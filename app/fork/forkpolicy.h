#pragma once

// Decisions behind the fork's fullscreen handling, kept free of Qt, SDL and AppKit so they can
// be unit tested on their own (tests/fork/policy_test.cpp).
namespace ForkPolicy
{
    // Whether the stream should go fullscreen in a macOS Space (video below the notch) rather
    // than in a borderless window the size of the screen. upstream is Moonlight's own choice.
    // With the notch bar on, a notched display gets a Space for every size except the exact
    // native one, because only a Space leaves the strip beside the notch for the bar. Native
    // size is the user asking for video under the notch, so it keeps upstream's choice.
    bool useSpacesFullscreen(bool upstream, bool displayHasNotch, bool keepBelowNotch, bool exactNative);

    // A frame in screen coordinates; all that matters is that both rects use the same ones
    struct Rect {
        double x, y, w, h;
    };

    // Whether a window fills its screen without being in a fullscreen Space. A title bar rules it
    // out, since a window with one is an ordinary windowed stream. Each edge may be a little off.
    bool coversScreen(const Rect& window, const Rect& screen, bool hasTitleBar, double tolerance = 2.0);
}
