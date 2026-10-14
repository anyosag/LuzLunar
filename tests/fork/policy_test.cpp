// Unit tests for app/fork/forkpolicy.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/policy_test.cpp app/fork/forkpolicy.cpp
#include "fork/forkpolicy.h"

#include <cstdio>

using namespace ForkPolicy;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

int main()
{
    // A 14" MacBook Pro: the full panel is about 1.54:1, the area below the notch 16:10
    const int fullW = 3024, fullH = 1964, safeW = 3024, safeH = 1890;
    auto fit = [&](int w, int h) { return notchFit(w, h, fullW, fullH, safeW, safeH); };

    // The full panel's aspect ratio at any size, including even-rounded ones
    CHECK(fit(3024, 1964) == NotchFit::FullDisplay);
    CHECK(fit(2520, 1636) == NotchFit::FullDisplay);
    CHECK(fit(1512, 982) == NotchFit::FullDisplay);
    CHECK(fit(756, 490) == NotchFit::FullDisplay);

    // The aspect ratio below the notch (16:10) at any size
    CHECK(fit(3024, 1890) == NotchFit::BelowNotch);
    CHECK(fit(2560, 1600) == NotchFit::BelowNotch);
    CHECK(fit(1920, 1200) == NotchFit::BelowNotch);
    CHECK(fit(1512, 944) == NotchFit::BelowNotch);

    // Everything else, and sizes that make no sense
    CHECK(fit(2560, 1440) == NotchFit::Other);
    CHECK(fit(3440, 1440) == NotchFit::Other);
    CHECK(fit(2048, 1536) == NotchFit::Other);
    CHECK(fit(0, 1080) == NotchFit::Other);
    CHECK(notchFit(1920, 1080, 0, 0, 0, 0) == NotchFit::Other);

    // The two shapes are 3.9% apart, so the tolerance decides
    CHECK(notchFit(1920, 1200, fullW, fullH, safeW, safeH, 0.05) == NotchFit::FullDisplay);
    CHECK(notchFit(1512, 944, fullW, fullH, safeW, safeH, 0) == NotchFit::Other);

    // Every combination of (upstream, notch, bar on, fit). Without a notch upstream decides. With
    // one, either shape fills itself, and other ratios go below the notch while the bar is on.
    const NotchFit fits[] = { NotchFit::FullDisplay, NotchFit::BelowNotch, NotchFit::Other };
    for (int bits = 0; bits < 8; bits++) {
        for (NotchFit f : fits) {
            bool upstream = bits & 4;
            bool notch = bits & 2;
            bool barOn = bits & 1;
            bool expected = !notch ? upstream :
                            f == NotchFit::FullDisplay ? false :
                            f == NotchFit::BelowNotch ? true :
                                                        upstream || barOn;
            if (useSpacesFullscreen(upstream, notch, barOn, f) != expected) {
                std::printf("FAIL useSpacesFullscreen(upstream %d, notch %d, bar %d, fit %d) != %d\n",
                            upstream, notch, barOn, static_cast<int>(f), expected);
                s_Failures++;
            }
        }
    }

    // The case that matters: Fullscreen at 2560x1440 on a notched display with the bar on
    CHECK(useSpacesFullscreen(false, true, true, fit(2560, 1440)));
    // Without the bar, 16:9 keeps upstream's choice
    CHECK(!useSpacesFullscreen(false, true, false, fit(2560, 1440)));
    CHECK(useSpacesFullscreen(true, true, false, fit(2560, 1440)));
    // Half the native size fills the whole panel, even in Borderless windowed (upstream true)
    CHECK(!useSpacesFullscreen(true, true, true, fit(1512, 982)));
    // A smaller 16:10 size fills the area below the notch, with or without the bar
    CHECK(useSpacesFullscreen(false, true, false, fit(1920, 1200)));
    // No notch: upstream decides
    CHECK(!useSpacesFullscreen(false, false, true, NotchFit::Other));

    // A borderless window the size of the screen covers it
    const Rect screen = { 0, 0, 1512, 982 };
    CHECK(coversScreen(screen, screen, false));

    // One point off an edge still covers (rounding), five points off don't
    CHECK(coversScreen({ 1, 0, 1511, 982 }, screen, false));
    CHECK(coversScreen({ 0, 0, 1513, 983 }, screen, false));
    CHECK(coversScreen({ 0, 1, 1512, 981 }, screen, false));
    CHECK(!coversScreen({ 5, 0, 1507, 982 }, screen, false));
    CHECK(!coversScreen({ 0, 5, 1512, 977 }, screen, false));
    CHECK(!coversScreen({ 0, 0, 1517, 982 }, screen, false));
    CHECK(!coversScreen({ 0, 0, 1512, 987 }, screen, false));
    CHECK(!coversScreen({ 0, 0, 1512, 977 }, screen, false));

    // The tolerance can be changed
    CHECK(coversScreen({ 5, 0, 1507, 982 }, screen, false, 5));
    CHECK(!coversScreen({ 1, 0, 1511, 982 }, screen, false, 0));

    // A smaller window, a window of the right size somewhere else, and a window with a title bar
    CHECK(!coversScreen({ 100, 100, 800, 600 }, screen, false));
    CHECK(!coversScreen({ 200, 100, 1512, 982 }, screen, false));
    CHECK(!coversScreen(screen, screen, true));
    CHECK(!coversScreen({ 0, 0, 1512, 982 }, screen, true, 100));

    // Screens that don't start at the origin, like a display beside the main one
    const Rect second = { 1512, -200, 2560, 1440 };
    CHECK(coversScreen(second, second, false));
    CHECK(!coversScreen({ 0, 0, 2560, 1440 }, second, false));

    if (s_Failures == 0) {
        std::printf("All fork policy tests passed\n");
    }
    return s_Failures == 0 ? 0 : 1;
}
