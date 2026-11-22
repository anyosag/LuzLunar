// Tests for app/fork/audiohealth.*: what the stream's sound went through on its way to the speakers
// (late packets, nothing queued, thrown away), and when it says so in the log. A standalone program,
// so CI builds it without the app:
//   clang++ -std=c++17 -Iapp tests/fork/audiohealth_test.cpp app/fork/audiohealth.cpp

#include "fork/audiohealth.h"

#include <cstdio>
#include <string>

using namespace AudioHealth;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static bool contains(const std::string& text, const char* part)
{
    return text.find(part) != std::string::npos;
}

static void testSteady()
{
    // Packets every 5 ms with 10 to 20 ms queued: nothing late, nothing to report
    Monitor monitor(15.0);
    CHECK(monitor.summary().empty());
    for (int i = 0; i < 2000; i++) {
        monitor.packet(i * 5.0, 10.0 + (i % 3) * 5.0);
    }
    const Counters& c = monitor.total();
    CHECK(c.packets == 2000);
    CHECK(c.late == 0 && c.ranDry == 0 && c.thrownAway == 0 && c.waits == 0);
    CHECK(c.longestGapMs == 5.0);
    CHECK(c.leastWaitingMs == 10.0 && c.mostWaitingMs == 20.0);
    CHECK(monitor.report(10000.0).empty());     // 10 s passed, but nothing happened
    CHECK(contains(monitor.summary(), "2000 packets in 10 s; 0 late"));
}

static void testLateAndDry()
{
    Monitor monitor(15.0);
    monitor.packet(0, 0);           // the first: nothing queued yet is expected, not counted
    monitor.packet(5, 10);
    monitor.packet(10, 5);
    monitor.packet(40, 0);          // 30 ms after the last, nothing queued: late and dry
    monitor.packet(45, 5);
    monitor.packet(60, 0);          // exactly the device's buffer: not late, but dry
    monitor.thrownAway();
    monitor.waited();
    const Counters& c = monitor.total();
    CHECK(c.packets == 6);
    CHECK(c.late == 1 && c.longestGapMs == 30.0);
    CHECK(c.ranDry == 2);
    CHECK(c.thrownAway == 1 && c.waits == 1);
    CHECK(c.leastWaitingMs == 0 && c.mostWaitingMs == 10.0);
    CHECK(contains(monitor.summary(), "1 late (longest gap 30 ms), 2 arrived with nothing queued, 1 thrown away"));
}

static void testReports()
{
    // A line at most every 10 s, only for a window with something in it, counting that window alone
    Monitor monitor(15.0, 10000.0);
    monitor.packet(0, 10);
    monitor.packet(5, 10);
    CHECK(monitor.report(5).empty());           // too soon
    monitor.packet(100, 0);                      // late and dry
    CHECK(monitor.report(9999).empty());        // still too soon
    std::string first = monitor.report(10000);
    CHECK(contains(first, "3 packets in 10 s; 1 late (longest gap 95 ms), 1 arrived with nothing queued"));
    // The next window starts empty; packets every 5 ms through it say nothing
    for (double t = 105; t < 20000; t += 5) {
        monitor.packet(t, 10);
    }
    CHECK(monitor.report(20000).empty());
    monitor.thrownAway();
    std::string third = monitor.report(30000);
    CHECK(contains(third, "0 late") && contains(third, "1 thrown away"));
    // The whole stream keeps counting
    CHECK(monitor.total().late == 1 && monitor.total().thrownAway == 1);
    CHECK(contains(monitor.summary(), "longest gap 95 ms"));
}

static void testPauses()
{
    // The PC sending nothing for a while (silence) is a pause, not a late packet, and the packet
    // after it finding nothing queued is expected
    Monitor monitor(15.0);
    monitor.packet(0, 0);
    monitor.packet(5, 10);
    monitor.packet(3005, 0);
    monitor.packet(3010, 5);
    monitor.packet(3509, 5);        // just under the pause line: late
    const Counters& c = monitor.total();
    CHECK(c.pauses == 1);
    CHECK(c.late == 1 && c.longestGapMs == 499.0);
    CHECK(c.ranDry == 0);
    CHECK(contains(monitor.summary(), "1 pauses"));
}

int main()
{
    testSteady();
    testLateAndDry();
    testReports();
    testPauses();
    if (s_Failures) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("audiohealth: all checks passed\n");
    return 0;
}
