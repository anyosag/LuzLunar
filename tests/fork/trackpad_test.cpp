// Tests for app/fork/forktrackpad.*: which Mac touches become which contacts in trackpad
// passthrough's frames, and which of the trackpad's own mouse events are held back.
//   clang++ -std=c++17 -Iapp/fork tests/fork/trackpad_test.cpp app/fork/forktrackpad.cpp

#include "forktrackpad.h"

#include <cstdio>
#include <initializer_list>

using namespace ForkTrackpad;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

// A MacBook Pro 14" trackpad, about 135 x 82 mm in points
static const double k_PadWidthPt = 382.7;
static const double k_PadHeightPt = 232.4;
static const std::uintptr_t k_Pad = 0x1000;

static Touch touch(std::uintptr_t id, TouchPhase phase, double x, double y, std::uintptr_t device = k_Pad)
{
    Touch t;
    t.identity = id;
    t.device = device;
    t.phase = phase;
    t.x = x;
    t.y = y;
    t.deviceWidth = k_PadWidthPt;
    t.deviceHeight = k_PadHeightPt;
    return t;
}

static const luztouchpad::contact* contactIn(const luztouchpad::frame& f, std::uint8_t slot)
{
    for (std::size_t i = 0; i < f.count; i++) {
        if (f.contacts[i].slot == slot) {
            return &f.contacts[i];
        }
    }
    return nullptr;
}

static Touch with(Touch t, TouchPhase phase)
{
    t.phase = phase;
    return t;
}

// A touch MultitouchSupport describes
static Touch sized(Touch t, int fingerId, float minorMm)
{
    t.hasContact = true;
    t.fingerId = fingerId;
    t.minorAxisMm = minorMm;
    return t;
}

// The event where touches begin, then two more with them held: by then they're decided
// (k_DecideFrames). The frame of the third.
static std::optional<luztouchpad::frame> settle(ContactTracker& t, const std::vector<Touch>& touches, std::uint32_t at)
{
    CHECK(!t.update(touches, at));
    std::vector<Touch> held;
    for (const Touch& tc : touches) {
        held.push_back(tc.phase == TouchPhase::Began ? with(tc, TouchPhase::Stationary) : tc);
    }
    CHECK(!t.update(held, at + 8));
    return t.update(held, at + 16);
}

static void testPadSize()
{
    std::uint16_t w = 0, h = 0;
    padSize(k_PadWidthPt, k_PadHeightPt, &w, &h);
    CHECK(w >= 13490 && w <= 13510);
    CHECK(h >= 8190 && h <= 8210);

    padSize(0, 0, &w, &h);
    CHECK(w == k_FallbackWidth && h == k_FallbackHeight);
    padSize(2000, 100, &w, &h);  // 700 mm wide
    CHECK(w == k_FallbackWidth && h == k_FallbackHeight);
}

static void testOneFinger()
{
    ContactTracker t;
    // It waits until it's decided: three frames
    CHECK(!t.update({touch(1, TouchPhase::Began, 0.25, 0.75)}, 100));
    CHECK(t.touching() && !t.fingersDown());
    CHECK(!t.update({touch(1, TouchPhase::Stationary, 0.25, 0.75)}, 108));
    auto down = t.update({touch(1, TouchPhase::Stationary, 0.25, 0.75)}, 116);
    CHECK(down.has_value());
    CHECK(down->count == 1);
    CHECK(down->contacts[0].slot == 0);
    CHECK(down->contacts[0].phase == luztouchpad::phase_down);
    // x from the left; y flipped to the pad's top
    CHECK(down->contacts[0].x == 16384);
    CHECK(down->contacts[0].y == 16384);
    CHECK(down->time_ms == 116);
    CHECK(down->width >= 13490 && down->width <= 13510);
    CHECK(t.fingersDown() && t.touching());

    auto move = t.update({touch(1, TouchPhase::Moved, 0.5, 0.5)}, 124);
    CHECK(move && move->contacts[0].phase == luztouchpad::phase_move);
    CHECK(move->contacts[0].x == 32768);

    // Unchanged positions send nothing
    CHECK(!t.update({touch(1, TouchPhase::Stationary, 0.5, 0.5)}, 132));

    auto up = t.update({touch(1, TouchPhase::Ended, 0.5, 0.5)}, 140);
    CHECK(up && up->count == 1 && up->contacts[0].phase == luztouchpad::phase_up);
    CHECK(!t.fingersDown() && !t.touching());

    // The slot is free for the next finger
    auto again = settle(t, {touch(2, TouchPhase::Began, 0.1, 0.1)}, 200);
    CHECK(again && again->contacts[0].slot == 0);
}

