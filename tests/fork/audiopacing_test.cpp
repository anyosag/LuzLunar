// Tests for app/fork/audiopacing.*: how SDL's audio renderer paces the stream's sound (the reserve it
// plays from, building it again after a pause, the drift correction, throwing a packet away only
// past the cap). A standalone program, so CI builds it without the app:
//   clang++ -std=c++17 -Iapp tests/fork/audiopacing_test.cpp app/fork/audiopacing.cpp

#include "fork/audiopacing.h"

#include <cstdio>

using namespace AudioPacing;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

// 5 ms packets at 48 kHz, as the stream sends them
constexpr int k_Frames = 240;

static void testReserve()
{
    // Nothing plays until 30 ms wait: the 6th packet brings it there, with 25 ms already queued
    Pacer pacer(48000);
    for (int i = 0; i < 5; i++) {
        Decision d = pacer.packet(i * 5.0, i * 5.0, k_Frames);
        CHECK(!d.start && !d.hold && !d.drop && d.adjust == 0);
        CHECK(!pacer.playing());
    }
    Decision d = pacer.packet(25, 25, k_Frames);
    CHECK(d.start && !d.hold);
    CHECK(pacer.playing());

    // Playing, near the target: nothing to do
    d = pacer.packet(30, 28, k_Frames);
    CHECK(!d.start && !d.hold && !d.drop && d.adjust == 0);
}

static void testPause()
{
    Pacer pacer(48000);
    for (int i = 0; i <= 5; i++) {
        pacer.packet(i * 5.0, i * 5.0, k_Frames);
    }
    CHECK(pacer.playing());

    // A late packet (100 ms, less than a pause) with nothing queued plays on: the device already
    // played silence for it, and holding now would only add a gap
    Decision d = pacer.packet(125, 0, k_Frames);
    CHECK(!d.hold && pacer.playing());

    // The PC paused (silence, 2 s) and everything played: build the reserve again
    d = pacer.packet(2125, 0, k_Frames);
    CHECK(d.hold && !d.start);
    CHECK(!pacer.playing());
    for (int i = 1; i <= 4; i++) {
        d = pacer.packet(2125 + i * 5.0, i * 5.0, k_Frames);
        CHECK(!d.start && !d.hold);
    }
    d = pacer.packet(2150, 25, k_Frames);
    CHECK(d.start && pacer.playing());

    // A pause with sound still queued (it can't have run out yet): nothing to rebuild
    d = pacer.packet(3000, 10, k_Frames);
    CHECK(!d.hold && pacer.playing());
}

static void testDrift()
{
    Settings settings;
    Pacer pacer(48000, settings);
    double t = 0;
    for (int i = 0; i <= 5; i++, t += 5) {
        pacer.packet(t, i * 5.0, k_Frames);
    }
    // Every 1000 frames (the 5th packet of 240: 1200 frames) one adjustment, if away from the target
    int adjusts = 0;
    int sign = 0;
    for (int i = 0; i < 20; i++, t += 5) {
        Decision d = pacer.packet(t, 70, k_Frames);     // too much waiting
        if (d.adjust != 0) {
            adjusts++;
            sign = d.adjust;
        }
    }
    CHECK(adjusts == 4 && sign == -1);

    adjusts = 0;
    for (int i = 0; i < 20; i++, t += 5) {
        Decision d = pacer.packet(t, 5, k_Frames);      // too little
        if (d.adjust != 0) {
            adjusts++;
            sign = d.adjust;
        }
    }
    CHECK(adjusts == 4 && sign == +1);

    adjusts = 0;
    for (int i = 0; i < 20; i++, t += 5) {
        Decision d = pacer.packet(t, 30, k_Frames);     // at the target: never
        adjusts += d.adjust != 0;
    }
    CHECK(adjusts == 0);
}

static void testCap()
{
    Pacer pacer(48000);
    for (int i = 0; i <= 5; i++) {
        pacer.packet(i * 5.0, i * 5.0, k_Frames);
    }
    // A burst after a stall: thrown away only past 120 ms
    Decision d = pacer.packet(30, 119, k_Frames);
    CHECK(!d.drop);
    d = pacer.packet(35, 121, k_Frames);
    CHECK(d.drop && d.adjust == 0);
    CHECK(pacer.playing());

    // While building the reserve, nothing is thrown away
    Pacer fresh(48000);
    d = fresh.packet(0, 200, k_Frames);
    CHECK(!d.drop && d.start);
}

static void testOtherRates()
{
    // 10 ms packets at 48 kHz (slow connections): three bring 30 ms
    Pacer pacer(48000);
    CHECK(!pacer.packet(0, 0, 480).start);
    CHECK(!pacer.packet(10, 10, 480).start);
    CHECK(pacer.packet(20, 20, 480).start);
}

int main()
{
    testReserve();
    testPause();
    testDrift();
    testCap();
    testOtherRates();
    if (s_Failures) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("audiopacing: all checks passed\n");
    return 0;
}
