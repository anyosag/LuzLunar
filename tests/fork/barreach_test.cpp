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

static const std::uint32_t k_Release = k_Pulses * k_PulseMs;

// One move up: 4 px, 2 points
static Step up(Tracker& tracker, std::uint32_t ms, int dy = -4, double dyPoints = -2, double dxPoints = 0, bool button = false)
{
    return tracker.moved(0, dy, dxPoints, dyPoints, button, ms);
}

// Moves up every 10 ms from ms for duration, until a step isn't None; that step
static Step push(Tracker& tracker, std::uint32_t& ms, std::uint32_t duration, int dy = -4, double dyPoints = -2)
{
    for (std::uint32_t end = ms + duration; ms < end; ms += 10) {
        Step step = up(tracker, ms, dy, dyPoints);
        if (step.action != Action::None) {
            ms += 10;
            return step;
        }
    }
    return {};
}

static Cursor at(int x, int y, bool pulsing = true, bool shown = true)
{
    Cursor cursor;
    cursor.x = x;
    cursor.y = y;
    cursor.width = 2560;
    cursor.height = 1440;
    cursor.shown = shown;
    cursor.pulsing = pulsing;
    return cursor;
}

static void testAsksAsThePushBegins()
{
    Tracker tracker;
    // Not known yet: the first move up asks, at once
    CHECK(up(tracker, 1000).action == Action::Ask);
    CHECK(tracker.asking());
    std::uint32_t ms = 1010;
    CHECK(push(tracker, ms, 300).action == Action::None);
}

static void testGoesAsTheSecondPulseEnds()
{
    Tracker tracker;
    CHECK(up(tracker, 1000).action == Action::Ask);
    // At the top, and the PC pulses it
    CHECK(tracker.answered(at(1279, 0), 1040).action == Action::None);
    CHECK(tracker.busy());
    // Pushed on: nothing until the pulses end
    std::uint32_t ms = 1050;
    CHECK(push(tracker, ms, k_Release - 20).action == Action::None);
    Step step = push(tracker, ms, 60);
    CHECK(step.action == Action::HandOver);
    CHECK(step.fraction > 0.49 && step.fraction < 0.51);
    CHECK(!tracker.busy());
}

static void testPulsesHereWhenThePcCant()
{
    Tracker tracker;
    up(tracker, 1000);
    CHECK(tracker.answered(at(500, 0, false), 1040).action == Action::PulseHere);
    std::uint32_t ms = 1050;
    CHECK(push(tracker, ms, k_Release + 20).action == Action::HandOver);
}

static void testLowerSyncs()
{
    Tracker tracker;
    up(tracker, 1000);
    // 300 px down: followed from there, with the moves since
    up(tracker, 1005, -8, -4);
    CHECK(tracker.answered(at(100, 300, false), 1010).action == Action::None);
    CHECK(tracker.known() && tracker.x() == 100 && tracker.y() == 292 && !tracker.busy());

    // Pushed up to the top: it asks as it gets there. 292 px at 4 a move reach it with the 73rd.
    std::uint32_t ms = 1300;
    std::uint32_t top = ms + 72 * 10;
    Step step;
    std::uint32_t askedAt = 0;
    for (std::uint32_t end = ms + 1000; ms < end; ms += 10) {
        step = up(tracker, ms);
        if (step.action == Action::Ask) {
            askedAt = ms;
            break;
        }
    }
    CHECK(askedAt == top);
}

static void testStopsShort()
{
    // Stopped while the PC pulses: a pause, seen by the tick
    Tracker tracker;
    up(tracker, 1000);
    tracker.answered(at(500, 0), 1040);
    std::uint32_t ms = 1050;
    push(tracker, ms, 100);
    CHECK(tracker.tick(ms + 100).action == Action::None);
    Step step = tracker.tick(ms + k_PauseMs + 20);
    CHECK(step.action == Action::Cancel && step.pcPulses);
    CHECK(!tracker.busy());

    // Moving down instead
    Tracker down;
    up(down, 1000);
    down.answered(at(500, 0), 1040);
    CHECK(down.moved(0, 10, 0, 5, false, 1100).action == Action::Cancel);

    // The pulses over the picture settle too
    Tracker here;
    up(here, 1000);
    here.answered(at(500, 0, false), 1040);
    Step settle = here.moved(0, 10, 0, 5, false, 1100);
    CHECK(settle.action == Action::Cancel && !settle.pcPulses);
}