static void testDecidedFromWhereItIs()
{
    ContactTracker t;
    // A finger that moves while it's decided goes down where it is by then
    t.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    t.update({touch(1, TouchPhase::Moved, 0.52, 0.5)}, 8);
    auto down = t.update({touch(1, TouchPhase::Moved, 0.54, 0.5)}, 16);
    CHECK(down && down->contacts[0].phase == luztouchpad::phase_down);
    CHECK(down->contacts[0].x == 35389);

    // One held still brings no events: the keepalive's tick decides it after k_DecideMs
    ContactTracker still;
    still.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    CHECK(!still.tick(30));
    auto late = still.tick(k_DecideMs);
    CHECK(late && late->contacts[0].phase == luztouchpad::phase_down);
}

static void testQuickTap()
{
    ContactTracker t;
    // A tap shorter than the decision still reaches Windows: down now, up with the next frame
    t.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    auto down = t.update({touch(1, TouchPhase::Ended, 0.5, 0.5)}, 12);
    CHECK(down && down->count == 1 && down->contacts[0].phase == luztouchpad::phase_down);
    auto up = t.tick(20);
    CHECK(up && up->count == 1 && up->contacts[0].phase == luztouchpad::phase_up);
    CHECK(!t.fingersDown() && !t.touching());

    // A cancelled one doesn't
    t.update({touch(2, TouchPhase::Began, 0.5, 0.5)}, 100);
    CHECK(!t.update({touch(2, TouchPhase::Cancelled, 0.5, 0.5)}, 108));
    CHECK(!t.tick(200));
}

static void testTwoFingers()
{
    ContactTracker t;
    settle(t, {touch(1, TouchPhase::Began, 0.3, 0.5)}, 0);
    auto two = settle(t, {touch(1, TouchPhase::Stationary, 0.3, 0.5), touch(2, TouchPhase::Began, 0.6, 0.5)}, 24);
    CHECK(two && two->count == 2);
    auto first = contactIn(*two, 0);
    auto second = contactIn(*two, 1);
    CHECK(first && first->phase == luztouchpad::phase_move);
    CHECK(second && second->phase == luztouchpad::phase_down);

    // The first lifts; the frame still lists the second
    auto lift = t.update({touch(1, TouchPhase::Ended, 0.3, 0.5), touch(2, TouchPhase::Moved, 0.6, 0.4)}, 48);
    CHECK(lift && lift->count == 2);
    CHECK(contactIn(*lift, 0)->phase == luztouchpad::phase_up);
    CHECK(contactIn(*lift, 1)->phase == luztouchpad::phase_move);
    auto next = t.update({touch(2, TouchPhase::Moved, 0.6, 0.3)}, 56);
    CHECK(next && next->count == 1 && next->contacts[0].slot == 1);
}

static void testSixthFinger()
{
    ContactTracker t;
    std::vector<Touch> touches;
    for (std::uintptr_t id = 1; id <= 6; id++) {
        touches.push_back(touch(id, TouchPhase::Began, 0.1 * id, 0.5));
    }
    auto f = settle(t, touches, 0);
    CHECK(f && f->count == 5);
    // The sixth is ignored, but the pad counts as touched
    for (auto& tc : touches) {
        tc.phase = TouchPhase::Stationary;
    }
    touches[5] = touch(6, TouchPhase::Moved, 0.9, 0.9);
    CHECK(!t.update(touches, 24));
}

