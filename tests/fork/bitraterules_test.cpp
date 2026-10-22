// Tests for app/fork/bitraterules.cpp: adaptive bitrate's controller, fed one simulated second at a
// time. A standalone program for the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/bitraterules_test.cpp app/fork/bitraterules.cpp

#include "fork/bitraterules.h"

#include <algorithm>
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

    // A route that got slower for good: the cuts at 13 s and 23 s leave it at 80 ms, so at 33 s
    // 80 ms becomes the base instead of a third cut
    Controller g(20000, false);
    run(g, 1, 10, 0, 20);
    changes = run(g, 11, 32, 0, 80);
    CHECK(changes.size() == 2);
    CHECK(g.baseRttMs() == 20);
    CHECK(g.tick(second(33, 0, 80)) == 0);
    CHECK(g.baseRttMs() == 80);
    CHECK(run(g, 34, 40, 0, 80).empty());
    CHECK(g.currentKbps() == 16200);
    // ...and it climbs back
    changes = run(g, 41, 200, 0, 80);
    CHECK(!changes.empty() && changes.back() == 20000);

    // An unknown round-trip time counts for nothing
    Controller h(20000, false);
    CHECK(run(h, 1, 60, 0, 0).empty());
    CHECK(h.baseRttMs() == 0);
}

static void testRoundTripBase()
{
    // A queue that keeps growing, a little more at each cut: no two cuts find it where the first did,
    // so the cuts go on, then the checks at the floor, and the base stays 20 ms
    Controller a(20000, false);
    run(a, 1, 10, 0, 20);
    std::vector<int> changes;
    for (int t = 11; t <= 120; t++) {
        int kbps = a.tick(second(t, 0, 60 + 5 * (t - 11)));
        if (kbps) {
            changes.push_back(kbps);
        }
    }
    CHECK(changes.size() >= 10);
    CHECK(a.baseRttMs() == 20);

    // A link that carries 15 Mb/s from 11 s on: the round-trip time follows the bitrate, each cut
    // brings it back under the line, and climbs find the limit again. Cuts keep coming at levels
    // close to each other, but the time back under the line in between shows the queue is the
    // stream's own: the base stays 20 ms.
    Controller b(20000, false);
    run(b, 1, 10, 0, 20);
    int cuts = 0;
    for (int t = 11; t <= 300; t++) {
        int before = b.currentKbps();
        uint32_t rtt = 20 + (uint32_t) std::max(0, before - 15000) / 50;
        int kbps = b.tick(second(t, 0, rtt));
        if (kbps && kbps < before) {
            cuts++;
        }
    }
    CHECK(cuts >= 5);
    CHECK(b.baseRttMs() == 20);
    CHECK(b.currentKbps() < 18000);

    // The lowest of the whole stream, not of the last seconds: after a minute at 45 ms (within
    // 20 + 30 ms), 70 ms is still a queue against 20 ms
    Controller c(20000, false);
    run(c, 1, 10, 0, 20);
    CHECK(run(c, 11, 70, 0, 45).empty());
    CHECK(c.baseRttMs() == 20);
    CHECK(run(c, 71, 72, 0, 70).empty());
    CHECK(c.tick(second(73, 0, 70)) == 18000);

    // At the floor nothing can be cut, but the route's check still runs every 10 s: it cuts to
    // the floor at 13 s, can't at 23 s, takes 80 ms as the base at 33 s, and climbs back
    Controller d(3300, false);
    CHECK(d.floorKbps() == 3000);
    run(d, 1, 10, 0, 20);
    changes = run(d, 11, 33, 0, 80);
    CHECK(changes.size() == 1 && changes[0] == 3000);
    CHECK(d.baseRttMs() == 80);
    changes = run(d, 34, 120, 0, 80);
    CHECK(!changes.empty() && changes.back() == 3300);

    // A loss starts the route's count over: a slower route plus a loss takes two more cuts to learn
    Controller e(20000, false);
    run(e, 1, 10, 0, 20);
    CHECK(run(e, 11, 23, 0, 80).size() == 2);   // 18000 at 13 s, 16200 at 23 s
    run(e, 24, 32, 0, 80);
    CHECK(e.tick(second(33, 5.0, 80)) == 11340); // a loss cut instead of learning the route
    CHECK(e.baseRttMs() == 20);
    CHECK(run(e, 34, 62, 0, 80).size() == 2);   // two more round-trip cuts, at 43 s and 53 s
    CHECK(e.baseRttMs() == 20);
    CHECK(e.tick(second(63, 0, 80)) == 0);
    CHECK(e.baseRttMs() == 80);
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
    testRoundTripBase();
    testSmallBitrates();

    if (s_Failures == 0) {
        std::printf("bitraterules: all tests passed\n");
        return 0;
    }
    std::printf("bitraterules: %d failure(s)\n", s_Failures);
    return 1;
}
