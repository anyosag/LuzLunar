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
    auto down = t.update({touch(1, TouchPhase::Began, 0.25, 0.75)}, 100);
    CHECK(down.has_value());
    CHECK(down->count == 1);
    CHECK(down->contacts[0].slot == 0);
    CHECK(down->contacts[0].phase == luztouchpad::phase_down);
    // x from the left; y flipped to the pad's top
    CHECK(down->contacts[0].x == 16384);
    CHECK(down->contacts[0].y == 16384);
    CHECK(down->time_ms == 100);
    CHECK(down->width >= 13490 && down->width <= 13510);
    CHECK(t.fingersDown() && t.touching());

    auto move = t.update({touch(1, TouchPhase::Moved, 0.5, 0.5)}, 108);
    CHECK(move && move->contacts[0].phase == luztouchpad::phase_move);
    CHECK(move->contacts[0].x == 32768);

    // Unchanged positions send nothing
    CHECK(!t.update({touch(1, TouchPhase::Stationary, 0.5, 0.5)}, 116));

    auto up = t.update({touch(1, TouchPhase::Ended, 0.5, 0.5)}, 124);
    CHECK(up && up->count == 1 && up->contacts[0].phase == luztouchpad::phase_up);
    CHECK(!t.fingersDown() && !t.touching());

    // The slot is free for the next finger
    auto again = t.update({touch(2, TouchPhase::Began, 0.1, 0.1)}, 200);
    CHECK(again && again->contacts[0].slot == 0);
}

static void testTwoFingers()
{
    ContactTracker t;
    t.update({touch(1, TouchPhase::Began, 0.3, 0.5)}, 0);
    auto two = t.update({touch(1, TouchPhase::Stationary, 0.3, 0.5), touch(2, TouchPhase::Began, 0.6, 0.5)}, 8);
    CHECK(two && two->count == 2);
    auto first = contactIn(*two, 0);
    auto second = contactIn(*two, 1);
    CHECK(first && first->phase == luztouchpad::phase_move);
    CHECK(second && second->phase == luztouchpad::phase_down);

    // The first lifts; the frame still lists the second
    auto lift = t.update({touch(1, TouchPhase::Ended, 0.3, 0.5), touch(2, TouchPhase::Moved, 0.6, 0.4)}, 16);
    CHECK(lift && lift->count == 2);
    CHECK(contactIn(*lift, 0)->phase == luztouchpad::phase_up);
    CHECK(contactIn(*lift, 1)->phase == luztouchpad::phase_move);
    auto next = t.update({touch(2, TouchPhase::Moved, 0.6, 0.3)}, 24);
    CHECK(next && next->count == 1 && next->contacts[0].slot == 1);
}

static void testSixthFinger()
{
    ContactTracker t;
    std::vector<Touch> touches;
    for (std::uintptr_t id = 1; id <= 6; id++) {
        touches.push_back(touch(id, TouchPhase::Began, 0.1 * id, 0.5));
    }
    auto f = t.update(touches, 0);
    CHECK(f && f->count == 5);
    // The sixth is ignored, but the pad counts as touched
    touches.resize(5);
    for (auto& tc : touches) {
        tc.phase = TouchPhase::Stationary;
    }
    touches.push_back(touch(6, TouchPhase::Moved, 0.9, 0.9));
    CHECK(!t.update(touches, 8));
}

static void testCancelAndResting()
{
    ContactTracker t;
    t.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    auto cancel = t.update({touch(1, TouchPhase::Cancelled, 0.5, 0.5)}, 8);
    CHECK(cancel && cancel->contacts[0].phase == luztouchpad::phase_cancel);
    CHECK(!t.fingersDown());

    // A finger macOS decides is a resting thumb is cancelled, not lifted (no tap)
    t.update({touch(2, TouchPhase::Began, 0.5, 0.1)}, 16);
    Touch resting = touch(2, TouchPhase::Stationary, 0.5, 0.1);
    resting.resting = true;
    auto rest = t.update({resting}, 24);
    CHECK(rest && rest->contacts[0].phase == luztouchpad::phase_cancel);

    // A resting touch that begins is never sent
    Touch palm = touch(3, TouchPhase::Began, 0.9, 0.1);
    palm.resting = true;
    CHECK(!t.update({palm}, 32));
    CHECK(!t.fingersDown());
}

