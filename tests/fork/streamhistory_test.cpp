// Unit tests for app/fork/streamhistory.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/streamhistory_test.cpp
#include "fork/streamhistory.h"

#include <cmath>
#include <cstdio>

using namespace StreamHistory;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool near(double a, double b, double tolerance = 1e-9)
{
    return std::fabs(a - b) <= tolerance;
}

static void testLatency()
{
    // A window with nothing in it knows nothing
    Parts parts = latency(Totals());
    for (double part : parts) {
        CHECK(!known(part));
    }
    CHECK(!known(total(parts)));

    // The canvas's example: 4.2 + 8 + 2.2 + 5.4 ms over 120 frames
    Totals totals;
    totals.totalHostProcessingLatency = 42 * 120;      // 0.1 ms units
    totals.framesWithHostProcessingLatency = 120;
    totals.lastRttMs = 8;
    totals.totalDecodeTimeUs = 2200 * 118;
    totals.decodedFrames = 118;
    totals.totalPacerTimeUs = 3000 * 117;
    totals.totalRenderTimeUs = 2400 * 117;
    totals.renderedFrames = 117;
    parts = latency(totals);
    CHECK(near(parts[PcCaptureAndEncode], 4.2));
    CHECK(near(parts[NetworkRoundTrip], 8));
    CHECK(near(parts[MacDecode], 2.2));
    CHECK(near(parts[Display], 5.4));
    CHECK(near(total(parts), 19.8));

    // An RTT of 0 wasn't measured; the rest still adds up
    totals.lastRttMs = 0;
    parts = latency(totals);
    CHECK(!known(parts[NetworkRoundTrip]));
    CHECK(near(total(parts), 11.8));

    // Frames decoded but none shown yet
    totals.renderedFrames = 0;
    CHECK(!known(latency(totals)[Display]));
}

static Sample at(double seconds, double targetMbps = 0)
{
    Sample sample;
    sample.seconds = seconds;
    sample.targetMbps = targetMbps;
    return sample;
}

static void testWindow()
{
    History history;
    CHECK(history.empty());
    for (int i = 0; i < 200; i++) {
        history.add(at(1000 + i));
    }
    CHECK(!history.empty());
    CHECK(near(history.latest().seconds, 1199));

    // Two minutes back from now, oldest first
    std::vector<Sample> window = history.window(1199);
    CHECK(window.size() == 121);
    CHECK(near(window.front().seconds, 1079));
    CHECK(near(window.back().seconds, 1199));
    CHECK(history.window(1500).empty());

    // The ring keeps no more than it can show
    CHECK(history.window(1199, 1000).size() == History::Capacity);

    history.reset();
    CHECK(history.empty());
}

static void testRuns()
{
    // Samples a frame past each second, then frames stop for 5 seconds
    std::vector<Sample> samples { at(0), at(1.02), at(2.04), at(3.06), at(8.1), at(9.12) };
    std::vector<std::size_t> starts = runStarts(samples);
    CHECK(starts.size() == 2);
    CHECK(starts[0] == 0);
    CHECK(starts[1] == 4);

    CHECK(runStarts({}).empty());
    CHECK(runStarts({ at(5) }).size() == 1);
    // Just under the gap is still one line
    CHECK(runStarts({ at(0), at(2.4) }).size() == 1);
}

static void testLowered()
{
    History history;
    history.add(at(1));             // the PC's bitrate not known yet
    CHECK(!history.latest().lowered);
    history.add(at(2, 50));         // the stream's own
    CHECK(!history.latest().lowered);
    history.add(at(3, 40));         // adaptive bitrate lowered it
    CHECK(history.latest().lowered);
    history.add(at(4, 40));         // still there
    CHECK(!history.latest().lowered);
    history.add(at(5, 30));         // lower again
    CHECK(history.latest().lowered);
    history.add(at(6, 35));         // climbing back
    CHECK(!history.latest().lowered);
    history.add(at(7, 0));          // unknown for a moment: no change
    CHECK(!history.latest().lowered);
    history.add(at(8, 20));         // lowered by hand, against the last known
    CHECK(history.latest().lowered);

    // A new stream doesn't remember the last one's bitrate
    history.reset();
    history.add(at(1, 20));
    CHECK(!history.latest().lowered);
}

int main()
{
    testLatency();
    testWindow();
    testRuns();
    testLowered();

    if (s_Failures == 0) {
        std::printf("streamhistory: all tests passed\n");
        return 0;
    }
    std::printf("streamhistory: %d failure(s)\n", s_Failures);
    return 1;
}
