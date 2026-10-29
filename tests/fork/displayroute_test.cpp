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

// After the first round only the addresses a connect reached are timed again
static void testAnswering()
{
    std::vector<Probe> first = { probe("73.100.235.17", 13, 20), probe("10.0.0.77", -1, -1, 10),
                                 probe("2601::190f", 40, 60, 3) };
    std::vector<size_t> kept = answering(first);
    CHECK(kept.size() == 2);
    CHECK(kept.size() == 2 && kept[0] == 0 && kept[1] == 2);   // one connect of three getting through is enough
    CHECK(answering({ probe("10.0.0.77", -1, -1, 10) }).empty());
    CHECK(answering({}).empty());
}

// A Resume decides on the launch's connect times with the iMac's state as it is now
static void testDecideOnRecalledFacts()
{
    Facts now = ready();
    CHECK(decide(Setting::Automatic, now).route == Route::Direct);
    now.imacConnected = false;   // the iMac left DisplayExtend since the launch
    Decision d = decide(Setting::Automatic, now);
    CHECK(d.route == Route::ViaMac);
}

// DisplayExtend 1.6.5 on an iMac that decodes H.264 only in hardware
static ImacCodecs codecs165()
{
    ImacCodecs imac;
    imac.direct = { Codec::H264, Codec::Hevc, Codec::Av1 };
    imac.hardware = { Codec::H264 };
    return imac;
}

// Automatic: straight from the PC, a codec the iMac decodes in hardware, at twice a slot bitrate
// sized for HEVC; through this Mac, slot 0's codec at the slot's bitrate
static void testImacStreamAutomatic()
{
    const int slotKbps = 14694;   // a 1080p60 iMac beside a 3024x1890 120 Hz stream at 81 Mb/s
    ImacStream s = imacStream(Route::Direct, CodecSetting::Automatic, 0, slotKbps, k_VccAutomatic, codecs165());
    CHECK(s.codec == Codec::H264 && !s.sameAsMain && s.kbps == 29388 && s.automaticKbps && s.note.empty());
    CHECK(describe(s) == "H.264 at 29388 kbps (automatic)");

    s = imacStream(Route::Direct, CodecSetting::Automatic, 0, slotKbps, k_VccAutomatic, ImacCodecs());
    CHECK(s.codec == Codec::H264 && s.kbps == 29388);   // DisplayExtend before 1.6.5

    s = imacStream(Route::Direct, CodecSetting::Automatic, 0, slotKbps, k_VccH264, codecs165());
    CHECK(s.codec == Codec::H264 && s.kbps == slotKbps);   // slot 0 is H.264 too: already sized for it

    ImacCodecs hevcHardware = codecs165();
    hevcHardware.hardware = { Codec::H264, Codec::Hevc };
    s = imacStream(Route::Direct, CodecSetting::Automatic, 0, slotKbps, k_VccAutomatic, hevcHardware);
    CHECK(s.codec == Codec::Hevc && s.kbps == slotKbps);

    s = imacStream(Route::Direct, CodecSetting::Automatic, 0, 30000, k_VccHevc, codecs165());
    CHECK(s.kbps == k_DirectMaxBitrateKbps);

    s = imacStream(Route::ViaMac, CodecSetting::Automatic, 0, slotKbps, k_VccAutomatic, codecs165());
    CHECK(s.sameAsMain && s.codec == Codec::Hevc && s.kbps == slotKbps);
    CHECK(describe(s) == "slot 0's codec at 14694 kbps (automatic)");
    s = imacStream(Route::ViaMac, CodecSetting::Automatic, 0, 60000, k_VccAutomatic, codecs165());
    CHECK(s.kbps == 60000);   // the direct cap is for the iMac's decoder only
}

// A codec or bitrate set by hand is used on either route, except a codec the iMac's DisplayExtend
// can't be asked for straight from the PC
static void testImacStreamSet()
{
    ImacStream s = imacStream(Route::Direct, CodecSetting::Hevc, 20000, 14694, k_VccAutomatic, codecs165());
    CHECK(s.codec == Codec::Hevc && s.kbps == 20000 && !s.automaticKbps && s.note.empty());
    CHECK(describe(s) == "HEVC at 20000 kbps (set in Settings)");

    s = imacStream(Route::Direct, CodecSetting::Hevc, 0, 14694, k_VccAutomatic, codecs165());
    CHECK(s.codec == Codec::Hevc && s.kbps == 14694);   // HEVC needs no more than slot 0's HEVC

    s = imacStream(Route::Direct, CodecSetting::Av1, 0, 14694, k_VccAutomatic, ImacCodecs());
    CHECK(s.codec == Codec::H264 && s.kbps == 29388 && !s.note.empty());
    CHECK(describe(s) == "H.264 at 29388 kbps (automatic; AV1 is set, but the iMac's DisplayExtend streams H.264 only before 1.6.5)");

    s = imacStream(Route::ViaMac, CodecSetting::Av1, 0, 14694, k_VccAutomatic, ImacCodecs());
    CHECK(s.codec == Codec::Av1 && !s.sameAsMain && s.note.empty());   // the Mac's helper takes any codec

    s = imacStream(Route::ViaMac, CodecSetting::H264, 0, 14694, k_VccAutomatic, ImacCodecs());
    CHECK(s.codec == Codec::H264 && s.kbps == 29388);
    s = imacStream(Route::ViaMac, CodecSetting::Hevc, 0, 14694, k_VccH264, ImacCodecs());
    CHECK(s.kbps == 7347);   // HEVC beside an H.264 slot 0: half

    CHECK(imacStream(Route::Direct, CodecSetting::H264, 500, 14694, k_VccAutomatic, codecs165()).kbps == k_ImacMinBitrateKbps);
    CHECK(imacStream(Route::Direct, CodecSetting::H264, 900000, 14694, k_VccAutomatic, codecs165()).kbps == k_ImacMaxBitrateKbps);
    CHECK(imacStream(Route::ViaMac, CodecSetting::Hevc, 0, 2000, k_VccH264, codecs165()).kbps == k_ImacMinBitrateKbps);
}

static void testCodecNames()
{
    Codec c = Codec::H264;
    CHECK(parseCodec("HEVC", &c) && c == Codec::Hevc);
    CHECK(parseCodec("AV1", &c) && c == Codec::Av1);
    CHECK(parseCodec("H.264", &c) && c == Codec::H264);
    CHECK(!parseCodec("h264", &c) && c == Codec::H264);
    CHECK(codecConfig(Codec::H264) == k_VccH264 && codecConfig(Codec::Hevc) == k_VccHevc && codecConfig(Codec::Av1) == k_VccAv1);
}

int main()
{
    testDirectWins();
    testAnswering();
    testDecideOnRecalledFacts();
    testImacStreamAutomatic();
    testImacStreamSet();
    testCodecNames();
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
