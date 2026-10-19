#include "trackpadcapture_mac.h"

#include <cmath>
#include <utility>

#include <SDL_syswm.h>

#import <AppKit/AppKit.h>

namespace
{
    id s_Monitor = nil;
    id s_MacMonitor = nil;
    NSWindow* s_Window = nil;
    ForkTrackpadCapture::Handler s_Handler;
    ForkTrackpadCapture::MacInput s_MacInput;
    NSTouchTypeMask s_PreviousTouchTypes = 0;
    bool s_ChangedTouchTypes = false;
    BOOL s_PreviousRestingTouches = NO;
    bool s_ChangedRestingTouches = false;

    NSWindow* cocoaWindow(SDL_Window* window)
    {
        SDL_SysWMinfo info;
        SDL_VERSION(&info.version);
        if (window == nullptr || !SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) {
            return nil;
        }
        return info.info.cocoa.window;
    }

    // An event's timestamp counts seconds since the Mac started, like systemUptime; SDL's ticks
    // count milliseconds since SDL started
    std::uint32_t sdlTicks(NSTimeInterval timestamp)
    {
        NSTimeInterval age = [[NSProcessInfo processInfo] systemUptime] - timestamp;
        if (age < 0) {
            age = 0;
        }
        return SDL_GetTicks() - static_cast<std::uint32_t>(std::llround(age * 1000.0));
    }

    ForkTrackpad::TouchPhase phaseOf(NSTouchPhase phase)
    {
        switch (phase) {
        case NSTouchPhaseBegan:
            return ForkTrackpad::TouchPhase::Began;
        case NSTouchPhaseStationary:
            return ForkTrackpad::TouchPhase::Stationary;
        case NSTouchPhaseEnded:
            return ForkTrackpad::TouchPhase::Ended;
        case NSTouchPhaseCancelled:
            return ForkTrackpad::TouchPhase::Cancelled;
        case NSTouchPhaseMoved:
        default:
            return ForkTrackpad::TouchPhase::Moved;
        }
    }

    // The stream window's events. With the pointer held in relative mode, motion and pinches can
    // come without a window while the stream window is key.
    bool inStreamWindow(NSEvent* event)
    {
        return event.window == s_Window || (event.window == nil && [s_Window isKeyWindow]);
    }
}

bool ForkTrackpadCapture::start(SDL_Window* window, Handler handler, MacInput mac)
{
    stop();

    NSWindow* nsWindow = cocoaWindow(window);
    if (nsWindow == nil) {
        return false;
    }
    s_Window = [nsWindow retain];
    s_Handler = std::move(handler);
    s_MacInput = std::move(mac);

    // SDL's view takes trackpad touches already; make sure it does, since the events only carry
    // touches for views that accept them. It also gets resting touches, so one that starts or
    // stops resting isn't reported as a lift and a new touch.
    NSView* view = nsWindow.contentView;
    if (view != nil && !(view.allowedTouchTypes & NSTouchTypeMaskIndirect)) {
        s_PreviousTouchTypes = view.allowedTouchTypes;
        view.allowedTouchTypes = s_PreviousTouchTypes | NSTouchTypeMaskIndirect;
        s_ChangedTouchTypes = true;
    }
    if (view != nil && !view.wantsRestingTouches) {
        s_PreviousRestingTouches = view.wantsRestingTouches;
        view.wantsRestingTouches = YES;
        s_ChangedRestingTouches = true;
    }

    // Local monitors run from -[NSApplication sendEvent:], on the main thread like the stream's
    // event loop. The event goes on to SDL unchanged.
    s_Monitor = [[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskGesture | NSEventMaskMagnify
                                                       handler:^NSEvent*(NSEvent* event) {
        if (event.type == NSEventTypeMagnify) {
            if (event.phase == NSEventPhaseBegan && s_MacInput.pinchBegan && inStreamWindow(event)) {
                s_MacInput.pinchBegan(sdlTicks(event.timestamp));
            }
            return event;
        }

        if (event.window != s_Window || !s_Handler) {
            return event;
        }

        std::vector<ForkTrackpad::Touch> touches;
        for (NSTouch* touch in [event allTouches]) {
            if (touch.type != NSTouchTypeIndirect) {
                continue;
            }
            ForkTrackpad::Touch t;
            // Identities are compared with isEqual:, so equal ones share a hash
            t.identity = static_cast<std::uintptr_t>([(id<NSObject>)touch.identity hash]);
            t.device = static_cast<std::uintptr_t>([(id<NSObject>)touch.device hash]);
            t.phase = phaseOf(touch.phase);
            t.x = touch.normalizedPosition.x;
            t.y = touch.normalizedPosition.y;
            t.deviceWidth = touch.deviceSize.width;
            t.deviceHeight = touch.deviceSize.height;
            t.resting = touch.isResting;
            touches.push_back(t);
        }
        if (!touches.empty()) {
            s_Handler(touches, sdlTicks(event.timestamp));
        }
        return event;
    }] retain];

    // Mac trackpad mode: macOS's own pointer motion and scrolling, read before SDL turns them
    // into whole points and lines
    if (s_MacInput.pointer || s_MacInput.scroll) {
        NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged |
                           NSEventMaskOtherMouseDragged | NSEventMaskScrollWheel;
        s_MacMonitor = [[NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent*(NSEvent* event) {
            if (!inStreamWindow(event)) {
                return event;
            }
            if (event.type == NSEventTypeScrollWheel) {
                // A mouse wheel's lines stay SDL's
                if (event.hasPreciseScrollingDeltas && s_MacInput.scroll &&
                        s_MacInput.scroll(-event.scrollingDeltaX, event.scrollingDeltaY, sdlTicks(event.timestamp))) {
                    return nil;
                }
                return event;
            }
            if (s_MacInput.pointer) {
                s_MacInput.pointer(event.deltaX, event.deltaY, sdlTicks(event.timestamp));
            }
            return event;
        }] retain];
    }

    return s_Monitor != nil;
}

void ForkTrackpadCapture::stop()
{
    if (s_Monitor != nil) {
        [NSEvent removeMonitor:s_Monitor];
        [s_Monitor release];
        s_Monitor = nil;
    }
    if (s_MacMonitor != nil) {
        [NSEvent removeMonitor:s_MacMonitor];
        [s_MacMonitor release];
        s_MacMonitor = nil;
    }
    if (s_Window != nil) {
        NSView* view = s_Window.contentView;
        if (s_ChangedTouchTypes && view != nil) {
            view.allowedTouchTypes = s_PreviousTouchTypes;
        }
        if (s_ChangedRestingTouches && view != nil) {
            view.wantsRestingTouches = s_PreviousRestingTouches;
        }
        [s_Window release];
        s_Window = nil;
    }
    s_ChangedTouchTypes = false;
    s_ChangedRestingTouches = false;
    s_Handler = nullptr;
    s_MacInput = MacInput();
}

bool ForkTrackpadCapture::streamWindowIsKey()
{
    return s_Window != nil && [NSApp isActive] && [s_Window isKeyWindow];
}
