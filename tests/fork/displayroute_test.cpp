// Unit tests for app/fork/forkdisplayroute.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/displayroute_test.cpp app/fork/forkdisplayroute.cpp
#include "fork/forkdisplayroute.h"

#include <cstdio>
#include <string>

using namespace ForkDisplayRoute;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool contains(const std::string& text, const char* part)
{
    return text.find(part) != std::string::npos;
}

static Probe probe(const char* address, double median, double worst, int failures = 0)
{
    Probe p;
    p.address = address;
    p.count = 10;
    p.failures = failures;
    p.medianMs = median;
    p.maxMs = worst;
    return p;
}

// An iMac that can stream from the PC, a PC 3 ms away from it, and DisplayExtend measuring 21 ms
// (76 ms at its worst)
static Facts ready()
{
    Facts f;
    f.bridge = true;
    f.imacConnected = true;
    f.directSupported = true;
    f.moonlightVerified = true;
    f.paired = true;
    f.imacToPc = { probe("100.64.0.7", 30, 40), probe("10.0.0.77", 3, 9) };
    f.macToPc = probe("10.0.0.77", 2.2, 4.4);
    f.displayExtendP50Ms = 21;
    f.displayExtendP95Ms = 76;
    f.displayExtendFrames = 600;
    return f;
}

static void testDirectWins()
{
    Decision d = decide(Setting::Automatic, ready());
    CHECK(d.route == Route::Direct);
    CHECK(d.address == "10.0.0.77");
    // 1.5 + 1.7 + 12.5 against 1.1 + 2 + 12.5 + 21
    CHECK(d.estDirectMs > 15.6 && d.estDirectMs < 15.8);
    CHECK(d.estViaMs > 36.5 && d.estViaMs < 36.7);
    // At their worst: 4.5 + 1.7 + 12.5 against 2.2 + 2 + 12.5 + 76
    CHECK(d.estDirectWorstMs > 18.6 && d.estDirectWorstMs < 18.8);
    CHECK(d.estViaWorstMs > 92.6 && d.estViaWorstMs < 92.8);

    std::string text = describe(d, ready());
    CHECK(text == "straight from the PC (about 16 ms vs 37 ms, worst 19 ms vs 93 ms; iMac→PC 3 ms, worst 9 ms; "
                  "Mac→PC 2 ms, worst 4 ms; DisplayExtend 21 ms, worst 76 ms)");
}

static void testViaMacWhenFaster()
{
    // A far slower iMac link, and a DisplayExtend that is somehow nearly free: through the Mac wins,
    // even with direct's 5 ms head start
    Facts f = ready();
    f.imacToPc = { probe("10.0.0.77", 15, 20) };
    f.displayExtendP50Ms = 1;
    Decision d = decide(Setting::Automatic, f);
    CHECK(d.route == Route::ViaMac);
    CHECK(d.estDirectMs > d.estViaMs + k_DirectBiasMs);
    CHECK(contains(describe(d, f), "through this Mac (about"));

    // Within the head start, direct wins
    f.displayExtendP50Ms = 4;
    CHECK(decide(Setting::Automatic, f).route == Route::Direct);
}

static void testViaMacWhenSteadier()
{
    // Direct is faster typically but far worse at its worst than a DisplayExtend that never stalls
    Facts f = ready();
    f.imacToPc = { probe("10.0.0.77", 3, 58) };
    f.displayExtendP95Ms = 15;
    Decision d = decide(Setting::Automatic, f);
    CHECK(d.estDirectMs < d.estViaMs);
    CHECK(d.estDirectWorstMs > d.estViaWorstMs + k_DirectWorstBiasMs);
    CHECK(d.route == Route::ViaMac && d.reason == "steadier at its worst");
    CHECK(contains(describe(d, f), "; steadier at its worst)"));

    // A DisplayExtend that stalls as usual: direct holds up better too
    f.displayExtendP95Ms = 76;
    CHECK(decide(Setting::Automatic, f).route == Route::Direct);
}

