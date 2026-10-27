#include "multidisplay_mac.h"

#include "SDL_compat.h"
#include <SDL_syswm.h>

#include <cmath>

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

namespace MultiDisplayMac
{

namespace
{
    NSScreen* screenFor(CGDirectDisplayID displayId)
    {
        for (NSScreen* screen in NSScreen.screens) {
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == displayId) {
                return screen;
            }
        }
        return nil;
    }

    NSWindow* nsWindowFor(SDL_Window* window)
    {
        SDL_SysWMinfo info;
        SDL_VERSION(&info.version);
        if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) {
            return nil;
        }
        return info.info.cocoa.window;
    }

    id s_LaunchObserver = nil;
    id s_ActivationObserver = nil;
}

bool screensHaveSeparateSpaces()
{
    return NSScreen.screensHaveSeparateSpaces;
}

bool helperFrame(uint32_t displayId, int& x, int& y, int& width, int& height)
{
    CGRect bounds = CGDisplayBounds(displayId);
    if (CGRectIsEmpty(bounds)) {
        return false;
    }

    // The strip beside a notch is the menu bar's; the stream goes below it, as fullscreen video does
    double notch = 0;
    @autoreleasepool {
        NSScreen* screen = screenFor(displayId);
        if (screen != nil) {
            notch = screen.safeAreaInsets.top;
        }
    }

    x = static_cast<int>(std::lround(bounds.origin.x));
    y = static_cast<int>(std::lround(bounds.origin.y + notch));
    width = static_cast<int>(std::lround(bounds.size.width));
    height = static_cast<int>(std::lround(bounds.size.height - notch));
    return width > 0 && height > 0;
}

void becomeBackgroundApp()
{
    // SDL doesn't make itself the active app at startup with this, nor set the regular policy
    SDL_SetHint(SDL_HINT_MAC_BACKGROUND_APP, "1");

    @autoreleasepool {
        // SDL makes NSApp when its video starts (making it here would keep SDL from finishing its
        // launch); keep it out of the Dock and the app switcher as it launches
        s_LaunchObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillFinishLaunchingNotification
                                                                              object:nil
                                                                               queue:nil
                                                                          usingBlock:^(NSNotification*) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }];
        [s_LaunchObserver retain];

        // Qt's cocoa platform (the fallback without the offscreen plugin) made it already
        if (NSApp != nil) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }

        // macOS activates an app whose window is clicked. Hand that straight back to the main
        // stream: an active app may activate another, even under macOS 14's cooperative activation.
        pid_t mainPid = getppid();
        s_ActivationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification
                                                                                  object:nil
                                                                                   queue:nil
                                                                              usingBlock:^(NSNotification*) {
            NSRunningApplication* main = [NSRunningApplication runningApplicationWithProcessIdentifier:mainPid];
            if (main != nil) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Helper became the active app; handing that back to the main stream");
                // Under macOS 14's cooperative activation an app hands activation over by yielding it
                // first; activating the other app alone can leave neither in front
                if (@available(macOS 14.0, *)) {
                    [NSApp yieldActivationToApplication:main];
                }
                [main activateWithOptions:0];
            }
        }];
        [s_ActivationObserver retain];
    }
}

pid_t activePid()
{
    @autoreleasepool {
        NSRunningApplication* active = NSWorkspace.sharedWorkspace.frontmostApplication;
        return active != nil ? active.processIdentifier : 0;
    }
}

std::string activeAppName()
{
    @autoreleasepool {
        NSRunningApplication* active = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (active == nil) {
            return "no app";
        }
        NSString* name = active.localizedName ?: active.bundleIdentifier ?: @"an app";
        return std::string(name.UTF8String ?: "an app") + " (pid " + std::to_string(active.processIdentifier) + ")";
    }
}

bool placeHelperWindow(SDL_Window* window, uint32_t displayId)
{
    int x, y, width, height;
    if (!helperFrame(displayId, x, y, width, height)) {
        return false;
    }

    @autoreleasepool {
        NSWindow* nsWindow = nsWindowFor(window);
        if (nsWindow == nil) {
            return false;
        }

        // Above the menu bar (NSMainMenuWindowLevel) and the Dock, but below the notch bar's panels
        nsWindow.level = NSStatusWindowLevel;
        nsWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                      NSWindowCollectionBehaviorStationary |
                                      NSWindowCollectionBehaviorIgnoresCycle |
                                      NSWindowCollectionBehaviorFullScreenAuxiliary;
        nsWindow.hidesOnDeactivate = NO;
        nsWindow.hasShadow = NO;

        // Cocoa's frames start at the bottom left of the main display
        CGFloat mainHeight = CGDisplayBounds(CGMainDisplayID()).size.height;
        NSRect frame = NSMakeRect(x, mainHeight - (y + height), width, height);
        [nsWindow setFrame:frame display:YES];
        [nsWindow orderFrontRegardless];
    }
    return true;
}

}
