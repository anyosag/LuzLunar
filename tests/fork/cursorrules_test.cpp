// Unit tests for app/fork/cursorrules.*, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/cursorrules_test.cpp app/fork/cursorrules.cpp
#include "fork/cursorrules.h"

#include <cmath>
#include <cstdio>

using namespace CursorRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

// What Apollo says: the pointer at x,y of a 1920x1080 display, with the sums it had, Windows keeping
// it on that display
static luzcursor::state_t pc(int x, int y, std::int64_t sumX, std::int64_t sumY)
{
    luzcursor::state_t state;
    state.flags = luzcursor::flag_visible | luzcursor::flag_on_display;
    state.hash = 42;
    state.x = x;
    state.y = y;
    state.width = 1920;
    state.height = 1080;
    state.sum_dx = sumX;
    state.sum_dy = sumY;
    state.clip_left = 0;
    state.clip_top = 0;
    state.clip_right = 1920;
    state.clip_bottom = 1080;
    return state;
}

static bool near(double a, double b)
{
    return std::fabs(a - b) < 0.01;
}

static void testFirstState()
{
    Tracker tracker;
    CHECK(!tracker.known());
    // Moves before the PC said anything: the first state had none of them, so they go on from it
    tracker.moved(5, 0, 0);
    tracker.moved(5, 2, 8);
    CHECK(tracker.state(pc(100, 100, 0, 0), 20) == Correction::Snap);
    CHECK(tracker.known());
    CHECK(tracker.predictedX() == 110 && tracker.predictedY() == 102);
    CHECK(tracker.width() == 1920 && tracker.height() == 1080);
    // A display of nothing says nothing
    Tracker none;
    luzcursor::state_t empty = pc(1, 1, 0, 0);
    empty.width = 0;
    CHECK(none.state(empty, 0) == Correction::None && !none.known());
}

static void testRightAlong()
{
    Tracker tracker;
    tracker.state(pc(500, 500, 0, 0), 0);
    std::uint32_t ms = 0;
    for (int i = 0; i < 10; i++) {
        tracker.moved(3, -1, ms += 8);
    }
    CHECK(tracker.predictedX() == 530 && tracker.predictedY() == 490);
    // The PC had 6 of them when it said: it's where those put it, so nothing changes, and the 4 sent
    // since still count
    CHECK(tracker.state(pc(518, 494, 18, -6), ms) == Correction::None);
    CHECK(tracker.predictedX() == 530 && tracker.predictedY() == 490);
    CHECK(tracker.kept() == 4);
    // All of them
    CHECK(tracker.state(pc(530, 490, 30, -10), ms + 20) == Correction::None);
    CHECK(tracker.kept() == 0);
    CHECK(!tracker.easing(ms + 20));
}

static void testEase()
{
    Tracker tracker;
    tracker.state(pc(500, 500, 0, 0), 0);
    tracker.moved(10, 0, 10);
    // An app nudged it 12 px down: eases there over k_EaseMs, most of the way early
    CHECK(tracker.state(pc(510, 512, 10, 0), 100) == Correction::Ease);
    CHECK(tracker.predictedX() == 510 && tracker.predictedY() == 512);
    CHECK(tracker.easing(100) && near(tracker.y(100), 500));
    double half = tracker.y(100 + k_EaseMs / 2);
    CHECK(half > 500 + 12 * 0.8 && half < 512);
    CHECK(near(tracker.y(100 + k_EaseMs), 512) && !tracker.easing(100 + k_EaseMs));
    // A move during the ease goes on from the new place, the ease still running
    tracker.moved(0, 1, 110);
    CHECK(tracker.predictedY() == 513 && tracker.easing(110));

    // A pixel off isn't eased
    Tracker pixel;
    pixel.state(pc(100, 100, 0, 0), 0);
    CHECK(pixel.state(pc(101, 100, 0, 0), 10) == Correction::None);
    CHECK(pixel.predictedX() == 101 && !pixel.easing(10));
}

static void testSnap()
{
    Tracker tracker;
    tracker.state(pc(500, 500, 0, 0), 0);
    tracker.moved(4, 4, 10);
    // An app moved it across the display: the Mac's jumps too, with the move sent since kept
    tracker.moved(1, 0, 20);
    CHECK(tracker.state(pc(1800, 100, 4, 4), 30) == Correction::Snap);
    CHECK(tracker.predictedX() == 1801 && tracker.predictedY() == 100);
    CHECK(!tracker.easing(30) && near(tracker.x(30), 1801));
    CHECK(k_EasePx == 24 && k_EaseMs == 60);
}

