#include "forkpolicy.h"

#include <cmath>

namespace ForkPolicy
{

namespace
{
    bool sameRatio(int width, int height, int otherWidth, int otherHeight, double tolerance)
    {
        if (width <= 0 || height <= 0 || otherWidth <= 0 || otherHeight <= 0) {
            return false;
        }

        double ratio = static_cast<double>(width) / height;
        double otherRatio = static_cast<double>(otherWidth) / otherHeight;
        return std::fabs(ratio / otherRatio - 1) <= tolerance;
    }
}

NotchFit notchFit(int streamWidth, int streamHeight, int fullWidth, int fullHeight,
                  int safeWidth, int safeHeight, double tolerance)
{
    if (sameRatio(streamWidth, streamHeight, fullWidth, fullHeight, tolerance)) {
        return NotchFit::FullDisplay;
    }
    if (sameRatio(streamWidth, streamHeight, safeWidth, safeHeight, tolerance)) {
        return NotchFit::BelowNotch;
    }
    return NotchFit::Other;
}

bool useSpacesFullscreen(bool upstream, bool displayHasNotch, bool keepBelowNotch, NotchFit fit)
{
    if (!displayHasNotch) {
        return upstream;
    }

    switch (fit) {
    case NotchFit::FullDisplay:
        return false;
    case NotchFit::BelowNotch:
        return true;
    case NotchFit::Other:
        break;
    }
    return upstream || keepBelowNotch;
}

bool coversScreen(const Rect& window, const Rect& screen, bool hasTitleBar, double tolerance)
{
    if (hasTitleBar) {
        return false;
    }

    return std::fabs(window.x - screen.x) <= tolerance &&
           std::fabs(window.y - screen.y) <= tolerance &&
           std::fabs((window.x + window.w) - (screen.x + screen.w)) <= tolerance &&
           std::fabs((window.y + window.h) - (screen.y + screen.h)) <= tolerance;
}

}
