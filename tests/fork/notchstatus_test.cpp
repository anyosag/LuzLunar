// Unit tests for app/fork/notchstatus.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/notchstatus_test.cpp
#include "fork/notchstatus.h"

#include <cmath>
#include <cstdio>

using namespace NotchStatus;
using StreamHistory::Parts;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool near(double a, double b, double tolerance = 0.05)
{
    return std::fabs(a - b) <= tolerance;
}

static Parts parts(double pc, double network, double decode, double display)
{
    return Parts { pc, network, decode, display };
}

static Sample sample(double seconds, double totalMs, double dropPercent = 0)
{
    Sample s;
    s.seconds = seconds;
    s.parts = parts(totalMs, StreamHistory::unknown(), StreamHistory::unknown(), StreamHistory::unknown());
    s.dropPercent = dropPercent;
    return s;
}

static void testScale()
{
    // The canvas's example peaked at 60.16 ms
    Scale scale = scaleFor(60.16);
    CHECK(scale.topMs == 64);
    CHECK(scale.stepMs == 25);
    CHECK(near(heightFor(32, scale), 31.5));
    CHECK(near(heightFor(500, scale), k_PlotHeight));

    scale = scaleFor(StreamHistory::unknown());
    CHECK(scale.topMs == 63 && scale.stepMs == 25);
    scale = scaleFor(20);
    CHECK(scale.topMs == 63 && scale.stepMs == 25);
    scale = scaleFor(190);
    CHECK(scale.topMs == 200 && scale.stepMs == 50);
    scale = scaleFor(1000);
    CHECK(scale.topMs == 1050 && scale.stepMs == 250);
}

static void testSummary()
{
    std::vector<Sample> samples { sample(1, 20), sample(2, 18), sample(3, 60), sample(4, 22), sample(5, 60) };
    Summary summary = summarize(samples);
    CHECK(summary.any);
    CHECK(near(summary.usualMs, 22));       // the upper median of 18 20 22 60 60
    CHECK(near(summary.peakMs, 60));
    CHECK(summary.peakIndex == 2);          // the first of the highest

    // Samples without any part known don't count
    Sample empty;
    empty.seconds = 6;
    samples.push_back(empty);
    CHECK(summarize(samples).peakIndex == 2);
    CHECK(!summarize({ empty }).any);
    CHECK(!summarize({}).any);

    samples[3].lowered = true;
    CHECK(loweredNear(samples, 2));
    CHECK(!loweredNear(samples, 0, 1.5));
    CHECK(!loweredNear(samples, 99));
}

static void testSegments()
{
    // The canvas's latency bar: 270 points, three 2-point gaps
    auto widths = segmentWidths(parts(4.2, 8.0, 2.2, 5.4));
    CHECK(near(widths[0], 56.0));
    CHECK(near(widths[1], 106.7));
    CHECK(near(widths[2], 29.3));
    CHECK(near(widths[3], 72.0));

    // An unknown part takes no room, nor a gap
    widths = segmentWidths(parts(4.0, StreamHistory::unknown(), 2.0, 4.0));
    CHECK(widths[1] == 0);
    CHECK(near(widths[0] + widths[2] + widths[3], 270 - 2 * k_SegmentGap));

    widths = segmentWidths(StreamHistory::unknownParts());
    CHECK(widths[0] == 0 && widths[3] == 0);
}

static void testPointer()
{
    CHECK(near(xForAge(0), 270));
    CHECK(near(xForAge(120), 0));
    CHECK(near(xForAge(60), 135));
    CHECK(near(ageForX(270), 0));
    CHECK(near(ageForX(0), 120));
    CHECK(near(ageForX(-5), 120));

    // Samples a second apart, then a gap
    std::vector<Sample> samples { sample(100, 20), sample(101, 21), sample(102, 22), sample(110, 30) };
    double now = 110.5;
    CHECK(nearest(samples, now, 0) == 3);
    CHECK(nearest(samples, now, 9.5) == 1);
    CHECK(nearest(samples, now, 9.9) == 1);
    CHECK(nearest(samples, now, 5) == -1);     // frames had stopped
    CHECK(nearest({}, now, 0) == -1);

    CHECK(secondsAgo(0.4) == 0);
    CHECK(secondsAgo(62.2) == 62);
    CHECK(secondsAgo(-1) == 0);

    // The canvas: at the peak, 62 s ago (x 135.6), the tooltip goes right of the cursor
    CHECK(near(tooltipX(129.3), 137.3));
    CHECK(near(tooltipX(200), 118));
    CHECK(near(tooltipX(2), 10));
    CHECK(near(tooltipX(268), 186));
    // Kept inside a narrow graph
    CHECK(near(tooltipX(30, 100), 26));
    CHECK(near(tooltipX(60, 100), 0));
}

static void testHealth()
{
    CHECK(health(false, false, {}, 10) == Health::Waiting);
    CHECK(health(false, true, {}, 10) == Health::Waiting);
    // No frames for over two minutes on a still desktop is still video
    CHECK(health(true, false, {}, 500) == Health::Smooth);

    std::vector<Sample> samples { sample(1, 20, 5), sample(8, 20), sample(9, 20, 1.9) };
    CHECK(health(true, false, samples, 9.5) == Health::Smooth);   // the loss was 8.5 s ago
    CHECK(health(true, true, samples, 9.5) == Health::Poor);
    samples.push_back(sample(10, 20, k_PoorLossPercent));
    CHECK(health(true, false, samples, 10.2) == Health::Poor);
}

static void testBarText()
{
    CHECK(barText("5 GHz", 119.6, 8) == "5 GHz · 120 fps · 8 ms");
    CHECK(barText("", 60, 12) == "60 fps · 12 ms");
    CHECK(barText("", 60, 0) == "60 fps · — ms");
}

int main()
{
    testScale();
    testSummary();
    testSegments();
    testPointer();
    testHealth();
    testBarText();

    if (s_Failures == 0) {
        std::printf("notchstatus: all tests passed\n");
        return 0;
    }
    std::printf("notchstatus: %d failure(s)\n", s_Failures);
    return 1;
}
