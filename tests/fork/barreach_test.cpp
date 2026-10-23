// Unit tests for app/fork/barreach.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/barreach_test.cpp
#include "fork/barreach.h"

#include <cstdio>

using namespace BarReach;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

// Moves every 10 ms from ms for duration, each dy pixels and dyPoints up; the time of the first move
// that asks, or 0
static std::uint32_t push(Tracker& tracker, std::uint32_t& ms, std::uint32_t duration, int dy = -4, double dyPoints = -2,
                          double dxPoints = 0, bool button = false)
{
    std::uint32_t asked = 0;
    for (std::uint32_t end = ms + duration; ms < end; ms += 10) {
        if (tracker.moved(0, dy, dxPoints, dyPoints, button, ms) && asked == 0) {
            asked = ms;
        }
    }
    return asked;
}

static Cursor at(int x, int y, bool shown = true)
{
    return { x, y, 2560, 1440, shown };
}

static void testFirstPushAsks()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    // Not known yet: a push long and far enough asks, once until it's answered
    std::uint32_t asked = push(tracker, ms, 400);
    CHECK(asked >= 1000 + k_PushMs);
    CHECK(tracker.asking());
    CHECK(push(tracker, ms, 300) == 0);
}

static void testAtTopHandsOver()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    push(tracker, ms, 300);
    // At the top, still pushed: the Mac's pointer goes in above it
    std::optional<double> x = tracker.answered(at(1279, 0), ms);
    CHECK(x && *x > 0.49 && *x < 0.51);
    CHECK(tracker.known() && tracker.y() == 0);
}

// Moves as push() does until one asks; its time, or 0
static std::uint32_t pushUntilAsked(Tracker& tracker, std::uint32_t& ms, std::uint32_t duration, int dy = -4, double dyPoints = -2)
{
    for (std::uint32_t end = ms + duration; ms < end; ms += 10) {
        if (tracker.moved(0, dy, 0, dyPoints, false, ms)) {
            return ms;
        }
    }
    return 0;
}

static void testLowerSyncs()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    CHECK(pushUntilAsked(tracker, ms, 400) != 0);
    // 300 px down: no handing over, and the pointer is followed from there, with the moves since
    tracker.moved(0, -8, 0, -4, false, ms + 5);
    CHECK(!tracker.answered(at(100, 300), ms + 10));
    CHECK(tracker.known() && tracker.x() == 100 && tracker.y() == 292);

    // Pushed up to the top: the push starts there, and asks once it's long enough. 292 px at 4 a
    // move reach the top with the 73rd move.
    ms += 300;
    std::uint32_t top = ms + 72 * 10;
    std::uint32_t asked = pushUntilAsked(tracker, ms, 1500);
    CHECK(asked >= top + k_PushMs && asked <= top + k_PushMs + 10);
    CHECK(tracker.answered(at(100, 0), asked + 5));
}

static void testThrowDoesntReach()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    push(tracker, ms, 300);
    tracker.answered(at(500, 40), ms);
    // Thrown up, past the top for a moment, then still: no question
    CHECK(push(tracker, ms, 150, -8, -6) == 0);
    ms += 200;
    // The next push starts over: a short one doesn't ask either
    CHECK(push(tracker, ms, 200) == 0);
}

static void testSlidingAlongTop()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    push(tracker, ms, 300);
    tracker.answered(at(500, 0), ms);
    ms += 300;
    // Across tabs: a little up, mostly sideways
    CHECK(push(tracker, ms, 600, 0, -1, 5) == 0);
    // Dragging, as a window to the top: no push either
    CHECK(push(tracker, ms, 600, -4, -2, 0, true) == 0);
}

static void testShownAndStillPushed()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    push(tracker, ms, 300);
    // A game hides the pointer
    CHECK(!tracker.answered(at(500, 0, false), ms));

    // The answer comes after the push stopped
    ms += 300;
    push(tracker, ms, 300);
    CHECK(!tracker.answered(at(500, 0), ms + k_PauseMs + 20));
}

static void testAskGap()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    std::uint32_t first = push(tracker, ms, 260);
    CHECK(first != 0);
    tracker.unanswered();
    // Asked again no sooner than the gap allows
    std::uint32_t second = push(tracker, ms, 300);
    CHECK(second >= first + k_AskGapMs);
}

static void testOtherDisplays()
{
    Tracker tracker;
    std::uint32_t ms = 1000;
    push(tracker, ms, 300);
    // Beside the display: nothing known
    CHECK(!tracker.answered(at(-200, 0), ms));
    CHECK(!tracker.known());

    // Above it, on a display over this one: past the top
    push(tracker, ms, 300);
    CHECK(tracker.answered(at(640, -30), ms));
}

static void testPlaced()
{
    Tracker tracker;
    // Before any answer the display's size isn't known
    tracker.placed(0.5, 0.1);
    CHECK(!tracker.known());

    std::uint32_t ms = 1000;
    push(tracker, ms, 300);
    tracker.answered(at(500, 500), ms);
    tracker.placed(0.25, 0);
    CHECK(tracker.known() && tracker.x() == 640 && tracker.y() == 0);
    tracker.forget();
    CHECK(!tracker.known());
}

int main()
{
    testFirstPushAsks();
    testAtTopHandsOver();
    testLowerSyncs();
    testThrowDoesntReach();
    testSlidingAlongTop();
    testShownAndStillPushed();
    testAskGap();
    testOtherDisplays();
    testPlaced();

    if (s_Failures == 0) {
        std::printf("barreach: all tests passed\n");
        return 0;
    }
    std::printf("barreach: %d failure(s)\n", s_Failures);
    return 1;
}
