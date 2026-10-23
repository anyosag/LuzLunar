// Unit tests for app/fork/notchquality.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/notchquality_test.cpp
#include "fork/notchquality.h"

#include <cstdio>

using namespace NotchQuality;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

// The canvas's: the user's 20 Mb/s, launched at 25, adapting and held to 18
static State canvas()
{
    State state;
    state.known = true;
    state.adapting = true;
    state.ownKbps = 20000;
    state.targetKbps = 18000;
    state.minKbps = 1000;
    state.maxKbps = 25000;
    state.changeReason = BitrateRules::Reason::RoundTrip;
    state.changeAgoSeconds = 61;
    state.changeRttMs = 48;
    state.changeBaseRttMs = 8;
    return state;
}

static void testShown()
{
    State state = canvas();
    CHECK(shownKbps(state) == 18000 && lowered(state));
    state.targetKbps = 0;
    CHECK(shownKbps(state) == 20000 && !lowered(state));
    state.targetKbps = 23000;           // raised by hand, above the user's
    CHECK(!lowered(state));

    CHECK(mbps(18000) == "18");
    CHECK(mbps(18500) == "18.5");
    CHECK(mbps(14999) == "15");
    CHECK(mbps(2340) == "2.3");

    CHECK(percent(4.0) == "4");
    CHECK(percent(2.46) == "2.5");
    CHECK(percent(0.04) == "0");
    CHECK(percent(12.6) == "13");
}

static void testLines()
{
    State state = canvas();
    CHECK(line(state) == Line::LoweredRoundTrip);
    CHECK(caption(state) == Caption::Adapting);
    state.changeReason = BitrateRules::Reason::Loss;
    CHECK(line(state) == Line::LoweredLoss);
    state.changePoor = true;            // called poor, with few frames lost
    state.changeDropPercent = 0.4;
    CHECK(line(state) == Line::LoweredPoor);
    state.changeDropPercent = 3;        // poor, and lost enough to cut anyway
    CHECK(line(state) == Line::LoweredLoss);
    state.changeReason = BitrateRules::Reason::Climb;
    CHECK(line(state) == Line::Climbing);
    state.changeReason = BitrateRules::Reason::None;    // turned on below, not climbed yet
    CHECK(line(state) == Line::Climbing);
    state.targetKbps = 20000;           // back at the user's
    CHECK(line(state) == Line::None);

    state.adapting = false;
    CHECK(line(state) == Line::Holding);
    CHECK(caption(state) == Caption::ByHand);

    state.live = false;
    state.why = Why::Encoder;
    CHECK(line(state) == Line::EncoderCant);
    CHECK(caption(state) == Caption::CantChange);
    state.why = Why::Apollo;
    CHECK(line(state) == Line::ApolloCant);
    state.why = Why::NotApollo;
    CHECK(line(state) == Line::PcCant);
}

static void testAgo()
{
    CHECK(ago(3).unit == Ago::JustNow);
    CHECK(ago(45).unit == Ago::Seconds && ago(45).value == 40);
    CHECK(ago(61).unit == Ago::Minutes && ago(61).value == 1);
    CHECK(ago(185).value == 3);
}

static void testSlider()
{
    State state = canvas();
    CHECK(!sliderEnabled(state) && switchEnabled(state));
    state.adapting = false;
    CHECK(sliderEnabled(state));
    state.live = false;
    CHECK(!sliderEnabled(state) && !switchEnabled(state));

    // 3 to 25 Mb/s on the canvas
    Range r = range(canvas());
    CHECK(r.minKbps == 3000 && r.maxKbps == 25000 && r.stepKbps == 500);
    CHECK(snap(18240, r) == 18000);
    CHECK(snap(18300, r) == 18500);
    CHECK(snap(100, r) == 3000);
    CHECK(snap(40000, r) == 25000);

    // A launch kept under an audio line: its top is a stop of its own
    State small = canvas();
    small.ownKbps = 12000;
    small.maxKbps = 14999;
    r = range(small);
    CHECK(r.maxKbps == 14999);
    CHECK(snap(14800, r) == 14999);
    CHECK(snap(14600, r) == 14500);

    // Before the PC says, the user's bitrate is the top; a tiny bitrate is the bottom too
    State unknown;
    unknown.ownKbps = 2000;
    r = range(unknown);
    CHECK(r.minKbps == 2000 && r.maxKbps == 2000);
    State noMax = canvas();
    noMax.maxKbps = 0;
    noMax.minKbps = 0;
    CHECK(range(noMax).maxKbps == 20000 && range(noMax).minKbps == 3000);
}

static void testSaver()
{
    // The canvas's: the saver holds the stream at 10 of the user's 20
    State state = canvas();
    state.saver = true;
    state.targetKbps = 10000;
    CHECK(saverCaps(state) && saverNote(state) == SaverNote::Caps);
    CHECK(lowered(state));
    CHECK(line(state) == Line::None);           // the note says why
    state.targetKbps = 7000;                    // lowered further by adaptive bitrate
    CHECK(line(state) == Line::LoweredRoundTrip);

    // The slider's top is the cap
    state.adapting = false;
    CHECK(range(state).maxKbps == 10000);
    CHECK(caption(state) == Caption::ByHand);

    // A PC that can't change it live: nothing capped, and the note says a reconnect would
    state.live = false;
    state.why = Why::Encoder;
    CHECK(!saverCaps(state) && saverNote(state) == SaverNote::NeedsReconnect);
    CHECK(range(state).maxKbps == 25000);

    State off = canvas();
    CHECK(saverNote(off) == SaverNote::None && range(off).maxKbps == 25000);

    // Climbing back under the cap goes to the cap
    State climbing = canvas();
    climbing.saver = true;
    climbing.targetKbps = 8000;
    climbing.changeReason = BitrateRules::Reason::Climb;
    CHECK(line(climbing) == Line::Climbing && climbKbps(climbing) == 10000);
    CHECK(climbKbps(canvas()) == 20000);

    // A user's bitrate at the cap or below: nothing to cap, nothing to say
    State small = canvas();
    small.saver = true;
    small.ownKbps = 8000;
    small.targetKbps = 8000;
    small.maxKbps = 10000;
    CHECK(!saverCaps(small) && saverNote(small) == SaverNote::None && range(small).maxKbps == 10000);
}

int main()
{
    testShown();
    testLines();
    testAgo();
    testSlider();
    testSaver();

    if (s_Failures == 0) {
        std::printf("notchquality: all tests passed\n");
        return 0;
    }
    std::printf("notchquality: %d failure(s)\n", s_Failures);
    return 1;
}
