#include "forkvideoscaling.h"

#include "forkpolicy.h"
#include "forkpreferences.h"
#include "settings/streamingpreferences.h"
#include "streaming/streamutils.h"
#include "SDL_compat.h"

#include <QGuiApplication>
#include <QScreen>
#include <QWindow>

#include <atomic>

#ifdef Q_OS_DARWIN
#include <ApplicationServices/ApplicationServices.h>
#include <cmath>
#endif

namespace ForkVideoScaling
{

namespace
{
    // The stream's window while its fullscreenStretch preference is on, null otherwise
    std::atomic<SDL_Window*> s_StretchWindow { nullptr };

    // Whether the last stretchActive() answer was on (1) or off (0), so the log only has changes
    std::atomic<int> s_LastStretch { 0 };

#ifdef Q_OS_DARWIN
    // The index of the display with the given top-left corner, in the order StreamUtils uses
    // (CGGetActiveDisplayList). Qt and CoreGraphics both use points with a top-left origin.
    int displayIndexAt(QPoint topLeft)
    {
        constexpr uint32_t maxDisplays = 16;
        CGDirectDisplayID displayIds[maxDisplays];
        uint32_t displayCount = 0;
        if (CGGetActiveDisplayList(maxDisplays, displayIds, &displayCount) != kCGErrorSuccess) {
            return -1;
        }

        for (uint32_t i = 0; i < displayCount; i++) {
            CGRect bounds = CGDisplayBounds(displayIds[i]);
            if (std::fabs(bounds.origin.x - topLeft.x()) < 1 && std::fabs(bounds.origin.y - topLeft.y()) < 1) {
                return static_cast<int>(i);
            }
        }
        return -1;
    }
#endif
}

int displayIndexFor(QWindow* qtWindow)
{
#ifdef Q_OS_DARWIN
    QScreen* screen = qtWindow != nullptr ? qtWindow->screen() : QGuiApplication::primaryScreen();
    return screen != nullptr ? displayIndexAt(screen->geometry().topLeft()) : -1;
#else
    (void)qtWindow;
    return -1;
#endif
}

bool useSpacesFullscreen(bool upstream, const StreamingPreferences& prefs, QWindow* qtWindow)
{
#ifdef Q_OS_DARWIN
    int displayIndex = displayIndexFor(qtWindow);
    if (displayIndex < 0) {
        return upstream;
    }

    SDL_DisplayMode nativeMode;
    SDL_Rect safeArea;
    if (!StreamUtils::getNativeDesktopMode(displayIndex, &nativeMode, &safeArea)) {
        return upstream;
    }

    bool hasNotch = nativeMode.w != safeArea.w || nativeMode.h != safeArea.h;
    ForkPolicy::NotchFit fit = ForkPolicy::notchFit(prefs.width, prefs.height, nativeMode.w, nativeMode.h,
                                                    safeArea.w, safeArea.h);

    // Stretch never draws under the notch, so it keeps the stream below it like the bar does
    bool barOn = ForkPreferences::get()->notchBar();
    bool useSpaces = ForkPolicy::useSpacesFullscreen(upstream, hasNotch, barOn || prefs.fullscreenStretch, fit);
    if (useSpaces != upstream) {
        const char* reason = fit == ForkPolicy::NotchFit::FullDisplay ? "it has the full display's aspect ratio" :
                             fit == ForkPolicy::NotchFit::BelowNotch ? "it has the aspect ratio below the notch" :
                             barOn && prefs.fullscreenStretch ? "the notch bar needs the strip beside the notch and a stretched picture can't go under it" :
                             barOn ? "the notch bar needs the strip beside the notch" :
                                     "a stretched picture can't go under the notch";
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Streaming %dx%d fullscreen %s the notch: %s",
                    prefs.width, prefs.height, useSpaces ? "below" : "under", reason);
    }
    return useSpaces;
#else
    (void)prefs;
    (void)qtWindow;
    return upstream;
#endif
}

void activate(SDL_Window* window, bool stretch)
{
    s_LastStretch.store(0);
    s_StretchWindow.store(stretch ? window : nullptr);
}

void deactivate()
{
    s_StretchWindow.store(nullptr);
    s_LastStretch.store(0);
}

bool stretchActive()
{
    SDL_Window* window = s_StretchWindow.load();

    // SDL_WINDOW_FULLSCREEN_DESKTOP includes SDL_WINDOW_FULLSCREEN's bit, so this matches both kinds
    bool fullscreen = window != nullptr && (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN_DESKTOP) != 0;
    bool active = ForkPolicy::stretchActive(window != nullptr, fullscreen);

    int state = active ? 1 : 0;
    if (s_LastStretch.exchange(state) != state) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Fullscreen stretch %s", active ? "on" : "off");
    }
    return active;
}

}