static void testCancelAndResting()
{
    ContactTracker t;
    settle(t, {touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    auto cancel = t.update({touch(1, TouchPhase::Cancelled, 0.5, 0.5)}, 24);
    CHECK(cancel && cancel->contacts[0].phase == luztouchpad::phase_cancel);
    CHECK(!t.fingersDown());

    // A finger macOS decides is a resting thumb is cancelled, not lifted (no tap)
    settle(t, {touch(2, TouchPhase::Began, 0.5, 0.1)}, 40);
    Touch resting = touch(2, TouchPhase::Stationary, 0.5, 0.1);
    resting.resting = true;
    auto rest = t.update({resting}, 64);
    CHECK(rest && rest->contacts[0].phase == luztouchpad::phase_cancel);

    // A resting touch waits as long as it rests, however long that is
    Touch thumb = touch(3, TouchPhase::Began, 0.9, 0.1);
    thumb.resting = true;
    CHECK(!t.update({thumb}, 100));
    CHECK(!t.update({with(thumb, TouchPhase::Stationary)}, 108));
    CHECK(!t.tick(500));
    CHECK(!t.fingersDown() && t.touching());

    // Once it stops resting and moves, it's decided like a new touch: a thumb starting to point
    Touch active = touch(3, TouchPhase::Moved, 0.8, 0.2);
    CHECK(!t.update({active}, 600));
    CHECK(!t.update({touch(3, TouchPhase::Moved, 0.78, 0.22)}, 608));
    auto points = t.update({touch(3, TouchPhase::Moved, 0.76, 0.24)}, 616);
    CHECK(points && points->contacts[0].phase == luztouchpad::phase_down);
}

static void testPalmByHand()
{
    ContactTracker t;
    // Apple's driver calls it a palm from its first frame: never sent
    Touch palm = sized(touch(1, TouchPhase::Began, 0.85, 0.1), 7, 6.0f);
    CHECK(!t.update({palm}, 0));
    CHECK(!t.update({with(palm, TouchPhase::Moved)}, 8));
    CHECK(!t.tick(200));
    CHECK(!t.fingersDown() && t.touching());
    CHECK(t.rejected().palms == 1);

    // A finger next to it works as usual
    auto f = settle(t, {with(palm, TouchPhase::Stationary), sized(touch(2, TouchPhase::Began, 0.4, 0.6), 2, 7.0f)}, 300);
    CHECK(f && f->count == 1 && f->contacts[0].phase == luztouchpad::phase_down);
    t.update({with(palm, TouchPhase::Ended), sized(touch(2, TouchPhase::Ended, 0.4, 0.6), 2, 7.0f)}, 400);
    CHECK(!t.touching());
}

static void testPalmBySize()
{
    ContactTracker t;
    // Two of the first three frames as wide as a palm
    CHECK(!t.update({sized(touch(1, TouchPhase::Began, 0.2, 0.2), 0, 11.0f)}, 0));
    CHECK(!t.update({sized(touch(1, TouchPhase::Moved, 0.21, 0.2), 0, 8.0f)}, 8));
    CHECK(!t.update({sized(touch(1, TouchPhase::Moved, 0.22, 0.2), 0, 12.0f)}, 16));
    CHECK(!t.update({sized(touch(1, TouchPhase::Moved, 0.5, 0.5), 0, 12.0f)}, 24));
    CHECK(!t.fingersDown() && t.rejected().palms == 1);

    // A fingertip
    ContactTracker f;
    auto down = settle(f, {sized(touch(1, TouchPhase::Began, 0.5, 0.5), 2, 8.5f)}, 0);
    CHECK(down && down->contacts[0].phase == luztouchpad::phase_down);
}

static void testLatePalm()
{
    ContactTracker t;
    settle(t, {sized(touch(1, TouchPhase::Began, 0.5, 0.5), 2, 8.0f)}, 0);
    CHECK(t.fingersDown());
    // It spreads: one wide frame isn't enough, two in a row are
    CHECK(t.update({sized(touch(1, TouchPhase::Moved, 0.51, 0.5), 2, 10.5f)}, 24));
    CHECK(t.fingersDown());
    auto cancel = t.update({sized(touch(1, TouchPhase::Moved, 0.52, 0.5), 2, 11.0f)}, 32);
    CHECK(cancel && cancel->contacts[0].phase == luztouchpad::phase_cancel);
    CHECK(!t.fingersDown() && t.touching() && t.rejected().late == 1);
    // ... and stays out until it lifts
    CHECK(!t.update({sized(touch(1, TouchPhase::Moved, 0.6, 0.5), 2, 8.0f)}, 40));
    t.update({touch(1, TouchPhase::Ended, 0.6, 0.5)}, 48);
    CHECK(!t.touching());

    // Apple relabelling it a palm cancels it at once
    settle(t, {sized(touch(2, TouchPhase::Began, 0.5, 0.5), 3, 8.0f)}, 100);
    auto relabelled = t.update({sized(touch(2, TouchPhase::Moved, 0.5, 0.51), 6, 8.0f)}, 124);
    CHECK(relabelled && relabelled->contacts[0].phase == luztouchpad::phase_cancel);
}

static void testTyping()
{
    ContactTracker t;
    // Within k_FirstKeyMs of a first key, a touch that lands is a palm
    t.keyDown(1000);
    CHECK(!t.update({touch(1, TouchPhase::Began, 0.8, 0.1)}, 1100));
    CHECK(!t.tick(1200));
    CHECK(t.rejected().typing == 1 && t.touching());
    t.update({touch(1, TouchPhase::Ended, 0.8, 0.1)}, 1240);

    // After it, a finger
    auto later = settle(t, {touch(2, TouchPhase::Began, 0.5, 0.5)}, 1250);
    CHECK(later && later->contacts[0].phase == luztouchpad::phase_down);
    t.update({touch(2, TouchPhase::Ended, 0.5, 0.5)}, 1300);

    // While keys keep coming, the window is k_TypingMs from the last one
    t.keyDown(2000);
    t.keyDown(2300);
    CHECK(!t.update({touch(3, TouchPhase::Began, 0.2, 0.1)}, 2700));
    CHECK(t.rejected().typing == 2);
    t.update({touch(3, TouchPhase::Ended, 0.2, 0.1)}, 2750);
    auto after = settle(t, {touch(4, TouchPhase::Began, 0.5, 0.5)}, 2810);
    CHECK(after && after->contacts[0].phase == luztouchpad::phase_down);
}

static void testRestingThumb()
{
    ContactTracker t;
    // A finger points...
    settle(t, {touch(1, TouchPhase::Began, 0.5, 0.6)}, 0);
    // ...while a thumb lands at the bottom and stays still: a resting thumb
    Touch thumb = sized(touch(2, TouchPhase::Began, 0.3, 0.05), 1, 8.0f);
    t.update({touch(1, TouchPhase::Moved, 0.52, 0.6), thumb}, 24);
    t.update({touch(1, TouchPhase::Moved, 0.54, 0.6), with(thumb, TouchPhase::Stationary)}, 32);
    auto f = t.update({touch(1, TouchPhase::Moved, 0.56, 0.6), with(thumb, TouchPhase::Stationary)}, 40);
    CHECK(f && f->count == 1 && f->contacts[0].slot == 0);
    CHECK(t.rejected().thumbs == 1);

    // A thumb on its own is a finger: some point with it
    ContactTracker alone;
    auto down = settle(alone, {sized(touch(1, TouchPhase::Began, 0.3, 0.05), 1, 8.0f)}, 0);
    CHECK(down && down->contacts[0].phase == luztouchpad::phase_down);

    // Without MultitouchSupport, any touch that lands like a resting thumb is one
    ContactTracker plain;
    settle(plain, {touch(1, TouchPhase::Began, 0.5, 0.6)}, 0);
    Touch still = touch(2, TouchPhase::Began, 0.3, 0.05);
    plain.update({touch(1, TouchPhase::Moved, 0.52, 0.6), still}, 24);
    plain.update({touch(1, TouchPhase::Moved, 0.54, 0.6), with(still, TouchPhase::Stationary)}, 32);
    plain.update({touch(1, TouchPhase::Moved, 0.56, 0.6), with(still, TouchPhase::Stationary)}, 40);
    CHECK(plain.rejected().thumbs == 1);

    // With it, a finger the driver doesn't call a thumb isn't one wherever it lands
    ContactTracker named;
    settle(named, {sized(touch(1, TouchPhase::Began, 0.5, 0.6), 2, 8.0f)}, 0);
    Touch index = sized(touch(2, TouchPhase::Began, 0.3, 0.05), 2, 8.0f);
    named.update({sized(touch(1, TouchPhase::Moved, 0.52, 0.6), 2, 8.0f), index}, 24);
    named.update({sized(touch(1, TouchPhase::Moved, 0.54, 0.6), 2, 8.0f), with(index, TouchPhase::Stationary)}, 32);
    auto both = named.update({sized(touch(1, TouchPhase::Moved, 0.56, 0.6), 2, 8.0f), with(index, TouchPhase::Stationary)}, 40);
    CHECK(both && both->count == 2);
    CHECK(named.rejected().thumbs == 0);
}

static void testVanished()
{
    ContactTracker t;
    settle(t, {touch(1, TouchPhase::Began, 0.3, 0.5), touch(2, TouchPhase::Began, 0.6, 0.5)}, 0);
    // An event from the same pad without finger 1: it went away without an end
    auto f = t.update({touch(2, TouchPhase::Moved, 0.6, 0.4)}, 24);
    CHECK(f && contactIn(*f, 0) && contactIn(*f, 0)->phase == luztouchpad::phase_cancel);

    // An event from another pad doesn't say anything about this one's fingers
    auto other = t.update({touch(9, TouchPhase::Began, 0.5, 0.5, 0x2000)}, 32);
    CHECK(!other);  // the other pad's finger is ignored while this pad is in use
    CHECK(t.fingersDown());

    // A touch waiting to be decided that vanishes is forgotten
    ContactTracker w;
    w.update({touch(1, TouchPhase::Began, 0.5, 0.5), touch(2, TouchPhase::Began, 0.2, 0.2)}, 0);
    w.update({touch(2, TouchPhase::Stationary, 0.2, 0.2)}, 8);
    auto one = w.update({touch(2, TouchPhase::Stationary, 0.2, 0.2)}, 16);
    CHECK(one && one->count == 1);
}

static void testIgnoredUntilLifted()
{
    ContactTracker t;
    // On the pad before passthrough started: never sent, but the pad is in use
    CHECK(!t.update({touch(1, TouchPhase::Moved, 0.5, 0.5)}, 0));
    CHECK(!t.fingersDown() && t.touching());
    CHECK(!t.update({touch(1, TouchPhase::Moved, 0.6, 0.5)}, 8));
    // A new finger while it's down is sent
    auto f = settle(t, {touch(1, TouchPhase::Moved, 0.6, 0.5), touch(2, TouchPhase::Began, 0.2, 0.2)}, 16);
    CHECK(f && f->count == 1 && f->contacts[0].phase == luztouchpad::phase_down);
    CHECK(!t.update({touch(1, TouchPhase::Ended, 0.6, 0.5), touch(2, TouchPhase::Stationary, 0.2, 0.2)}, 40));
    t.update({touch(2, TouchPhase::Ended, 0.2, 0.2)}, 48);
    CHECK(!t.touching());

    // An ignored finger that vanishes is forgotten too
    t.update({touch(5, TouchPhase::Moved, 0.5, 0.5)}, 60);
    CHECK(t.touching());
    settle(t, {touch(6, TouchPhase::Began, 0.5, 0.5)}, 70);
    t.update({touch(6, TouchPhase::Ended, 0.5, 0.5)}, 100);
    CHECK(!t.touching());
}

static void testMagicMouse()
{
    ContactTracker t;
    Touch mouse = touch(1, TouchPhase::Began, 0.5, 0.5, 0x3000);
    mouse.deviceWidth = 60;
    mouse.deviceHeight = 100;
    CHECK(!t.update({mouse}, 0));
    CHECK(!t.touching());
}

static void testButtonsAndKeepalive()
{
    ContactTracker t;
    // No finger: a press only changes the state
    CHECK(!t.setButton(true, 0));
    CHECK(!t.setButton(false, 1));
    CHECK(!t.keepalive(2));

    settle(t, {touch(1, TouchPhase::Began, 0.5, 0.5)}, 10);
    auto press = t.setButton(true, 30);
    CHECK(press && press->buttons == luztouchpad::button_pressed && press->count == 1);
    CHECK(press->contacts[0].phase == luztouchpad::phase_move);
    CHECK(!t.setButton(true, 31));  // no change

    auto alive = t.keepalive(130);
    CHECK(alive && alive->buttons == luztouchpad::button_pressed && alive->time_ms == 130);
    CHECK(!luztouchpad::is_reliable(*alive, luztouchpad::button_pressed));

    auto release = t.setButton(false, 140);
    CHECK(release && release->buttons == 0);

    // Lifting the last finger lets go of the pad
    t.setButton(true, 150);
    t.update({touch(1, TouchPhase::Ended, 0.5, 0.5)}, 160);
    CHECK(t.buttons() == 0);
}

static void testCancelAll()
{
    ContactTracker t;
    CHECK(!t.cancelAll(0));  // nothing sent yet

    settle(t, {touch(1, TouchPhase::Began, 0.5, 0.5)}, 10);
    auto all = t.cancelAll(40);
    CHECK(all && all->flags == luztouchpad::flag_cancel_all && all->count == 0 && all->buttons == 0);
    CHECK(all->width >= 13490);  // the pad's size is kept for the frame
    CHECK(!t.fingersDown());
    CHECK(!t.cancelAll(50));

    // reset() forgets without sending, and a touch still waiting to be decided too
    settle(t, {touch(2, TouchPhase::Began, 0.5, 0.5)}, 60);
    t.update({touch(2, TouchPhase::Stationary, 0.5, 0.5), touch(3, TouchPhase::Began, 0.2, 0.2)}, 90);
    t.reset();
    CHECK(!t.fingersDown() && !t.touching() && !t.cancelAll(100));
}

static void testGestureOnly()
{
    ContactTracker t;
    t.setGestureOnly(true);
    // One and two fingers stay on the Mac (macOS points and scrolls with them)
    CHECK(!settle(t, {touch(1, TouchPhase::Began, 0.3, 0.5)}, 0));
    CHECK(!settle(t, {touch(1, TouchPhase::Stationary, 0.3, 0.5), touch(2, TouchPhase::Began, 0.5, 0.5)}, 24));
    CHECK(t.fingersDown() && !t.gestureOpen());
    CHECK(!t.keepalive(60) && !t.setButton(true, 61));
    t.setButton(false, 62);

    // A third: all three go down together
    auto three = settle(t, {touch(1, TouchPhase::Stationary, 0.3, 0.5), touch(2, TouchPhase::Stationary, 0.5, 0.5),
                            touch(3, TouchPhase::Began, 0.7, 0.5)}, 70);
    CHECK(three && three->count == 3);
    for (std::size_t i = 0; i < three->count; i++) {
        CHECK(three->contacts[i].phase == luztouchpad::phase_down);
    }
    CHECK(t.gestureOpen());
    CHECK(t.keepalive(200).has_value());

    // It stays a gesture until the last finger lifts, even with fewer than three
    auto swipe = t.update({touch(1, TouchPhase::Moved, 0.3, 0.6), touch(2, TouchPhase::Ended, 0.5, 0.5),
                           touch(3, TouchPhase::Moved, 0.7, 0.6)}, 210);
    CHECK(swipe && swipe->count == 3 && contactIn(*swipe, 1)->phase == luztouchpad::phase_up);
    auto end = t.update({touch(1, TouchPhase::Ended, 0.3, 0.6), touch(3, TouchPhase::Ended, 0.7, 0.6)}, 220);
    CHECK(end && end->count == 2);
    CHECK(!t.gestureOpen() && !t.fingersDown());

    // A pinch macOS starts with two fingers opens it too
    settle(t, {touch(4, TouchPhase::Began, 0.4, 0.5), touch(5, TouchPhase::Began, 0.6, 0.5)}, 300);
    CHECK(!t.gestureOpen());
    auto pinch = t.openGesture(330);
    CHECK(pinch && pinch->count == 2 && pinch->contacts[0].phase == luztouchpad::phase_down);
    CHECK(!t.openGesture(331));
    auto spread = t.update({touch(4, TouchPhase::Moved, 0.3, 0.5), touch(5, TouchPhase::Moved, 0.7, 0.5)}, 340);
    CHECK(spread && spread->count == 2 && spread->contacts[0].phase == luztouchpad::phase_move);

    // A palm isn't a finger of a gesture
    ContactTracker p;
    p.setGestureOnly(true);
    auto palm = settle(p, {touch(1, TouchPhase::Began, 0.3, 0.5), touch(2, TouchPhase::Began, 0.5, 0.5),
                           sized(touch(3, TouchPhase::Began, 0.9, 0.1), 6, 14.0f)}, 0);
    CHECK(!palm && !p.gestureOpen());
}

static void testPinchBeforeDecided()
{
    // macOS can start a pinch while its fingers are still being decided: they go down once they are
    ContactTracker t;
    t.setGestureOnly(true);
    CHECK(!t.update({touch(1, TouchPhase::Began, 0.4, 0.5), touch(2, TouchPhase::Began, 0.6, 0.5)}, 0));
    CHECK(!t.openGesture(10));
    CHECK(t.gestureOpen());
    auto down = t.update({touch(1, TouchPhase::Moved, 0.38, 0.5), touch(2, TouchPhase::Moved, 0.62, 0.5)}, 20);
    CHECK(!down);
    down = t.update({touch(1, TouchPhase::Moved, 0.36, 0.5), touch(2, TouchPhase::Moved, 0.64, 0.5)}, 30);
    CHECK(down && down->count == 2 && down->contacts[0].phase == luztouchpad::phase_down &&
          down->contacts[1].phase == luztouchpad::phase_down);

    // A pinch for touches that all turn out to be palms opens nothing
    ContactTracker p;
    p.setGestureOnly(true);
    p.update({sized(touch(1, TouchPhase::Began, 0.4, 0.2), 2, 12.0f)}, 0);
    p.openGesture(5);
    CHECK(!p.update({sized(touch(1, TouchPhase::Moved, 0.4, 0.2), 2, 12.0f)}, 10));
    CHECK(!p.gestureOpen());
    // and a finger after it stays on the Mac
    CHECK(!settle(p, {with(sized(touch(1, TouchPhase::Moved, 0.4, 0.2), 2, 12.0f), TouchPhase::Stationary),
                      touch(2, TouchPhase::Began, 0.5, 0.5)}, 100));
    CHECK(p.fingersDown() && !p.gestureOpen());
}

static void testCarry()
{
    Carry c;
    // Slow motion adds up instead of rounding away
    int total = 0;
    for (int i = 0; i < 10; i++) {
        total += c.take(0.25);
    }
    CHECK(total == 2);
    CHECK(c.take(0.5) == 1);  // 0.5 left from before
    // Toward zero both ways, keeping what's left
    Carry n;
    CHECK(n.take(-1.75) == -1);
    CHECK(n.take(-0.25) == -1);
    CHECK(n.take(0.4) == 0);
    // Out of a short's range: clamped, the rest dropped
    Carry big;
    CHECK(big.take(50000.5) == 32767);
    CHECK(big.take(0.25) == 0);
    CHECK(big.take(0.0 / 0.0) == 0);
    c.reset();
    CHECK(c.take(0.9) == 0);
}

static void testMacMute()
{
    MacMute m;
    CHECK(!m.muteMotion(1000));
    m.pointerHandled(1000);
    CHECK(m.muteMotion(1000));
    CHECK(m.muteMotion(995));  // SDL stamped its copy first
    CHECK(m.muteMotion(1100));
    CHECK(!m.muteMotion(1200));  // a mouse event macOS's monitor never saw
    CHECK(!m.muteMotion(800));

    // Clicks pass, except one pressed while a gesture is open, with its release
    CHECK(!m.button(1, true, false));
    CHECK(!m.button(1, false, false));
    CHECK(m.button(1, true, true));
    CHECK(m.button(1, false, false));
    CHECK(!m.button(1, false, false));
    m.button(3, true, true);
    m.reset();
    CHECK(!m.button(3, false, false));
    CHECK(!m.muteMotion(1000));
}

static void testMuteMotionAndWheel()
{
    MuteFilter m;
    CHECK(!m.muteMotion(100));
    m.touching(true, 1000);
    CHECK(m.muteMotion(996));  // just before the touch's stamp
    CHECK(!m.muteMotion(990));
    CHECK(m.muteMotion(1500));
    m.touching(false, 2000);
    CHECK(m.muteMotion(2100));
    CHECK(!m.muteMotion(2200));

    // An external mouse's wheel well after the lift passes
    CHECK(!m.muteWheel(2500));

    // Momentum scrolling after a two-finger scroll keeps being muted while it keeps coming
    m.touching(true, 3000);
    m.touching(false, 3100);
    CHECK(m.muteWheel(3200));
    CHECK(m.muteWheel(3290));
    CHECK(m.muteWheel(3380));
    CHECK(!m.muteWheel(3600));  // a gap breaks the chain
    CHECK(!m.muteWheel(3650));

    // Events stamped across the clock wrapping
    MuteFilter w;
    w.touching(true, 0xFFFFFFF0u);
    CHECK(w.muteMotion(0x00000010u));
}

static void testButtons()
{
    MuteFilter m;
    // No finger: an external mouse's click passes, down and up
    CHECK(m.button(1, true, 100) == ButtonAction::Pass);
    CHECK(m.button(1, false, 150) == ButtonAction::Pass);

    // A click with a finger on the pad presses the pad
    m.touching(true, 1000);
    CHECK(m.button(1, true, 1100) == ButtonAction::PressPad);
    m.touching(false, 1200);
    // The release after the lift still releases the pad
    CHECK(m.button(1, false, 1210) == ButtonAction::ReleasePad);

    // macOS's tap to click, just after a tap
    m.touching(true, 2000);
    m.touching(false, 2050);
    CHECK(m.button(1, true, 2080) == ButtonAction::Mute);
    CHECK(m.button(1, false, 2090) == ButtonAction::Mute);

    // A two-finger click: right and left together, released with the last
    m.touching(true, 3000);
    CHECK(m.button(3, true, 3010) == ButtonAction::PressPad);
    CHECK(m.button(1, true, 3011) == ButtonAction::PressPad);
    CHECK(m.button(3, false, 3100) == ButtonAction::Mute);
    CHECK(m.button(1, false, 3101) == ButtonAction::ReleasePad);
    m.touching(false, 3200);

    // reset() forgets held buttons
    m.touching(true, 4000);
    m.button(1, true, 4010);
    m.reset();
    CHECK(m.button(1, false, 4020) == ButtonAction::Pass);
    CHECK(!m.muteMotion(4030));
}

static void testShouldBeActive()
{
    Conditions c;
    c.settingOn = c.hostSupports = c.captured = c.relativeMouse = true;
    c.windowFocused = c.windowKey = c.appActive = true;
    CHECK(shouldBeActive(c));

    bool Conditions::*fields[] = {
        &Conditions::settingOn, &Conditions::hostSupports, &Conditions::captured, &Conditions::relativeMouse,
        &Conditions::windowFocused, &Conditions::windowKey, &Conditions::appActive,
    };
    for (auto field : fields) {
        Conditions off = c;
        off.*field = false;
        CHECK(!shouldBeActive(off));
    }
}

static void testReliability()
{
    ContactTracker t;
    auto down = settle(t, {touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    CHECK(luztouchpad::is_reliable(*down, 0));
    auto move = t.update({touch(1, TouchPhase::Moved, 0.6, 0.5)}, 24);
    CHECK(!luztouchpad::is_reliable(*move, 0));
    auto up = t.update({touch(1, TouchPhase::Ended, 0.6, 0.5)}, 32);
    CHECK(luztouchpad::is_reliable(*up, 0));
}

int main()
{
    testPadSize();
    testOneFinger();
    testDecidedFromWhereItIs();
    testQuickTap();
    testTwoFingers();
    testSixthFinger();
    testCancelAndResting();
    testPalmByHand();
    testPalmBySize();
    testLatePalm();
    testTyping();
    testRestingThumb();
    testVanished();
    testIgnoredUntilLifted();
    testMagicMouse();
    testButtonsAndKeepalive();
    testCancelAll();
    testGestureOnly();
    testPinchBeforeDecided();
    testCarry();
    testMacMute();
    testMuteMotionAndWheel();
    testButtons();
    testShouldBeActive();
    testReliability();

    if (s_Failures == 0) {
        std::printf("trackpad: all tests passed\n");
        return 0;
    }
    std::printf("trackpad: %d failure(s)\n", s_Failures);
    return 1;
}
