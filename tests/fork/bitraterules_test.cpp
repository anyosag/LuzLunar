// Tests for app/fork/bitraterules.cpp: adaptive bitrate's controller, fed one simulated second at a
// time. A standalone program for the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/bitraterules_test.cpp app/fork/bitraterules.cpp

#include "fork/bitraterules.h"

#include <cstdio>
#include <vector>

using namespace BitrateRules;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

// A 120 fps stream, whose stats cover about 2 s
static Sample second(double t, double drop = 0, uint32_t rtt = 20, bool poor = false)
{
    Sample s;
    s.seconds = t;
    s.dropPercent = drop;
    s.lostFrames = (uint32_t) (drop * 240 / 100 + 0.5);
    s.rttMs = rtt;
    s.poor = poor;
    return s;
}

// Ticks from..to (inclusive) with the same conditions; returns the changes asked for, in order
static std::vector<int> run(Controller& c, int from, int to, double drop = 0, uint32_t rtt = 20, bool poor = false)
{
    std::vector<int> changes;
    for (int t = from; t <= to; t++) {
        int kbps = c.tick(second(t, drop, rtt, poor));
        if (kbps) {
            changes.push_back(kbps);
        }
    }
    return changes;
}

static void testFloor()
{
    CHECK(floorKbps(20000, false) == 4000);
    CHECK(floorKbps(10000, false) == 3000);
    CHECK(floorKbps(10000, true) == 5000);
    CHECK(floorKbps(100000, false) == 20000);
    CHECK(floorKbps(100000, true) == 20000);
    // Never above the user's own bitrate
    CHECK(floorKbps(2000, false) == 2000);
    CHECK(floorKbps(4000, true) == 4000);
}

static void testCleanStream()
{
    Controller c(20000, false);
    CHECK(run(c, 1, 120).empty());
    CHECK(c.currentKbps() == 20000);
    CHECK(!c.lowered());
}

static void testLossCutsAndHolds()
{
    Controller c(20000, false);

    // Nothing in the first 5 s, whatever happens
    CHECK(run(c, 1, 4, 10.0).empty());

    // Then 70%, held for 10 s, then 70% again
    CHECK(c.tick(second(5, 10.0)) == 14000);
    CHECK(run(c, 6, 14, 10.0).empty());
    CHECK(c.tick(second(15, 10.0)) == 9800);
    CHECK(c.lowered());
    CHECK(c.lastLossKbps() == 14000);

    // Down to the floor and no further
    auto changes = run(c, 16, 120, 10.0);
    CHECK(!changes.empty() && changes.back() == 4000);
    CHECK(c.currentKbps() == 4000);
    CHECK(run(c, 121, 200, 10.0).empty());

    // Just under 2% isn't a loss
    Controller d(20000, false);
    CHECK(run(d, 1, 60, 1.9).empty());

    // A poor connection counts like a loss
    Controller e(20000, false);
    CHECK(e.tick(second(5, 0, 20, true)) == 14000);

    // A quiet desktop sends a few frames a second: one or two lost aren't a loss, three are
    Controller f(20000, false);
    Sample quiet = second(5);
    quiet.dropPercent = 10.0;
    quiet.lostFrames = 1;
    CHECK(f.tick(quiet) == 0);
    quiet.seconds = 6;
    quiet.lostFrames = 2;
    CHECK(f.tick(quiet) == 0);
    quiet.seconds = 7;
    quiet.lostFrames = 3;
    CHECK(f.tick(quiet) == 14000);
}

static void testClimb()
{
    Controller c(20000, false);
    CHECK(c.tick(second(5, 5.0)) == 14000);
    CHECK(c.lastLossKbps() == 20000);

    // The loss ends at 5 s. A climb waits for 5 clean seconds and the 10 s hold: 15 s.
    CHECK(run(c, 6, 14).empty());
    CHECK(c.tick(second(15)) == 15000);
    // Then 5% of 20 Mb/s every 5 s...
    CHECK(run(c, 16, 19).empty());
    CHECK(c.tick(second(20)) == 16000);
    CHECK(c.tick(second(25)) == 17000);
    // ...and every 15 s from 85% of the bitrate it had to leave (17 Mb/s)
    CHECK(c.tick(second(30)) == 18000);
    CHECK(run(c, 31, 44).empty());
    CHECK(c.tick(second(45)) == 19000);
    CHECK(run(c, 46, 59).empty());
    CHECK(c.tick(second(60)) == 20000);
    CHECK(c.lastLossKbps() == 0);
    CHECK(!c.lowered());
    // Not past the user's bitrate
    CHECK(run(c, 61, 200).empty());
    CHECK(c.currentKbps() == 20000);

    // A loss during the hold restarts the wait
    Controller d(20000, false);
    CHECK(d.tick(second(5, 5.0)) == 14000);
    CHECK(d.tick(second(12, 3.0)) == 0);    // held, but the clock restarts
    CHECK(run(d, 13, 16).empty());          // only 4 clean seconds
    CHECK(d.tick(second(17)) == 15000);
}