static void testSwipes()
{
    // Quick swipes up, the finger lifting between them: one push
    Tracker tracker;
    up(tracker, 1000);
    CHECK(tracker.answered(at(800, 0), 1020).action == Action::None);
    std::uint32_t ms = 1030;
    CHECK(push(tracker, ms, 100).action == Action::None);
    ms += 200;
    CHECK(tracker.tick(ms).action == Action::None);
    CHECK(tracker.busy());
    CHECK(push(tracker, ms, 200).action == Action::HandOver);
}

static void testOneSwipe()
{
    // One swipe up that ends just before the pulses do: it goes as they end
    Tracker tracker;
    up(tracker, 1000);
    tracker.answered(at(800, 0), 1020);
    std::uint32_t ms = 1030;
    CHECK(push(tracker, ms, 230).action == Action::None);
    CHECK(tracker.tick(1020 + k_Release - 10).action == Action::None);
    Step step = tracker.tick(1020 + k_Release);
    CHECK(step.action == Action::HandOver);

    // A throw up at a tab that stops there: the pulses end without it going, then settle
    Tracker thrown;
    up(thrown, 1000);
    thrown.answered(at(800, 0), 1020);
    ms = 1030;
    push(thrown, ms, 60);
    CHECK(thrown.tick(1020 + k_Release).action == Action::None);
    CHECK(thrown.tick(ms + k_PauseMs).action == Action::Cancel);
}

static void testEndsBeforeTheAnswer()
{
    Tracker tracker;
    up(tracker, 1000);
    // The PC pulses, but the push had stopped by then
    Step step = tracker.answered(at(500, 0), 1000 + k_PauseMs + 50);
    CHECK(step.action == Action::Cancel && step.pcPulses);
}

static void testNotEnoughPush()
{
    Tracker tracker;
    up(tracker, 1000, -4, -1);
    tracker.answered(at(500, 0), 1010);
    // A gentle push: half a point a move, 18 points by the time the pulses end
    std::uint32_t ms = 1020;
    CHECK(push(tracker, ms, k_Release, -1, -0.5).action == Action::None);
    // On until 24
    CHECK(push(tracker, ms, 200, -1, -0.5).action == Action::HandOver);
}

static void testSlidingAndDragging()
{
    Tracker tracker;
    up(tracker, 1000);
    tracker.answered(at(500, 0, false), 1010);
    tracker.moved(0, 10, 0, 5, false, 1020);
    // Across tabs: a little up, mostly sideways
    std::uint32_t ms = 1400;
    Step step;
    for (std::uint32_t end = ms + 600; ms < end; ms += 10) {
        step = tracker.moved(0, -4, 5, -1, false, ms);
        CHECK(step.action == Action::None);
    }
    // Dragging, as a window to the top
    for (std::uint32_t end = ms + 600; ms < end; ms += 10) {
        CHECK(up(tracker, ms, -4, -2, 0, true).action == Action::None);
    }
}

static void testHiddenOrBeside()
{
    Tracker hidden;
    up(hidden, 1000);
    CHECK(hidden.answered(at(500, 0, false, false), 1010).action == Action::None);
    CHECK(!hidden.busy());

    Tracker beside;
    up(beside, 1000);
    CHECK(beside.answered(at(-200, 0, false), 1010).action == Action::None);
    CHECK(!beside.known());

    // Above, on a display over this one: at the top
    Tracker above;
    up(above, 1000);
    above.answered(at(640, -30), 1010);
    std::uint32_t ms = 1020;
    CHECK(push(above, ms, k_Release + 20).action == Action::HandOver);
}

static void testAskGap()
{
    Tracker tracker;
    CHECK(up(tracker, 1000).action == Action::Ask);
    tracker.unanswered();
    std::uint32_t ms = 1010;
    std::uint32_t askedAt = 0;
    for (std::uint32_t end = ms + 400; ms < end; ms += 10) {
        if (up(tracker, ms).action == Action::Ask) {
            askedAt = ms;
            break;
        }
    }
    CHECK(askedAt == 1000 + k_AskGapMs);
}

int main()
{
    testAsksAsThePushBegins();
    testGoesAsTheSecondPulseEnds();
    testPulsesHereWhenThePcCant();
    testLowerSyncs();
    testStopsShort();
    testSwipes();
    testOneSwipe();
    testEndsBeforeTheAnswer();
    testNotEnoughPush();
    testSlidingAndDragging();
    testHiddenOrBeside();
    testAskGap();

    if (s_Failures == 0) {
        std::printf("barreach: all tests passed\n");
        return 0;
    }
    std::printf("barreach: %d failure(s)\n", s_Failures);
    return 1;
}
