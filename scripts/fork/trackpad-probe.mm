// LuzLunar: probe for what trackpad passthrough relies on, to check on a real Mac and again after
// a macOS update: AppKit's trackpad touches, MultitouchSupport's contact sizes for palm rejection,
// macOS's own pointer and scroll deltas for Mac trackpad mode, the Dock's gesture events
// (CGEventType 30) that the event tap drops, and System Settings' private MTTGestureBackEnd that
// switches the two other gestures off.
//
// Build (CI builds it too): clang++ -std=c++17 -fobjc-arc -Iapp/fork -framework AppKit \
//   -framework ApplicationServices scripts/fork/trackpad-probe.mm app/fork/forktrackpadgestures.cpp \
//   app/fork/forkmultitouch.cpp -o /tmp/trackpad-probe
//
//   trackpad-probe touches [--no-resting] [SECONDS]
//                                          a window that logs every trackpad touch AppKit gives it
//                                          (identity, phase, position, pad size, resting), with
//                                          resting touches asked for as LuzLunar does, or not
//   trackpad-probe mt [SECONDS]            the same touches with MultitouchSupport's contact for
//                                          each (hand part, axes) and the contacts AppKit leaves
//                                          out, to set palm rejection's thresholds
//   trackpad-probe pointer [SECONDS]       macOS's pointer deltas, precise scrolling (with its
//                                          momentum) and pinches, as Mac trackpad mode reads them
//   trackpad-probe tap [SECONDS]           logs the Dock's gesture events and their non-zero fields,
//                                          to find the one that tells a gesture's start from its end
//   trackpad-probe tap --drop [--arm-after S] [SECONDS]
//                                          drops them like LuzLunar does, armed from the start or
//                                          after S seconds (arm it in the middle of a swipe)
//   trackpad-probe mtt list                MTTGestureBackEnd's methods and their type encodings
//   trackpad-probe mtt get NAME            calls the getter NAME (e.g. threeFingerDrag)
//   trackpad-probe mtt set NAME VALUE      calls the setter for NAME (e.g. threeFingerDrag 0)
//
// The event tap needs Accessibility for the app that runs this (Terminal, say).

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <objc/message.h>
#include <objc/runtime.h>

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "forkmultitouch.h"
#include "forktrackpadgestures.h"

static const int k_DockControlEventType = 30;

static double now()
{
    return [[NSProcessInfo processInfo] systemUptime];
}

static uint32_t nowMs()
{
    return static_cast<uint32_t>(now() * 1000.0);
}

// ---- touches -------------------------------------------------------------------------------

@interface ProbeView : NSView
@end

@implementation ProbeView
- (BOOL)acceptsFirstResponder { return YES; }
@end

static const char* phaseName(NSTouchPhase phase)
{
    switch (phase) {
    case NSTouchPhaseBegan: return "began";
    case NSTouchPhaseMoved: return "moved";
    case NSTouchPhaseStationary: return "stationary";
    case NSTouchPhaseEnded: return "ended";
    case NSTouchPhaseCancelled: return "cancelled";
    default: return "?";
    }
}

// A window over which the trackpad's touches are reported, as LuzLunar's stream window asks for them
static NSWindow* probeWindow(NSString* title, bool resting)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 640, 400)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = title;
    window.acceptsMouseMovedEvents = YES;
    ProbeView* view = [[ProbeView alloc] initWithFrame:window.contentView.bounds];
    view.allowedTouchTypes = NSTouchTypeMaskIndirect;
    view.wantsRestingTouches = resting ? YES : NO;
    window.contentView = view;
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return window;
}

static void runFor(NSWindow* window, double seconds)
{
    NSDate* until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0 && window.isVisible) {
        @autoreleasepool {
            NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]
                                                   inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event != nil) {
                [NSApp sendEvent:event];
            }
        }
    }
}

static void printTouch(NSTouch* t)
{
    std::printf("  id %lx device %lx %s %s pos %.4f,%.4f pad %.1fx%.1f pt%s",
                (unsigned long)[(id<NSObject>)t.identity hash], (unsigned long)[(id<NSObject>)t.device hash],
                t.type == NSTouchTypeIndirect ? "indirect" : "direct", phaseName(t.phase),
                t.normalizedPosition.x, t.normalizedPosition.y, t.deviceSize.width, t.deviceSize.height,
                t.isResting ? " resting" : "");
}