static void testClamped()
{
    // Pushed against the right edge, then back: Windows stopped it at the edge, and so does the
    // prediction, in the moves it replays too
    Tracker tracker;
    tracker.state(pc(1900, 500, 0, 0), 0);
    tracker.moved(50, 0, 10);
    CHECK(tracker.predictedX() == 1919);
    tracker.moved(-30, 0, 20);
    CHECK(tracker.predictedX() == 1889);
    // The PC had the first: at the edge; the second goes on from there
    CHECK(tracker.state(pc(1919, 500, 50, 0), 30) == Correction::None);
    CHECK(tracker.predictedX() == 1889);

    // An app's clip rectangle holds it in
    Tracker clipped;
    luzcursor::state_t state = pc(200, 200, 0, 0);
    state.flags |= luzcursor::flag_clipped;
    state.clip_left = 100;
    state.clip_top = 100;
    state.clip_right = 300;
    state.clip_bottom = 300;
    clipped.state(state, 0);
    clipped.moved(500, -500, 10);
    CHECK(clipped.predictedX() == 299 && clipped.predictedY() == 100);

    // Other displays beside this one: Windows keeps it on all of them, so it can go off this one
    Tracker wide;
    luzcursor::state_t two = pc(1900, 500, 0, 0);
    two.clip_right = 3840;
    wide.state(two, 0);
    wide.moved(100, 0, 10);
    CHECK(wide.predictedX() == 2000);
}

static void testUncounted()
{
    // The PC has moves this Mac never counted: nothing matches while moves go, and once they stop
    // its place and sums become this Mac's
    Tracker tracker;
    tracker.state(pc(500, 500, 0, 0), 0);
    tracker.moved(10, 0, 10);
    tracker.moved(10, 0, 20);
    CHECK(tracker.state(pc(700, 500, 120, 0), 30) == Correction::None);
    CHECK(tracker.predictedX() == 520);
    CHECK(tracker.state(pc(700, 500, 120, 0), 20 + k_IdleMs) == Correction::Snap);
    CHECK(tracker.predictedX() == 700 && tracker.sentX() == 120 && tracker.kept() == 0);
    // And they match from there
    tracker.moved(5, 0, 400);
    CHECK(tracker.state(pc(705, 500, 125, 0), 410) == Correction::None);
}

static void testBackAndForth()
{
    // The sums come back to a value they had: the first after the last match is the one, and where it
    // puts the pointer is the same either way while nothing was clamped
    Tracker tracker;
    tracker.state(pc(500, 500, 0, 0), 0);
    tracker.moved(10, 0, 10);
    tracker.moved(-10, 0, 20);
    tracker.moved(10, 0, 30);
    tracker.moved(-10, 0, 40);
    CHECK(tracker.state(pc(500, 500, 0, 0), 50) == Correction::None);
    CHECK(tracker.predictedX() == 500);
    CHECK(tracker.state(pc(510, 500, 10, 0), 60) == Correction::None);
    CHECK(tracker.state(pc(500, 500, 0, 0), 70) == Correction::None);
    CHECK(tracker.predictedX() == 500);
}

static void testHistoryCap()
{
    Tracker tracker;
    tracker.state(pc(0, 0, 0, 0), 0);
    for (std::size_t i = 0; i < k_History + 10; i++) {
        tracker.moved(1, 0, static_cast<std::uint32_t>(i));
    }
    CHECK(tracker.kept() == k_History);
    // The oldest sums are gone; a state from then can't be placed while moves go
    CHECK(tracker.state(pc(3, 0, 3, 0), static_cast<std::uint32_t>(k_History + 10)) == Correction::None);
    // One from the moves kept can
    CHECK(tracker.state(pc(20, 0, 20, 0), static_cast<std::uint32_t>(k_History + 11)) == Correction::None);
    CHECK(tracker.predictedX() == static_cast<int>(k_History + 10));
}

static void testModes()
{
    CHECK(modeFor(true, false) == Mode::Cursor);
    CHECK(modeFor(false, true) == Mode::Sprite);
    CHECK(modeFor(true, true) == Mode::Sprite);
    CHECK(modeFor(false, false) == Mode::None);
    CHECK(macDraws(Mode::Cursor) && macDraws(Mode::Sprite) && !macDraws(Mode::None));

    CHECK(launchValue(true, true, false, Mode::Sprite) == "1");
    CHECK(launchValue(true, true, false, Mode::Cursor) == "1");
    CHECK(launchValue(true, true, false, Mode::None) == "host");
    CHECK(launchValue(false, true, false, Mode::Sprite).empty());
    CHECK(launchValue(true, false, false, Mode::Sprite).empty());  // an older Apollo
    CHECK(launchValue(true, true, true, Mode::Sprite).empty());  // a multi-display stream's other window
}

