// Unit tests for app/fork/forkpolicy.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Iapp tests/fork/policy_test.cpp app/fork/forkpolicy.cpp
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
    // All 16 combinations of (upstream, notch, bar on, exact native). upstream always wins; otherwise a
    // Space is used only on a notched display with the bar on, at any size but the exact native one.
    for (int bits = 0; bits < 16; bits++) {
        bool upstream = bits & 8;
        bool notch = bits & 4;
        bool barOn = bits & 2;
        bool exactNative = bits & 1;
        bool expected = upstream || (notch && barOn && !exactNative);
        if (useSpacesFullscreen(upstream, notch, barOn, exactNative) != expected) {
            std::printf("FAIL useSpacesFullscreen(upstream %d, notch %d, bar %d, native %d) != %d\n",
                        upstream, notch, barOn, exactNative, expected);
            s_Failures++;
        }
    }

    // The case that matters: Fullscreen at 2560x1440 on a notched display with the bar on
    CHECK(useSpacesFullscreen(false, true, true, false));
    // Exact native keeps video under the notch, and the bar off or no notch keeps upstream's choice
    CHECK(!useSpacesFullscreen(false, true, true, true));
    CHECK(!useSpacesFullscreen(false, true, false, false));
    CHECK(!useSpacesFullscreen(false, false, true, false));

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