static int touches(double seconds, bool resting)
{
    NSWindow* window = probeWindow(@"trackpad-probe: touch the trackpad", resting);

    __block int events = 0;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskGesture handler:^NSEvent*(NSEvent* event) {
        NSSet<NSTouch*>* all = [event allTouches];
        std::printf("event %d type %ld at %.3f (%.1f ms old), %lu touches\n", ++events, (long)event.type,
                    event.timestamp, (now() - event.timestamp) * 1000.0, (unsigned long)all.count);
        for (NSTouch* t in all) {
            printTouch(t);
            std::printf("\n");
        }
        std::fflush(stdout);
        return event;
    }];

    std::printf("Touch the trackpad over the window for %.0f s (close it to stop); resting touches %s\n", seconds,
                resting ? "asked for" : "not asked for");
    runFor(window, seconds);
    std::printf("%d touch events\n", events);
    return events > 0 ? 0 : 1;
}

// ---- mt ------------------------------------------------------------------------------------

static const char* handPart(int fingerId)
{
    switch (fingerId) {
    case 1: return "thumb";
    case 2: return "index";
    case 3: return "middle";
    case 4: return "ring";
    case 5: return "little";
    case 6:
    case 7: return "palm";
    default: return "unknown";
    }
}

static void printContact(const ForkMultitouch::Contact& c)
{
    std::printf("%s (fingerID %d) state %d minor %.1f mm major %.1f mm at %.4f,%.4f", handPart(c.fingerId), c.fingerId,
                c.state, c.minorAxisMm, c.majorAxisMm, c.x, c.y);
}

static int mt(double seconds)
{
    if (!ForkMultitouch::start()) {
        std::printf("MultitouchSupport didn't start: %s\n", ForkMultitouch::why().c_str());
        return 1;
    }
    NSWindow* window = probeWindow(@"trackpad-probe: rest a palm, a thumb, a fingertip", true);

    __block int events = 0;
    __block float widestFinger = 0;
    __block float narrowestPalm = 1000;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskGesture handler:^NSEvent*(NSEvent* event) {
        NSArray<NSTouch*>* all = [[event allTouches] allObjects];
        std::vector<ForkTrackpad::Touch> touches;
        for (NSTouch* t in all) {
            ForkTrackpad::Touch touch;
            touch.x = t.normalizedPosition.x;
            touch.y = t.normalizedPosition.y;
            touches.push_back(touch);
        }
        std::vector<ForkMultitouch::Contact> contacts = ForkMultitouch::contactsNow();
        ForkMultitouch::annotate(touches, contacts);

        std::printf("event %d at %.3f, %lu touches, %zu contacts\n", ++events, event.timestamp, (unsigned long)all.count,
                    contacts.size());
        for (NSUInteger i = 0; i < all.count; i++) {
            printTouch(all[i]);
            const ForkTrackpad::Touch& touch = touches[i];
            if (touch.hasContact) {
                std::printf(" -> %s, minor %.1f mm\n", handPart(touch.fingerId), touch.minorAxisMm);
            }
            else {
                std::printf(" -> no contact\n");
            }
        }
        for (const ForkMultitouch::Contact& c : contacts) {
            std::printf("  contact ");
            printContact(c);
            std::printf("\n");
            if (!ForkMultitouch::touchingState(c.state)) {
                continue;
            }
            if (c.fingerId >= 2 && c.fingerId <= 5 && c.minorAxisMm > widestFinger) {
                widestFinger = c.minorAxisMm;
            }
            if ((c.fingerId == 6 || c.fingerId == 7) && c.minorAxisMm < narrowestPalm) {
                narrowestPalm = c.minorAxisMm;
            }
        }
        std::fflush(stdout);
        return event;
    }];

    std::printf("Over the window for %.0f s (close it to stop): rest your palm as you type and as you point, rest a "
                "thumb as you click, then touch with a fingertip and a flat finger\n", seconds);
    runFor(window, seconds);
    ForkMultitouch::stop();
    std::printf("%d touch events. Widest finger %.1f mm, narrowest palm %.1f mm (LuzLunar calls %.1f mm a palm)\n",
                events, widestFinger, narrowestPalm < 1000 ? narrowestPalm : 0.0f, ForkTrackpad::k_PalmMinorMm);
    std::string why = ForkMultitouch::why();
    if (!why.empty() && why != "stopped") {
        std::printf("MultitouchSupport: %s\n", why.c_str());
    }
    return events > 0 ? 0 : 1;
}

// ---- pointer -------------------------------------------------------------------------------

static const char* eventPhase(NSEventPhase phase)
{
    switch (phase) {
    case NSEventPhaseNone: return "-";
    case NSEventPhaseBegan: return "began";
    case NSEventPhaseStationary: return "stationary";
    case NSEventPhaseChanged: return "changed";
    case NSEventPhaseEnded: return "ended";
    case NSEventPhaseCancelled: return "cancelled";
    case NSEventPhaseMayBegin: return "may-begin";
    default: return "?";
    }
}

