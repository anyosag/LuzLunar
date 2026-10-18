#include "trackpadcapture_mac.h"

#include <cmath>
#include <utility>

#include <SDL_syswm.h>

#import <AppKit/AppKit.h>

namespace
{
    id s_Monitor = nil;
    NSWindow* s_Window = nil;
    ForkTrackpadCapture::Handler s_Handler;
    NSTouchTypeMask s_PreviousTouchTypes = 0;
    bool s_ChangedTouchTypes = false;

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
}

bool ForkTrackpadCapture::start(SDL_Window* window, Handler handler)
{
    stop();

    NSWindow* nsWindow = cocoaWindow(window);
    if (nsWindow == nil) {
        return false;
    }
    s_Window = [nsWindow retain];
    s_Handler = std::move(handler);

    // SDL's view takes trackpad touches already; make sure it does, since the events only carry
    // touches for views that accept them
    NSView* view = nsWindow.contentView;
    if (view != nil && !(view.allowedTouchTypes & NSTouchTypeMaskIndirect)) {
        s_PreviousTouchTypes = view.allowedTouchTypes;
        view.allowedTouchTypes = s_PreviousTouchTypes | NSTouchTypeMaskIndirect;
        s_ChangedTouchTypes = true;
    }

    // Local monitors run from -[NSApplication sendEvent:], on the main thread like the stream's
    // event loop. The event goes on to SDL unchanged.
    s_Monitor = [[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskGesture
                                                       handler:^NSEvent*(NSEvent* event) {
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

    return s_Monitor != nil;
}

void ForkTrackpadCapture::stop()
{
    if (s_Monitor != nil) {
        [NSEvent removeMonitor:s_Monitor];
        [s_Monitor release];
        s_Monitor = nil;
    }
    if (s_Window != nil) {
        if (s_ChangedTouchTypes && s_Window.contentView != nil) {
            s_Window.contentView.allowedTouchTypes = s_PreviousTouchTypes;
        }
        [s_Window release];
        s_Window = nil;
    }
    s_ChangedTouchTypes = false;
    s_Handler = nullptr;
}

bool ForkTrackpadCapture::streamWindowIsKey()
{
    return s_Window != nil && [NSApp isActive] && [s_Window isKeyWindow];
}