static void testShows()
{
    Situation sprite;
    sprite.mode = Mode::Sprite;
    sprite.stateKnown = true;
    sprite.state = pc(100, 100, 0, 0);
    sprite.shapeUsable = true;
    sprite.trackerKnown = true;
    sprite.x = 100;
    sprite.y = 100;
    CHECK(spriteShows(sprite) && !cursorShows(sprite));

    Situation hidden = sprite;
    hidden.state.flags = luzcursor::flag_on_display;  // a game hid it
    CHECK(!spriteShows(hidden));
    Situation host = sprite;
    host.state.flags |= luzcursor::flag_host_draws;  // UAC, the lock screen
    CHECK(!spriteShows(host));
    Situation off = sprite;
    off.x = 1920;  // the moves took it past the display's edge
    CHECK(!spriteShows(off));
    Situation shot = sprite;
    shot.screenshotTools = true;
    CHECK(!spriteShows(shot));
    Situation broken = sprite;
    broken.shapeUsable = false;
    CHECK(!spriteShows(broken));
    Situation unplaced = sprite;
    unplaced.trackerKnown = false;
    CHECK(!spriteShows(unplaced));
    Situation never = sprite;
    never.stateKnown = false;
    CHECK(!spriteShows(never));

    Situation cursor = sprite;
    cursor.mode = Mode::Cursor;
    cursor.trackerKnown = false;
    cursor.screenshotTools = true;  // macOS's own cursor is left out of screenshots anyway
    CHECK(cursorShows(cursor) && !spriteShows(cursor));
    Situation hostCursor = cursor;
    hostCursor.state.flags |= luzcursor::flag_host_draws;
    CHECK(!cursorShows(hostCursor));
    Situation none = sprite;
    none.mode = Mode::None;
    CHECK(!cursorShows(none) && !spriteShows(none));
}

static void testSizing()
{
    // A 2560-pixel display in a 1280-point picture: half a point a pixel, so a 32-pixel pointer is
    // 16 points, as big as the picture shows it
    CHECK(near(pointsPerPixel(1280, 2560), 0.5));
    CHECK(near(pointsPerPixel(1512, 1512), 1));
    CHECK(pointsPerPixel(1280, 0) == 0 && pointsPerPixel(0, 1920) == 0);

    // The picture letterboxed 20 points down a window
    Point point = inWindow(1280, 720, 0, 20, 1280, 720, 2560, 1440);
    CHECK(near(point.x, 640) && near(point.y, 380));
    Point corner = inWindow(0, 0, 10, 20, 1280, 720, 2560, 1440);
    CHECK(near(corner.x, 10) && near(corner.y, 20));
    Point none = inWindow(5, 5, 10, 20, 1280, 720, 0, 0);
    CHECK(near(none.x, 0) && near(none.y, 0));

    // A 16:10 display in a 16:9 stream: bars left and right of it in the picture
    Rect picture { 0, 0, 1600, 900 };
    Rect display = displayInPicture(picture, 1920, 1200);
    CHECK(near(display.w, 1440) && near(display.h, 900) && near(display.x, 80) && near(display.y, 0));
    // The same shape: all of it
    Rect same = displayInPicture(picture, 3200, 1800);
    CHECK(near(same.x, 0) && near(same.y, 0) && near(same.w, 1600) && near(same.h, 900));
    // Taller than wide: bars above and below
    Rect tall = displayInPicture(Rect { 10, 20, 1600, 900 }, 1600, 1600);
    CHECK(near(tall.w, 900) && near(tall.h, 900) && near(tall.x, 10 + 350) && near(tall.y, 20));
    Rect unknown = displayInPicture(picture, 0, 0);
    CHECK(near(unknown.w, 1600));
}

int main()
{
    testFirstState();
    testRightAlong();
    testEase();
    testSnap();
    testClamped();
    testUncounted();
    testBackAndForth();
    testHistoryCap();
    testModes();
    testShows();
    testSizing();

    if (s_Failures == 0) {
        std::printf("cursorrules: all tests passed\n");
        return 0;
    }
    std::printf("cursorrules: %d failure(s)\n", s_Failures);
    return 1;
}