static int pointerProbe(double seconds)
{
    NSWindow* window = probeWindow(@"trackpad-probe: point, scroll and pinch", true);

    __block int events = 0;
    __block double movedX = 0;
    __block double movedY = 0;
    NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged |
                       NSEventMaskScrollWheel | NSEventMaskMagnify;
    [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent*(NSEvent* event) {
        events++;
        if (event.type == NSEventTypeScrollWheel) {
            std::printf("scroll %s%.2f,%.2f pt, phase %s, momentum %s%s\n", event.hasPreciseScrollingDeltas ? "" : "(lines) ",
                        event.scrollingDeltaX, event.scrollingDeltaY, eventPhase(event.phase), eventPhase(event.momentumPhase),
                        event.directionInvertedFromDevice ? ", natural" : "");
        }
        else if (event.type == NSEventTypeMagnify) {
            std::printf("pinch %+.4f, phase %s\n", event.magnification, eventPhase(event.phase));
        }
        else {
            movedX += event.deltaX;
            movedY += event.deltaY;
            std::printf("pointer %+.2f,%+.2f pt (%.1f,%.1f so far)\n", event.deltaX, event.deltaY, movedX, movedY);
        }
        std::fflush(stdout);
        return event;
    }];

    std::printf("Over the window for %.0f s (close it to stop): move a finger across the trackpad at one speed with "
                "the tracking speed slider low, then high; scroll and fling; pinch\n", seconds);
    runFor(window, seconds);
    std::printf("%d events\n", events);
    return events > 0 ? 0 : 1;
}

// ---- tap -----------------------------------------------------------------------------------

static CFMachPortRef s_Tap;
static bool s_Drop;
static double s_ArmAt;
static ForkTrackpadGestures::DockGestureFilter s_Filter;
static int s_Seen;
static int s_Dropped;

static CGEventRef tapCallback(CGEventTapProxy, CGEventType type, CGEventRef event, void*)
{
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        std::printf("tap disabled by macOS (%s); enabling again\n", type == kCGEventTapDisabledByTimeout ? "timeout" : "user input");
        CGEventTapEnable(s_Tap, true);
        return event;
    }
    if (static_cast<int>(type) != k_DockControlEventType) {
        return event;
    }

    s_Seen++;
    std::printf("dock event %d at %.3f:", s_Seen, now());
    for (int field = 0; field < 256; field++) {
        int64_t value = CGEventGetIntegerValueField(event, static_cast<CGEventField>(field));
        if (value != 0) {
            std::printf(" %d=%lld", field, (long long)value);
        }
    }

    bool drop = false;
    if (s_Drop) {
        if (!s_Filter.armed() && now() >= s_ArmAt) {
            s_Filter.setArmed(true);
            std::printf(" [armed]");
        }
        drop = s_Filter.swallow(nowMs());
    }
    if (drop) {
        s_Dropped++;
    }
    std::printf("%s\n", drop ? " DROPPED" : "");
    std::fflush(stdout);
    return drop ? nullptr : event;
}

static int tap(double seconds)
{
    if (!AXIsProcessTrusted()) {
        std::printf("No Accessibility permission for this program (or the terminal running it)\n");
        return 1;
    }
    CGEventMask mask = CGEventMaskBit(k_DockControlEventType);
    CGEventTapOptions options = s_Drop ? kCGEventTapOptionDefault : kCGEventTapOptionListenOnly;
    const char* where = "HID";
    s_Tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, options, mask, tapCallback, nullptr);
    if (s_Tap == nullptr) {
        where = "session";
        s_Tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, options, mask, tapCallback, nullptr);
    }
    if (s_Tap == nullptr) {
        std::printf("CGEventTapCreate failed\n");
        return 1;
    }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, s_Tap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(s_Tap, true);

    std::printf("Tap at the %s level, %s, for %.0f s. Swipe with three and four fingers, pinch, spread.\n",
                where, s_Drop ? "dropping" : "listening", seconds);
    std::fflush(stdout);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);

    std::printf("%d dock events, %d dropped\n", s_Seen, s_Dropped);
    CGEventTapEnable(s_Tap, false);
    CFRelease(source);
    CFRelease(s_Tap);
    return 0;
}

// ---- mtt -----------------------------------------------------------------------------------

