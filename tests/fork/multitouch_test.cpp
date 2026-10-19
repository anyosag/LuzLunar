// Tests for app/fork/forkmultitouch.*: pairing AppKit's touches with MultitouchSupport's contacts,
// which carry the sizes and hand parts palm rejection uses.
//   clang++ -std=c++17 -Iapp/fork tests/fork/multitouch_test.cpp app/fork/forkmultitouch.cpp

#include "forkmultitouch.h"

#include <cstdio>

using namespace ForkMultitouch;
using ForkTrackpad::Touch;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static Touch touch(double x, double y)
{
    Touch t;
    t.x = x;
    t.y = y;
    return t;
}

static Contact contact(float x, float y, int fingerId, float minor, int state = 4)
{
    Contact c;
    c.x = x;
    c.y = y;
    c.fingerId = fingerId;
    c.minorAxisMm = minor;
    c.majorAxisMm = minor * 1.3f;
    c.state = state;
    return c;
}

static void testNearest()
{
    // Two fingers and a palm; the touches arrive in another order than the contacts
    std::vector<Touch> touches = {touch(0.70, 0.40), touch(0.30, 0.42)};
    std::vector<Contact> contacts = {contact(0.31, 0.41, 2, 8.0f), contact(0.69, 0.40, 3, 8.5f),
                                     contact(0.90, 0.05, 7, 14.0f)};
    annotate(touches, contacts);
    CHECK(touches[0].hasContact && touches[0].fingerId == 3);
    CHECK(touches[1].hasContact && touches[1].fingerId == 2 && touches[1].minorAxisMm == 8.0f);
}

static void testUpsideDown()
{
    // Should the framework's y count down the pad, the fingers are still found
    std::vector<Touch> touches = {touch(0.30, 0.80), touch(0.60, 0.10)};
    annotate(touches, {contact(0.30f, 0.20f, 2, 8.0f), contact(0.61f, 0.90f, 7, 15.0f)});
    CHECK(touches[0].hasContact && touches[0].fingerId == 2);
    CHECK(touches[1].hasContact && touches[1].fingerId == 7);
}

static void testTooFar()
{
    // A contact further than k_MatchDistance is someone else
    std::vector<Touch> touches = {touch(0.5, 0.5)};
    annotate(touches, {contact(0.5f + k_MatchDistance + 0.01f, 0.5f, 2, 8.0f)});
    CHECK(!touches[0].hasContact);
}

static void testEachOnce()
{
    // Two touches near one contact: the closer one gets it, the other nothing
    std::vector<Touch> touches = {touch(0.50, 0.50), touch(0.53, 0.50)};
    annotate(touches, {contact(0.52f, 0.50f, 2, 8.0f)});
    CHECK(!touches[0].hasContact);
    CHECK(touches[1].hasContact);
}

static void testHovering()
{
    // Contacts not on the pad (hovering, gone) don't count
    std::vector<Touch> touches = {touch(0.5, 0.5)};
    annotate(touches, {contact(0.5f, 0.5f, 2, 8.0f, 2), contact(0.5f, 0.5f, 2, 8.0f, 7)});
    CHECK(!touches[0].hasContact);
    CHECK(touchingState(3) && touchingState(4) && touchingState(5) && touchingState(6));
    CHECK(!touchingState(0) && !touchingState(1) && !touchingState(2) && !touchingState(7));
}

static void testPlausible()
{
    CHECK(plausible(contact(0.5f, 0.5f, 2, 8.0f)));
    CHECK(plausible(contact(0.0f, 1.0f, 7, 25.0f)));
    CHECK(!plausible(contact(3.0f, 0.5f, 2, 8.0f)));  // off the pad
    CHECK(!plausible(contact(0.5f, 0.5f, 12, 8.0f)));  // no such hand part
    CHECK(!plausible(contact(0.5f, 0.5f, 2, -1.0f)));
    CHECK(!plausible(contact(0.5f, 0.5f, 2, 500.0f)));
    Contact nan = contact(0.5f, 0.5f, 2, 8.0f);
    nan.majorAxisMm = 0.0f / 0.0f;
    CHECK(!plausible(nan));
}

static void testNotRunning()
{
    // Without start(), nothing is added
    std::vector<Touch> touches = {touch(0.5, 0.5)};
    annotateNow(touches);
    CHECK(!touches[0].hasContact);
    CHECK(!why().empty());
}

int main()
{
    testNearest();
    testUpsideDown();
    testTooFar();
    testEachOnce();
    testHovering();
    testPlausible();
    testNotRunning();

    if (s_Failures == 0) {
        std::printf("multitouch: all tests passed\n");
        return 0;
    }
    std::printf("multitouch: %d failure(s)\n", s_Failures);
    return 1;
}