static void testIneligible()
{
    Facts f = ready();
    f.bridge = false;
    Decision d = decide(Setting::Automatic, f);
    CHECK(d.route == Route::ViaMac && d.estDirectMs < 0);
    CHECK(contains(d.reason, "Host isn't running"));
    CHECK(describe(d, f) == "through this Mac (" + d.reason + ")");

    f = ready();
    f.directSupported = false;
    CHECK(contains(decide(Setting::Automatic, f).reason, "update it from DisplayExtend's Host"));

    f = ready();
    f.moonlightVerified = false;
    CHECK(contains(decide(Setting::Automatic, f).reason, "Moonlight on the iMac"));

    f = ready();
    f.paired = false;
    CHECK(contains(decide(Setting::Automatic, f).reason, "isn't paired"));

    f = ready();
    f.imacConnected = false;
    CHECK(contains(decide(Setting::Automatic, f).reason, "isn't connected"));

    // Unreachable, dropping connects, too slow
    f = ready();
    f.imacToPc = { probe("10.0.0.77", -1, -1, 10) };
    CHECK(decide(Setting::Automatic, f).reason == "the iMac can't reach the PC");
    f.imacToPc = { probe("10.0.0.77", 3, 9, 1) };
    CHECK(decide(Setting::Automatic, f).reason == "1 of 10 connects from the iMac to the PC failed");

    // ... still estimating the way through this Mac, which was timed, for the launch screen
    d = decide(Setting::Automatic, f);
    CHECK(d.estDirectMs < 0 && d.estViaMs > 36.5 && d.estViaMs < 36.7);
    CHECK(d.estViaWorstMs > 92.6 && d.estViaWorstMs < 92.8);
    Facts untimed = f;
    untimed.macToPc = Probe();
    CHECK(decide(Setting::Automatic, untimed).estViaMs < 0);
    f.imacToPc = { probe("10.0.0.77", 20, 30) };
    CHECK(contains(decide(Setting::Automatic, f).reason, "too slow (20 ms, worst 30 ms)"));
    f.imacToPc = { probe("10.0.0.77", 5, 61) };
    CHECK(decide(Setting::Automatic, f).route == Route::ViaMac);
    f.imacToPc.clear();
    CHECK(decide(Setting::Automatic, f).reason == "the iMac can't reach the PC");
}

static void testSettings()
{
    // Through this Mac whatever the facts
    Decision d = decide(Setting::ViaMac, ready());
    CHECK(d.route == Route::ViaMac && d.reason == "set to go through this Mac");

    // Straight from the PC even when slower, but only when it can
    Facts f = ready();
    f.imacToPc = { probe("10.0.0.77", 15, 20) };
    f.displayExtendP50Ms = 1;
    d = decide(Setting::Direct, f);
    CHECK(d.route == Route::Direct && d.reason == "set to go straight from the PC");
    CHECK(contains(describe(d, f), "; set to go straight from the PC)"));

    f.paired = false;
    d = decide(Setting::Direct, f);
    CHECK(d.route == Route::ViaMac);
    CHECK(d.reason.rfind("can't go straight from the PC: ", 0) == 0);
}

static void testDefaults()
{
    // Too few frames measured: DisplayExtend's measured p50 from its results stands in
    Facts f = ready();
    f.displayExtendFrames = 10;
    f.displayExtendP50Ms = 90;
    Decision d = decide(Setting::Automatic, f);
    CHECK(d.estViaMs > 36.2 && d.estViaMs < 36.4);
    CHECK(contains(describe(d, f), "DisplayExtend 21 ms assumed"));

    // Without the Mac's own probe its leg counts as nothing
    f = ready();
    f.macToPc = Probe();
    d = decide(Setting::Automatic, f);
    CHECK(d.estViaMs > 35.4 && d.estViaMs < 35.6);
    CHECK(!contains(describe(d, f), "; Mac→PC"));

    // A slower refresh waits longer
    f = ready();
    f.imacRefreshHz = 30;
    CHECK(decide(Setting::Automatic, f).estDirectMs > 28);
}

static void testCombine()
{
    // Rounds of three connects: one fast, one slower with a failure, one that reached nothing
    Probe a = probe("10.0.0.77", 3, 9);
    a.count = 3;
    Probe b = probe("10.0.0.77", 4, 12, 1);
    b.count = 3;
    Probe c = probe("10.0.0.77", -1, -1, 3);
    c.count = 3;
    Probe all = combine({ a, b, c });
    CHECK(all.address == "10.0.0.77");
    CHECK(all.count == 9 && all.failures == 4);
    CHECK(all.medianMs == 3.5 && all.maxMs == 12);

    // Nothing reached in any round
    all = combine({ c, c });
    CHECK(all.count == 6 && all.failures == 6 && all.medianMs == -1 && all.maxMs == -1);
    CHECK(combine({}).count == 0);
}

static void testMedian()
{
    CHECK(median({}) == -1);
    CHECK(median({ 5 }) == 5);
    CHECK(median({ 9, 1, 5 }) == 5);
    CHECK(median({ 4, 1, 3, 2 }) == 2.5);
}

int main()
{
    testDirectWins();
    testViaMacWhenFaster();
    testViaMacWhenSteadier();
    testIneligible();
    testSettings();
    testDefaults();
    testCombine();
    testMedian();

    if (s_Failures > 0) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("All display route tests passed\n");
    return 0;
}
