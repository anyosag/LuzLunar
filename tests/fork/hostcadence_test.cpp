// Unit tests for app/fork/hostcadence.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/hostcadence_test.cpp
#include "fork/hostcadence.h"

#include <cmath>
#include <cstdio>

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool near(double a, double b, double tolerance)
{
    return std::fabs(a - b) <= tolerance;
}

// 90 kHz ticks per frame at 60 fps
static const uint32_t k_Frame60 = 1500;

static void testScore()
{
    // 100 / (1 + (σ / 6 ms)^4), with σ in ticks²
    CHECK(near(HostCadence::smoothnessPercent(0), 100.0, 1e-9));
    CHECK(near(HostCadence::smoothnessPercent(90.0 * 90.0), 100.0 / (1.0 + std::pow(1.0 / 6, 4)), 1e-9));   // 1 ms
    CHECK(near(HostCadence::smoothnessPercent(270.0 * 270.0), 100.0 / (1.0 + std::pow(3.0 / 6, 4)), 1e-9)); // 3 ms, about 94 %
    CHECK(near(HostCadence::smoothnessPercent(540.0 * 540.0), 50.0, 1e-9));                                  // 6 ms
    CHECK(near(HostCadence::deviationMs(270.0 * 270.0), 3.0, 1e-9));
    CHECK(HostCadence::deviationMs(0) == 0.0);
}

static void testSteady()
{
    HostCadence cadence;
    uint32_t time = 1000;
    HostCadence::Sample sample;
    // The first frame and the next 29 intervals don't fill the window
    for (uint32_t frame = 1; frame <= 30; frame++, time += k_Frame60) {
        sample = cadence.observe(frame, time);
        CHECK(!sample.valid);
    }
    sample = cadence.observe(31, time);
    CHECK(sample.valid);
    CHECK(sample.varianceTicksSquared == 0.0);
    CHECK(near(HostCadence::smoothnessPercent(sample.varianceTicksSquared), 100.0, 1e-9));
}

static void testUneven()
{
    // Alternating 12 and 21 ms (a 60 fps game paced against a different clock): σ 4.5 ms
    HostCadence cadence;
    uint32_t time = 0;
    HostCadence::Sample sample;
    cadence.observe(1, time);
    for (uint32_t frame = 2; frame <= 31; frame++) {
        time += (frame % 2 == 0) ? 1080 : 1890;
        sample = cadence.observe(frame, time);
    }
    CHECK(sample.valid);
    CHECK(near(HostCadence::deviationMs(sample.varianceTicksSquared), 4.5, 1e-9));
    double percent = HostCadence::smoothnessPercent(sample.varianceTicksSquared);
    CHECK(percent > 70 && percent < 80);
}

static void testBreaks()
{
    HostCadence cadence;
    uint32_t time = 0;
    for (uint32_t frame = 1; frame <= 31; frame++, time += k_Frame60) {
        cadence.observe(frame, time);
    }

    // A lost frame starts the window again
    CHECK(!cadence.observe(33, time + k_Frame60).valid);
    // So do a repeated and a backward timestamp
    CHECK(!cadence.observe(34, time + k_Frame60).valid);
    CHECK(!cadence.observe(35, time).valid);

    // RTP time wraps without breaking it
    HostCadence wrapping;
    time = 0xFFFFFFFFu - 10 * k_Frame60;
    HostCadence::Sample sample;
    for (uint32_t frame = 1; frame <= 31; frame++, time += k_Frame60) {
        sample = wrapping.observe(frame, time);
    }
    CHECK(sample.valid);
    CHECK(sample.varianceTicksSquared == 0.0);

    // So does the frame number
    HostCadence numbers;
    time = 0;
    uint32_t frame = 0xFFFFFFF0u;
    for (int i = 0; i < 31; i++, frame++, time += k_Frame60) {
        sample = numbers.observe(frame, time);
    }
    CHECK(sample.valid);
}

static void testSummary()
{
    HostCadenceSummary summary;
    CHECK(summary.empty());
    CHECK(summary.average() == 0.0);
    summary.add(100);
    summary.add(80);
    summary.add(90);
    CHECK(!summary.empty());
    CHECK(summary.count() == 3);
    CHECK(near(summary.average(), 90.0, 1e-9));
    CHECK(summary.lowest() == 80.0);
}

static void testVerdict()
{
    // At 60 fps one frame the PC held, in a window of 30, scores about 94 %: uneven
    HostCadence cadence;
    uint32_t time = 0;
    HostCadence::Sample sample;
    for (uint32_t frame = 1; frame <= 31; frame++) {
        time += frame == 20 ? 2 * k_Frame60 : k_Frame60;
        sample = cadence.observe(frame, time);
    }
    CHECK(sample.valid);
    double held = HostCadence::smoothnessPercent(sample.varianceTicksSquared);
    CHECK(near(held, 94.2, 0.1));
    CHECK(pacingVerdict(held, 60) == PacingVerdict::Uneven);

    CHECK(pacingVerdict(100, 60) == PacingVerdict::Even);
    CHECK(pacingVerdict(k_EvenPacingPercent, 120) == PacingVerdict::Even);
    CHECK(pacingVerdict(96.9, 120) == PacingVerdict::Uneven);
    // No score, or a PC that's mostly idle: no verdict
    CHECK(pacingVerdict(std::nan(""), 60) == PacingVerdict::Unknown);
    CHECK(pacingVerdict(50, 9.5) == PacingVerdict::Unknown);
}

int main()
{
    testScore();
    testSteady();
    testUneven();
    testBreaks();
    testSummary();
    testVerdict();

    if (s_Failures == 0) {
        std::printf("hostcadence: all tests passed\n");
        return 0;
    }
    std::printf("hostcadence: %d failure(s)\n", s_Failures);
    return 1;
}
