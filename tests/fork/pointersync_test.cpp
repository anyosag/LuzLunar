// Unit tests for app/fork/forkpointersync.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/pointersync_test.cpp
#include "fork/forkpointersync.h"

#include <cstdio>

using namespace ForkPointerSync;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool at(const Point& p, int x, int y)
{
    return p.x == x && p.y == y;
}

int main()
{
    // A 1512x982-point window on the built-in display, the 3024x1890 picture below the notch's strip
    Rect picture { 0, 37, 1512, 945 };

    CHECK(at(place(700, 437, picture), 700, 400));      // over the picture: the same spot in it
    CHECK(at(place(0, 37, picture), 0, 0));             // its top-left corner
    CHECK(at(place(1511, 981, picture), 1511, 944));    // its last point
    CHECK(at(place(700, 20, picture), 756, 472));       // in the notch's strip: the centre
    CHECK(at(place(-900, 300, picture), 756, 472));     // on another display (the iMac's, left of it)
    CHECK(at(place(1512, 500, picture), 756, 472));     // just past its right edge
    CHECK(at(place(700, 982, picture), 756, 472));      // just below it

    // A letterboxed picture: bars on both sides
    Rect boxed { 100, 0, 800, 600 };
    CHECK(at(place(50, 300, boxed), 400, 300));
    CHECK(at(place(500, 300, boxed), 400, 300));

    if (s_Failures > 0) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("All pointer sync tests passed\n");
    return 0;
}