static void testClimbSlowsNearTheLastLoss()
{
    Controller c(20000, false);
    CHECK(c.tick(second(5, 5.0)) == 14000);
    CHECK(c.tick(second(15, 5.0)) == 9800);
    CHECK(c.lastLossKbps() == 14000);
    // Climbing from 9.8 Mb/s: 5 s steps while below 85% of 14 Mb/s (11.9 Mb/s), after the hold
    CHECK(run(c, 16, 24).empty());
    CHECK(c.tick(second(25)) == 10800);
    CHECK(c.tick(second(30)) == 11800);
    CHECK(c.tick(second(35)) == 12800);
    // 12.8 Mb/s is near 14: 15 s per step from here
    CHECK(c.tick(second(40)) == 13800);
    CHECK(run(c, 41, 54).empty());
    CHECK(c.tick(second(55)) == 14800);
    CHECK(c.lastLossKbps() == 0);
    // Past it: 5 s steps again, after that step's hold
    CHECK(run(c, 56, 69).empty());
    CHECK(c.tick(second(70)) == 15800);
    CHECK(c.tick(second(75)) == 16800);

    // A slow climb still lets a loss cut 5 s after it, not 15
    Controller d(20000, false);
    CHECK(d.tick(second(5, 5.0)) == 14000);
    run(d, 6, 29);
    CHECK(d.currentKbps() == 17000);
    CHECK(d.tick(second(30)) == 18000);     // near 20 Mb/s: the next climb is 15 s away
    CHECK(run(d, 31, 34, 5.0).empty());     // the 5 s every change waits
    CHECK(d.tick(second(35, 5.0)) == 12600);
}

static void testRoundTripTime()
{
    // 20 ms as the base; 60 ms is above 20 + 30 ms for 3 s: 90%
    Controller c(20000, false);
    run(c, 1, 10, 0, 20);
    CHECK(c.baseRttMs() == 20);
    CHECK(c.tick(second(11, 0, 60)) == 0);
    CHECK(c.tick(second(12, 0, 60)) == 0);
    CHECK(c.tick(second(13, 0, 60)) == 18000);

    // 45 ms is within 20 + 30 ms: no queue
    Controller d(20000, false);
    run(d, 1, 10, 0, 20);
    CHECK(run(d, 11, 60, 0, 45).empty());

    // A longer base gets half of it as margin: 100 ms base, 140 ms is fine, 160 ms isn't
    Controller e(20000, false);
    run(e, 1, 10, 0, 100);
    CHECK(run(e, 11, 20, 0, 140).empty());
    Controller f(20000, false);
    run(f, 1, 10, 0, 100);
    auto changes = run(f, 11, 13, 0, 160);
    CHECK(changes.size() == 1 && changes[0] == 18000);

    // A route that got slower for good becomes the base within 30 s, and cuts stop: two, at 13 s
    // and 23 s
    Controller g(20000, false);
    run(g, 1, 10, 0, 20);
    changes = run(g, 11, 40, 0, 80);
    CHECK(changes.size() == 2);
    CHECK(g.baseRttMs() == 80);
    CHECK(g.currentKbps() == 16200);
    // ...and it climbs back
    changes = run(g, 41, 200, 0, 80);
    CHECK(!changes.empty() && changes.back() == 20000);

    // An unknown round-trip time counts for nothing
    Controller h(20000, false);
    CHECK(run(h, 1, 60, 0, 0).empty());
    CHECK(h.baseRttMs() == 0);
}

static void testSmallBitrates()
{
    // The floor is the user's bitrate: nothing to change
    Controller c(2500, false);
    CHECK(c.floorKbps() == 2500);
    CHECK(run(c, 1, 100, 20.0).empty());

    // HDR's floor
    Controller d(8000, true);
    auto changes = run(d, 1, 100, 20.0);
    CHECK(!changes.empty() && changes.back() == 5000);
}

int main()
{
    testFloor();
    testCleanStream();
    testLossCutsAndHolds();
    testClimb();
    testClimbSlowsNearTheLastLoss();
    testRoundTripTime();
    testSmallBitrates();

    if (s_Failures == 0) {
        std::printf("bitraterules: all tests passed\n");
        return 0;
    }
    std::printf("bitraterules: %d failure(s)\n", s_Failures);
    return 1;
}