static id backEnd()
{
    NSBundle* bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PreferencePanesSupport.framework"];
    if (bundle == nil || ![bundle load]) {
        std::printf("PreferencePanesSupport.framework didn't load\n");
        return nil;
    }
    Class cls = NSClassFromString(@"MTTGestureBackEnd");
    if (cls == nil) {
        std::printf("No MTTGestureBackEnd class\n");
        return nil;
    }
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (![cls respondsToSelector:shared]) {
        std::printf("MTTGestureBackEnd has no +sharedInstance\n");
        return nil;
    }
    id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return send(cls, shared);
}

static void listMethods(Class cls, const char* prefix)
{
    unsigned int count = 0;
    Method* methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        std::printf("%s%s  %s\n", prefix, sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
    }
    free(methods);
}

static int mtt(int argc, char** argv)
{
    if (argc < 1) {
        return 2;
    }
    id target = backEnd();
    if (target == nil) {
        return 1;
    }

    if (std::strcmp(argv[0], "list") == 0) {
        for (Class cls = [target class]; cls != nil && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
            std::printf("%s:\n", class_getName(cls));
            listMethods(object_getClass(cls), "  +");
            listMethods(cls, "  -");
        }
        return 0;
    }

    if (std::strcmp(argv[0], "get") == 0 && argc >= 2) {
        SEL getter = sel_registerName(argv[1]);
        if (![target respondsToSelector:getter]) {
            std::printf("No getter %s\n", argv[1]);
            return 1;
        }
        NSMethodSignature* sig = [target methodSignatureForSelector:getter];
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = target;
        inv.selector = getter;
        [inv invoke];
        long long value = 0;
        if (sig.methodReturnLength <= sizeof(value)) {
            [inv getReturnValue:&value];
        }
        std::printf("%s (%s) = %lld\n", argv[1], sig.methodReturnType, value);
        return 0;
    }

    if (std::strcmp(argv[0], "set") == 0 && argc >= 3) {
        std::string name = argv[1];
        std::string setter = "set" + std::string(1, static_cast<char>(std::toupper(name[0]))) + name.substr(1) + ":";
        SEL sel = sel_registerName(setter.c_str());
        if (![target respondsToSelector:sel]) {
            std::printf("No setter %s\n", setter.c_str());
            return 1;
        }
        NSMethodSignature* sig = [target methodSignatureForSelector:sel];
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = target;
        inv.selector = sel;
        long long value = std::atoll(argv[2]);
        // The argument is read at the size its type takes, which works on little-endian Macs
        [inv setArgument:&value atIndex:2];
        [inv invoke];
        std::printf("%s(%lld) called (argument type %s). Check System Settings › Trackpad, without logging out.\n",
                    setter.c_str(), value, [sig getArgumentTypeAtIndex:2]);
        return 0;
    }

    return 2;
}

int main(int argc, char** argv)
{
    @autoreleasepool {
        if (argc >= 2 && std::strcmp(argv[1], "touches") == 0) {
            bool resting = true;
            double seconds = 30;
            for (int i = 2; i < argc; i++) {
                if (std::strcmp(argv[i], "--no-resting") == 0) {
                    resting = false;
                }
                else {
                    seconds = std::atof(argv[i]);
                }
            }
            return touches(seconds, resting);
        }
        if (argc >= 2 && std::strcmp(argv[1], "mt") == 0) {
            return mt(argc >= 3 ? std::atof(argv[2]) : 60);
        }
        if (argc >= 2 && std::strcmp(argv[1], "pointer") == 0) {
            return pointerProbe(argc >= 3 ? std::atof(argv[2]) : 30);
        }
        if (argc >= 2 && std::strcmp(argv[1], "tap") == 0) {
            double seconds = 30;
            s_ArmAt = 0;
            for (int i = 2; i < argc; i++) {
                if (std::strcmp(argv[i], "--drop") == 0) {
                    s_Drop = true;
                }
                else if (std::strcmp(argv[i], "--arm-after") == 0 && i + 1 < argc) {
                    s_ArmAt = now() + std::atof(argv[++i]);
                }
                else {
                    seconds = std::atof(argv[i]);
                }
            }
            return tap(seconds);
        }
        if (argc >= 3 && std::strcmp(argv[1], "mtt") == 0) {
            int status = mtt(argc - 2, argv + 2);
            if (status == 2) {
                std::printf("usage: trackpad-probe mtt list | get NAME | set NAME VALUE\n");
            }
            return status;
        }
        std::printf("usage: trackpad-probe touches [--no-resting] [SECONDS] | mt [SECONDS] | pointer [SECONDS] | "
                    "tap [--drop] [--arm-after S] [SECONDS] | mtt ...\n");
        return 2;
    }
}
