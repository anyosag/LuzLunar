#pragma once

// Decisions behind the fork's fullscreen handling, kept free of Qt, SDL and AppKit so they can
// be unit tested on their own (tests/fork/policy_test.cpp).
namespace ForkPolicy
{
    // A display with a notch has two shapes: the full panel, including the strip beside the notch
    // (3024x1964, about 1.54:1, on a 14" MacBook Pro), and the area below the notch (3024x1890, 16:10)
    enum class NotchFit {
        FullDisplay,    // the stream has the full panel's aspect ratio
        BelowNotch,     // the stream has the aspect ratio of the area below the notch
        Other,
    };

    // Which of the display's shapes a stream of this size matches, at any scale. tolerance is
    // relative, so even-rounded sizes like 756x490 still match.
    NotchFit notchFit(int streamWidth, int streamHeight, int fullWidth, int fullHeight,
                      int safeWidth, int safeHeight, double tolerance = 0.01);

    // Whether the stream should go fullscreen in a macOS Space (video below the notch) rather
    // than in a borderless window the size of the screen (video under the notch). upstream is
    // Moonlight's own choice, which only matches the two native sizes exactly. On a notched
    // display a stream with either shape's aspect ratio fills that shape, at any size. Any other
    // ratio goes below the notch while keepBelowNotch (the notch bar is on), because only a Space
    // leaves the strip beside the notch for the bar.
    bool useSpacesFullscreen(bool upstream, bool displayHasNotch, bool keepBelowNotch, NotchFit fit);

    // A frame in screen coordinates; all that matters is that both rects use the same ones
    struct Rect {
        double x, y, w, h;
    };

    // Whether a window fills its screen without being in a fullscreen Space. A title bar rules it
    // out, since a window with one is an ordinary windowed stream. Each edge may be a little off.
    bool coversScreen(const Rect& window, const Rect& screen, bool hasTitleBar, double tolerance = 2.0);
}
