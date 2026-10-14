#include "forkvideoscaling.h"

#include "forkpolicy.h"
#include "forkpreferences.h"
#include "settings/streamingpreferences.h"
#include "streaming/streamutils.h"
#include "SDL_compat.h"

#include <QGuiApplication>
#include <QScreen>
#include <QWindow>

#ifdef Q_OS_DARWIN
#include <ApplicationServices/ApplicationServices.h>
#include <cmath>
#endif

namespace ForkVideoScaling
{

namespace
{
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

bool useSpacesFullscreen(bool upstream, const StreamingPreferences& prefs, QWindow* qtWindow)
{
#ifdef Q_OS_DARWIN
    QScreen* screen = qtWindow != nullptr ? qtWindow->screen() : QGuiApplication::primaryScreen();
    if (screen == nullptr) {
        return upstream;
    }

    int displayIndex = displayIndexAt(screen->geometry().topLeft());
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
    bool useSpaces = ForkPolicy::useSpacesFullscreen(upstream, hasNotch, ForkPreferences::get()->notchBar(), fit);
    if (useSpaces != upstream) {
        const char* reason = fit == ForkPolicy::NotchFit::FullDisplay ? "it has the full display's aspect ratio" :
                             fit == ForkPolicy::NotchFit::BelowNotch ? "it has the aspect ratio below the notch" :
                                                                       "the notch bar needs the strip beside the notch";
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

}
