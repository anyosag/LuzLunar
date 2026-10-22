#include "displaytiming.h"

#include "SDL_compat.h"
#include <SDL_syswm.h>

#import <AppKit/AppKit.h>

int DisplayTiming::maximumRefreshRate(SDL_Window* window)
{
    if (window == nullptr || ![NSThread isMainThread]) {
        return 0;
    }
    @autoreleasepool {
        if (@available(macOS 12.0, *)) {
            SDL_SysWMinfo info;
            SDL_VERSION(&info.version);
            if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) {
                return 0;
            }
            NSScreen* screen = info.info.cocoa.window.screen;
            if (screen == nil) {
                screen = [NSScreen mainScreen];
            }
            return screen != nil ? static_cast<int>(screen.maximumFramesPerSecond) : 0;
        }
    }
    return 0;
}
