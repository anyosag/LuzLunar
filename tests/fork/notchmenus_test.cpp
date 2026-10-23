// Tests for app/fork/notchmenus.h: the notch bar menus' keyboard movement, the layout of the items
// right of the notch, and the push that lets the pointer up into the bar. A standalone program for
// the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/notchmenus_test.cpp

#include "fork/notchmenus.h"

#include <cstdio>
#include <vector>

using namespace NotchMenus;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static void testNeighbour()
{
    CHECK(neighbour(Menu::Session, 1) == Menu::ControlCenter);
    CHECK(neighbour(Menu::ControlCenter, 1) == Menu::Session);
    CHECK(neighbour(Menu::Session, -1) == Menu::ControlCenter);
    CHECK(neighbour(Menu::ControlCenter, -3) == Menu::Session);
    CHECK(neighbour(Menu::None, 1) == Menu::None);
}

static void testNextSelectable()
{
    // A header, two items, a separator, an item, a disabled item
    std::vector<bool> rows = { false, true, true, false, true, false };
    auto selectable = [&](int i) { return rows[static_cast<size_t>(i)]; };
    int count = static_cast<int>(rows.size());

    CHECK(nextSelectable(count, -1, 1, selectable) == 1);    // Down from nothing: the first item
    CHECK(nextSelectable(count, -1, -1, selectable) == 4);   // Up from nothing: the last item
    CHECK(nextSelectable(count, 1, 1, selectable) == 2);
    CHECK(nextSelectable(count, 2, 1, selectable) == 4);     // over the separator
    CHECK(nextSelectable(count, 4, 1, selectable) == 1);     // wraps past the disabled one and the header
    CHECK(nextSelectable(count, 1, -1, selectable) == 4);    // wraps up
    CHECK(nextSelectable(count, 99, 1, selectable) == 1);    // out of range counts as nothing

    std::vector<bool> none = { false, false };
    CHECK(nextSelectable(2, -1, 1, [&](int i) { return none[static_cast<size_t>(i)]; }) == -1);
    CHECK(nextSelectable(0, -1, 1, selectable) == -1);
    CHECK(nextSelectable(count, 1, 0, selectable) == -1);
}

static void testLayoutRight()
{
    // Stats (shrinkable), then Control Center, in a 400-point area
    auto placed = layoutRight(400, 10, 4, { 200, 34 }, 0);
    CHECK(placed[1].width == 34 && placed[1].x == 400 - 10 - 34);
    CHECK(placed[0].width == 200 && placed[0].x == 400 - 10 - 34 - 4 - 200);

    // Too narrow: the stats give way first
    placed = layoutRight(200, 10, 4, { 200, 34 }, 0);
    // 180 points of room for 238: the stats lose 58
    CHECK(placed[1].width == 34 && placed[1].x == 156);
    CHECK(placed[0].width == 142 && placed[0].x == 10);

    // Far too narrow: the stats go, then the items nearest the notch
    placed = layoutRight(60, 10, 4, { 200, 34 }, 0);
    CHECK(placed[0].width == 0);
    CHECK(placed[1].width == 34 && placed[1].x == 60 - 10 - 34);
    placed = layoutRight(30, 10, 4, { 200, 34 }, 0);
    CHECK(placed[0].width == 0 && placed[1].width == 0);

    // Shrunk below the minimum, the stats go rather than show a sliver
    placed = layoutRight(80, 10, 4, { 200, 34 }, 0, 24);
    CHECK(placed[0].width == 0 && placed[1].width == 34);
    placed = layoutRight(100, 10, 4, { 200, 34 }, 0, 24);
    CHECK(placed[0].width == 42 && placed[0].x == 10);

    // Nothing shrinkable: items are cut from the notch side
    placed = layoutRight(100, 10, 4, { 40, 40 }, -1);
    CHECK(placed[0].width == 0 && placed[1].width == 40);
}

static void testRevealGesture()
{
    RevealGesture gesture(24, 0.4);
    // Pushing up at the top edge, 8 points at a time
    CHECK(!gesture.push(8, true, 0.00));
    CHECK(!gesture.push(8, true, 0.05));
    CHECK(gesture.push(8, true, 0.10));
    // It starts over once it fires
    CHECK(!gesture.push(8, true, 0.15));

    // Too slow: the window starts again
    gesture.reset();
    CHECK(!gesture.push(10, true, 0.0));
    CHECK(!gesture.push(10, true, 0.5));
    CHECK(!gesture.push(10, true, 0.6));
    CHECK(gesture.push(10, true, 0.7));

    // Leaving the edge or moving down starts over
    gesture.reset();
    CHECK(!gesture.push(20, true, 0.0));
    CHECK(!gesture.push(-1, true, 0.05));
    CHECK(!gesture.push(20, true, 0.1));
    CHECK(!gesture.push(20, false, 0.15));
    CHECK(!gesture.push(20, true, 0.2));
    // A pause without movement keeps it
    CHECK(!gesture.push(0, true, 0.25));
    CHECK(gesture.push(5, true, 0.3));
}

int main()
{
    testNeighbour();
    testNextSelectable();
    testLayoutRight();
    testRevealGesture();

    if (s_Failures == 0) {
        std::printf("notchmenus: all tests passed\n");
        return 0;
    }
    std::printf("notchmenus: %d failure(s)\n", s_Failures);
    return 1;
}
