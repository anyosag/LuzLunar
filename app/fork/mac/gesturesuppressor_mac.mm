#include "gesturesuppressor_mac.h"

#include <atomic>
#include <cstring>
#include <future>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include <QCoreApplication>
#include <QSettings>

#include <unistd.h>

#include "SDL_compat.h"
#include "fork/forktrackpadgestures.h"
#include "macintegration.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <objc/runtime.h>

// The crash record of System Settings values a running LuzLunar switched off: "pid:edge=3/0,drag=1/0"
#define SER_TRACKPADHELDSETTINGS "fork/trackpadHeldSettings"

namespace
{
    // The Dock's gesture events. Not in CGEventTypes.h: the window server's private
    // kCGSEventDockControl, which AppKit also numbers 30.
    const int k_DockControlEventType = 30;

    // ---- The event tap ------------------------------------------------------------------

    std::mutex s_FilterLock;
    ForkTrackpadGestures::DockGestureFilter s_Filter;

    CFMachPortRef s_Tap = nullptr;
    CFRunLoopRef s_TapLoop = nullptr;
    std::thread s_TapThread;
    std::atomic<bool> s_TapRunning { false };
    std::atomic<bool> s_StopTap { false };

    CGEventRef tapCallback(CGEventTapProxy, CGEventType type, CGEventRef event, void*)
    {
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            // macOS turns a slow tap off; turn it back on
            if (s_Tap != nullptr) {
                CGEventTapEnable(s_Tap, true);
            }
            return event;
        }
        if (static_cast<int>(type) == k_DockControlEventType) {
            bool swallow;
            {
                std::lock_guard<std::mutex> lock(s_FilterLock);
                swallow = s_Filter.swallow(SDL_GetTicks());
            }
            return swallow ? nullptr : event;
        }
        return event;
    }

    void startTap()
    {
        if (!AXIsProcessTrusted()) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] No Accessibility permission, so macOS's trackpad gestures aren't held back during trackpad passthrough");
            return;
        }

        CGEventMask mask = CGEventMaskBit(k_DockControlEventType);
        CFMachPortRef tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                             mask, tapCallback, nullptr);
        if (tap == nullptr) {
            tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                   mask, tapCallback, nullptr);
        }
        if (tap == nullptr) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] macOS wouldn't let LuzLunar hold its trackpad gestures back (no event tap); if LuzLunar is "
                        "in Privacy & Security › Accessibility already, remove it and add it again");
            return;
        }

        s_Tap = tap;
        s_StopTap = false;
        std::promise<CFRunLoopRef> ready;
        std::future<CFRunLoopRef> loop = ready.get_future();

        // Its own thread, so a busy stream loop can't make macOS time the tap out
        s_TapThread = std::thread([tap, &ready]() {
            CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
            CFRunLoopRef current = CFRunLoopGetCurrent();
            CFRunLoopAddSource(current, source, kCFRunLoopCommonModes);
            CGEventTapEnable(tap, true);
            ready.set_value(static_cast<CFRunLoopRef>(const_cast<void*>(CFRetain(current))));
            while (!s_StopTap) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
            }
            CFRunLoopRemoveSource(current, source, kCFRunLoopCommonModes);
            CFRelease(source);
        });
        s_TapLoop = loop.get();
        s_TapRunning = true;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Ready to hold macOS's trackpad gestures back");
    }

    void stopTap()
    {
        if (!s_TapRunning) {
            return;
        }
        CGEventTapEnable(s_Tap, false);
        s_StopTap = true;
        CFRunLoopStop(s_TapLoop);
        if (s_TapThread.joinable()) {
            s_TapThread.join();
        }
        CFMachPortInvalidate(s_Tap);
        CFRelease(s_Tap);
        s_Tap = nullptr;
        CFRelease(s_TapLoop);
        s_TapLoop = nullptr;
        s_TapRunning = false;
    }

    // ---- System Settings' trackpad code ---------------------------------------------------

    struct Selectors {
        const char* name;  // in the crash record
        const char* getter;
        const char* setter;
        int off;
    };

    const Selectors k_Settings[] = {
        { "edge", "twoFingerFromRightEdgeSwipe", "setTwoFingerFromRightEdgeSwipe:", 0 },
        { "drag", "threeFingerDrag", "setThreeFingerDrag:", 0 },
    };

    const Selectors* findSetting(const std::string& name)
    {
        for (const Selectors& s : k_Settings) {
            if (name == s.name) {
                return &s;
            }
        }
        return nullptr;
    }

    // The object System Settings' Trackpad pane changes gestures through, or nil
    id gestureBackEnd()
    {
        static id s_Instance = nil;
        static bool s_Tried = false;
        if (s_Tried) {
            return s_Instance;
        }
        s_Tried = true;

        NSBundle* bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PreferencePanesSupport.framework"];
        if (bundle == nil || ![bundle load]) {
            return nil;
        }
        Class cls = NSClassFromString(@"MTTGestureBackEnd");
        SEL shared = NSSelectorFromString(@"sharedInstance");
        if (cls == nil || ![cls respondsToSelector:shared]) {
            return nil;
        }
        s_Instance = [[cls performSelector:shared] retain];
        return s_Instance;
    }

    // Skips Objective-C's type qualifiers (const, in, out...)
    const char* scalarType(const char* type)
    {
        while (*type != '\0' && std::strchr("rnNoORV", *type) != nullptr) {
            type++;
        }
        return type;
    }

    std::optional<int> callGetter(id target, SEL getter)
    {
        if (target == nil || ![target respondsToSelector:getter]) {
            return std::nullopt;
        }
        NSMethodSignature* sig = [target methodSignatureForSelector:getter];
        if (sig == nil || sig.numberOfArguments != 2) {
            return std::nullopt;
        }
        NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:sig];
        invocation.target = target;
        invocation.selector = getter;
        [invocation invoke];

        switch (scalarType(sig.methodReturnType)[0]) {
        case 'B': { bool v; [invocation getReturnValue:&v]; return v ? 1 : 0; }
        case 'c': { char v; [invocation getReturnValue:&v]; return v; }
        case 'C': { unsigned char v; [invocation getReturnValue:&v]; return v; }
        case 's': { short v; [invocation getReturnValue:&v]; return v; }
        case 'S': { unsigned short v; [invocation getReturnValue:&v]; return v; }
        case 'i': { int v; [invocation getReturnValue:&v]; return v; }
        case 'I': { unsigned int v; [invocation getReturnValue:&v]; return static_cast<int>(v); }
        case 'l': { long v; [invocation getReturnValue:&v]; return static_cast<int>(v); }
        case 'L': { unsigned long v; [invocation getReturnValue:&v]; return static_cast<int>(v); }
        case 'q': { long long v; [invocation getReturnValue:&v]; return static_cast<int>(v); }
        case 'Q': { unsigned long long v; [invocation getReturnValue:&v]; return static_cast<int>(v); }
        case '@': {
            id v = nil;
            [invocation getReturnValue:&v];
            if (v != nil && [v respondsToSelector:@selector(intValue)]) {
                return [v intValue];
            }
            return std::nullopt;
        }
        default:
            return std::nullopt;
        }
    }

    bool callSetter(id target, SEL setter, int value)
    {
        if (target == nil || ![target respondsToSelector:setter]) {
            return false;
        }
        NSMethodSignature* sig = [target methodSignatureForSelector:setter];
        if (sig == nil || sig.numberOfArguments != 3) {
            return false;
        }
        NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:sig];
        invocation.target = target;
        invocation.selector = setter;

        bool b = value != 0;
        char c = static_cast<char>(value);
        short s = static_cast<short>(value);
        int i = value;
        long l = value;
        long long q = value;
        NSNumber* number = [NSNumber numberWithInt:value];
        switch (scalarType([sig getArgumentTypeAtIndex:2])[0]) {
        case 'B': [invocation setArgument:&b atIndex:2]; break;
        case 'c': case 'C': [invocation setArgument:&c atIndex:2]; break;
        case 's': case 'S': [invocation setArgument:&s atIndex:2]; break;
        case 'i': case 'I': [invocation setArgument:&i atIndex:2]; break;
        case 'l': case 'L': [invocation setArgument:&l atIndex:2]; break;
        case 'q': case 'Q': [invocation setArgument:&q atIndex:2]; break;
        case '@': [invocation setArgument:&number atIndex:2]; break;
        default: return false;
        }
        [invocation invoke];
        return true;
    }

    // Writes a setting without letting the back end sync it to the user's other Macs, then puts
    // its sync setting back as it was
    bool writeLocally(id backEnd, SEL setter, int value)
    {
        SEL getSync = NSSelectorFromString(@"shouldSyncChangesToCloud");
        SEL setSync = NSSelectorFromString(@"setShouldSyncChangesToCloud:");
        std::optional<int> sync = callGetter(backEnd, getSync);
        bool syncOff = callSetter(backEnd, setSync, 0);
        bool written = callSetter(backEnd, setter, value);
        if (syncOff && sync && *sync != 0) {
            callSetter(backEnd, setSync, *sync);
        }
        return written;
    }

    ForkTrackpadGestures::HoldBackend holdBackend()
    {
        return ForkTrackpadGestures::HoldBackend {
            [](const std::string& name) -> std::optional<int> {
                const Selectors* s = findSetting(name);
                if (s == nullptr) {
                    return std::nullopt;
                }
                @autoreleasepool {
                    return callGetter(gestureBackEnd(), sel_registerName(s->getter));
                }
            },
            [](const std::string& name, int value) {
                const Selectors* s = findSetting(name);
                if (s == nullptr) {
                    return false;
                }
                @autoreleasepool {
                    bool ok = writeLocally(gestureBackEnd(), sel_registerName(s->setter), value);
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Set the Mac's trackpad setting %s to %d%s",
                                s->name, value, ok ? "" : " (failed)");
                    return ok;
                }
            },
            [](const std::string& record) {
                QSettings settings;
                if (record.empty()) {
                    settings.remove(SER_TRACKPADHELDSETTINGS);
                }
                else {
                    settings.setValue(SER_TRACKPADHELDSETTINGS, QString::fromStdString(record));
                }
                settings.sync();
            },
        };
    }

    bool settingsBackEndAvailable()
    {
        @autoreleasepool {
            id backEnd = gestureBackEnd();
            if (backEnd == nil) {
                return false;
            }
            for (const Selectors& s : k_Settings) {
                if (![backEnd respondsToSelector:sel_registerName(s.getter)] ||
                        ![backEnd respondsToSelector:sel_registerName(s.setter)]) {
                    return false;
                }
            }
            return true;
        }
    }

    std::unique_ptr<ForkTrackpadGestures::SettingsHold> s_Hold;

    void scheduleHoldTick()
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     static_cast<int64_t>(ForkTrackpadGestures::SettingsHold::k_ReleaseDelayMs + 50) * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (s_Hold) {
                s_Hold->tick(SDL_GetTicks());
            }
        });
    }

    // A LuzLunar that quit without putting the settings back: put them back now, unless that copy
    // is still running
    void startup()
    {
        QString record = QSettings().value(SER_TRACKPADHELDSETTINGS).toString();
        if (record.isEmpty()) {
            return;
        }
        if (ForkTrackpadGestures::restoreRecord(record.toStdString(), holdBackend(), MacIntegration::isRunningCopy)) {
            qInfo("[fork] Turned back on the Mac's trackpad gestures an earlier LuzLunar left off");
        }
    }
}

