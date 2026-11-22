#pragma once

#include <string>

#include "forkhwrules.h"

// What LuzLunar tells an Apollo host about the Mac screen a stream shows on, so the virtual display
// the host creates (with anyosag/LuzVDA) describes that screen: its physical size, color gamut, HDR
// brightness and shapes. Windows then picks a fitting scale and tone-maps HDR for this screen rather
// than a generic one. Kept free of Qt and AppKit so it can be unit tested on its own
// (tests/fork/clientdisplay_test.cpp); ForkLaunchArgs reads the screen and sends the arguments.
namespace ClientDisplay
{
    struct Description {
        int widthMm = 0, heightMm = 0;             // physical size; 0 if unknown
        int panelWidth = 0, panelHeight = 0;       // the full panel, in pixels
        int safeWidth = 0, safeHeight = 0;         // below the notch; the panel's size without one
        int maxRefresh = 0;                        // Hz; 0 if unknown
        bool p3 = false;                           // Display P3 primaries rather than sRGB
        bool hdr = false;
        // Known only for panels LuzLunar recognizes or when the user sets a peak; 0 otherwise, which
        // leaves the host's default
        int peakNits = 0, fullFrameNits = 0;
        int minLuminance = 0;                      // 1/10000 nits
        double edrPotential = 1;                   // reported for the host's log
        std::string name;
    };

    // The peak a user setting gives, or 0 to work it out from the screen
    Description describe(const ForkHwRules::Display& display, bool builtin, int peakNitsOverride);

    // The /launch and /resume query arguments, each starting with "&". Hosts that don't know them
    // ignore them.
    std::string queryArgs(const Description& description);

    // Percent-encodes everything but letters, digits and "-._~"
    std::string percentEncode(const std::string& text);

    // "&luzPrimary=1" when this Mac's screen should be the PC's primary display, else empty. Apollo's
    // Virtual Display app then makes it so, with the PC's displays still on beside it, until the app
    // is quit; other apps and hosts ignore it. The name is Apollo's vdisplay_primary_policy::k_arg.
    std::string primaryArg(bool primary);
}
