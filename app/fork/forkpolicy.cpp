#include "forkpolicy.h"

#include <cmath>

namespace ForkPolicy
{

bool useSpacesFullscreen(bool upstream, bool displayHasNotch, bool keepBelowNotch, bool exactNative)
{
    return upstream || (displayHasNotch && keepBelowNotch && !exactNative);
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