// Runs while the QGuiApplication is constructed, like ForkSystemShortcuts' own crash record
Q_COREAPP_STARTUP_FUNCTION(startup)

void ForkGestureSuppressor::start(bool pauseSettings)
{
    stop();
    startTap();

    if (pauseSettings) {
        if (settingsBackEndAvailable()) {
            std::vector<ForkTrackpadGestures::Setting> settings;
            for (const Selectors& s : k_Settings) {
                settings.push_back({ s.name, s.off });
            }
            s_Hold = std::make_unique<ForkTrackpadGestures::SettingsHold>(holdBackend(), settings, static_cast<long>(getpid()));
        }
        else {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] This macOS doesn't have System Settings' trackpad code LuzLunar uses, so Notification "
                        "Center's swipe and three-finger drag stay on during trackpad passthrough");
        }
    }
}

void ForkGestureSuppressor::stop()
{
    if (s_Hold) {
        s_Hold->releaseNow();
        s_Hold.reset();
    }
    {
        std::lock_guard<std::mutex> lock(s_FilterLock);
        s_Filter.setArmed(false);
    }
    stopTap();
}

void ForkGestureSuppressor::setArmed(bool armed)
{
    {
        std::lock_guard<std::mutex> lock(s_FilterLock);
        s_Filter.setArmed(armed);
    }
    if (s_Hold) {
        s_Hold->want(armed, SDL_GetTicks());
        if (!armed) {
            scheduleHoldTick();
        }
    }
}

bool ForkGestureSuppressor::tapRunning()
{
    return s_TapRunning;
}

bool ForkGestureSuppressor::accessibilityTrusted()
{
    return AXIsProcessTrusted();
}

void ForkGestureSuppressor::requestAccessibility()
{
    @autoreleasepool {
        NSDictionary* options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                            forKey:(id)kAXTrustedCheckOptionPrompt];
        AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
    }
}