static void testVanished()
{
    ContactTracker t;
    t.update({touch(1, TouchPhase::Began, 0.3, 0.5), touch(2, TouchPhase::Began, 0.6, 0.5)}, 0);
    // An event from the same pad without finger 1: it went away without an end
    auto f = t.update({touch(2, TouchPhase::Moved, 0.6, 0.4)}, 8);
    CHECK(f && contactIn(*f, 0) && contactIn(*f, 0)->phase == luztouchpad::phase_cancel);

    // An event from another pad doesn't say anything about this one's fingers
    auto other = t.update({touch(9, TouchPhase::Began, 0.5, 0.5, 0x2000)}, 16);
    CHECK(!other);  // the other pad's finger is ignored while this pad is in use
    CHECK(t.fingersDown());
}

static void testIgnoredUntilLifted()
{
    ContactTracker t;
    // On the pad before passthrough started: never sent, but the pad is in use
    CHECK(!t.update({touch(1, TouchPhase::Moved, 0.5, 0.5)}, 0));
    CHECK(!t.fingersDown() && t.touching());
    CHECK(!t.update({touch(1, TouchPhase::Moved, 0.6, 0.5)}, 8));
    // A new finger while it's down is sent
    auto f = t.update({touch(1, TouchPhase::Moved, 0.6, 0.5), touch(2, TouchPhase::Began, 0.2, 0.2)}, 16);
    CHECK(f && f->count == 1 && f->contacts[0].phase == luztouchpad::phase_down);
    CHECK(!t.update({touch(1, TouchPhase::Ended, 0.6, 0.5), touch(2, TouchPhase::Stationary, 0.2, 0.2)}, 24));
    t.update({touch(2, TouchPhase::Ended, 0.2, 0.2)}, 32);
    CHECK(!t.touching());

    // An ignored finger that vanishes is forgotten too
    t.update({touch(5, TouchPhase::Moved, 0.5, 0.5)}, 40);
    CHECK(t.touching());
    t.update({touch(6, TouchPhase::Began, 0.5, 0.5)}, 48);
    t.update({touch(6, TouchPhase::Ended, 0.5, 0.5)}, 56);
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

    t.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 10);
    auto press = t.setButton(true, 12);
    CHECK(press && press->buttons == luztouchpad::button_pressed && press->count == 1);
    CHECK(press->contacts[0].phase == luztouchpad::phase_move);
    CHECK(!t.setButton(true, 13));  // no change

    auto alive = t.keepalive(112);
    CHECK(alive && alive->buttons == luztouchpad::button_pressed && alive->time_ms == 112);
    CHECK(!luztouchpad::is_reliable(*alive, luztouchpad::button_pressed));

    auto release = t.setButton(false, 120);
    CHECK(release && release->buttons == 0);

    // Lifting the last finger lets go of the pad
    t.setButton(true, 130);
    t.update({touch(1, TouchPhase::Ended, 0.5, 0.5)}, 140);
    CHECK(t.buttons() == 0);
}

static void testCancelAll()
{
    ContactTracker t;
    CHECK(!t.cancelAll(0));  // nothing sent yet

    t.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 10);
    auto all = t.cancelAll(20);
    CHECK(all && all->flags == luztouchpad::flag_cancel_all && all->count == 0 && all->buttons == 0);
    CHECK(all->width >= 13490);  // the pad's size is kept for the frame
    CHECK(!t.fingersDown());
    CHECK(!t.cancelAll(30));

    // reset() forgets without sending
    t.update({touch(2, TouchPhase::Began, 0.5, 0.5)}, 40);
    t.reset();
    CHECK(!t.fingersDown() && !t.cancelAll(50));
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
    auto down = t.update({touch(1, TouchPhase::Began, 0.5, 0.5)}, 0);
    CHECK(luztouchpad::is_reliable(*down, 0));
    auto move = t.update({touch(1, TouchPhase::Moved, 0.6, 0.5)}, 8);
    CHECK(!luztouchpad::is_reliable(*move, 0));
    auto up = t.update({touch(1, TouchPhase::Ended, 0.6, 0.5)}, 16);
    CHECK(luztouchpad::is_reliable(*up, 0));
}

int main()
{
    testPadSize();
    testOneFinger();
    testTwoFingers();
    testSixthFinger();
    testCancelAndResting();
    testVanished();
    testIgnoredUntilLifted();
    testMagicMouse();
    testButtonsAndKeepalive();
    testCancelAll();
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
