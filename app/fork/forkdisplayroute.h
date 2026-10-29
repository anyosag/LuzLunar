#pragma once

#include <string>
#include <vector>

// Where the iMac's picture comes from in a multi-display stream (forkdisplaygroup.*), when one of the
// Mac's displays is DisplayExtend's: straight from the PC (Moonlight on the iMac streams that display
// from Apollo; DisplayExtend's client runs it) or through this Mac (a LuzLunar helper shows it on the
// virtual display, which DisplayExtend captures and streams to the iMac as usual). Chosen once per
// launch, on the launch screen before the stream connects, from what DisplayExtend's Host reports
// and a few seconds of probes: typical times and worst cases both count. A Resume reuses the
// launch's probes (forkroutememory.h).
//
// Kept free of Qt so it can be unit tested on its own (tests/fork/displayroute_test.cpp).
namespace ForkDisplayRoute
{
    // The "iMac picture" setting (ForkPreferences::imacRoute)
    enum class Setting { Automatic = 0, Direct = 1, ViaMac = 2 };

    enum class Route { Direct, ViaMac };

    // The codecs of the iMac's display's stream from the PC
    enum class Codec { H264, Hevc, Av1 };

    // "H.264", "HEVC", "AV1": Moonlight's names, which DisplayExtend's bridge takes and reports
    const char* codecName(Codec codec);
    bool parseCodec(const std::string& name, Codec* codec);

    // The "iMac codec" setting (ForkPreferences::ImacCodec)
    enum class CodecSetting { Automatic = 0, H264 = 1, Hevc = 2, Av1 = 3 };

    // What the iMac's DisplayExtend reports on its bridge status. Before 1.6.5 a direct run streams
    // H.264 only, and nothing says what the iMac decodes in hardware (its iMac16,2 does H.264).
    struct ImacCodecs {
        std::vector<Codec> direct = { Codec::H264 };     // what a direct run can be asked for
        std::vector<Codec> hardware = { Codec::H264 };   // what the iMac decodes in hardware
    };

    // TCP connects to the PC's HTTPS port from one machine to one of the PC's addresses
    struct Probe {
        std::string address;
        int count = 0;               // connects tried
        int failures = 0;
        double medianMs = -1, maxMs = -1;   // over the ones that connected; -1 without any
    };

    struct Facts {
        bool bridge = false;              // DisplayExtend's Host answered on its socket
        bool imacConnected = false;       // the iMac is streaming DisplayExtend's display
        bool directSupported = false;     // the iMac's client can run Moonlight on the Host's say
        bool moonlightVerified = false;   // its bundled Moonlight passed the signature check
        bool paired = false;              // that Moonlight is paired with this PC
        std::vector<Probe> imacToPc;      // one per PC address
        Probe macToPc;
        double displayExtendP50Ms = 0;    // DisplayExtend's live delay, capture to the iMac's refresh
        double displayExtendP95Ms = 0;    // and its worst 5%
        int displayExtendFrames = 0;      // frames that went into it
        int imacRefreshHz = 60;
        int virtualRefreshHz = 60;        // the Mac's DisplayExtend display
        ImacCodecs imacCodecs;
    };

    struct Decision {
        Route route = Route::ViaMac;
        std::string address;              // the PC address the iMac streams from, for Direct
        double estDirectMs = -1, estViaMs = -1;   // typical; -1 when not estimated
        double estDirectWorstMs = -1, estViaWorstMs = -1;   // at their worst
        std::string reason;               // why, for the log and Settings
    };

    // The thresholds an iMac to PC probe must meet for the direct route: every connect succeeds,
    // with a median and a worst case at most this long
    constexpr double k_DirectMaxMedianMs = 15;
    constexpr double k_DirectMaxWorstMs = 60;

    // Direct wins ties up to this much, typically and at its worst: it also skips DisplayExtend's
    // re-encode, which costs picture
    constexpr double k_DirectBiasMs = 5;
    constexpr double k_DirectWorstBiasMs = 10;

    // DisplayExtend's delay when it hasn't measured enough frames: the p50 measured on the user's
    // Wi-Fi (DisplayExtend's PHASE0-RESULTS.md)
    constexpr double k_DefaultDisplayExtendMs = 20.7;
    constexpr double k_DefaultDisplayExtendWorstMs = 76;
    constexpr int k_MinDisplayExtendFrames = 60;

    // Decode times: the iMac's H.264 (measured), the Mac's (typical for VideoToolbox)
    constexpr double k_ImacDecodeMs = 1.7;
    constexpr double k_MacDecodeMs = 2.0;

    Decision decide(Setting setting, const Facts& facts);

    // "straight from the PC (about 18 ms vs 46 ms; iMac→PC 3 ms, Mac→PC 2 ms, DisplayExtend 21 ms)",
    // or "through this Mac (the iMac isn't paired with this PC)"
    std::string describe(const Decision& decision, const Facts& facts);

    // The median of some values; -1 for none
    double median(std::vector<double> values);

    // Rounds of probes to one address as one: all their connects and failures, the median of their
    // medians, and the worst of their worst
    Probe combine(const std::vector<Probe>& rounds);

    // Which of a first round's addresses to keep probing: those with a connect that went through.
    // An address the iMac can't reach at all (the PC's home address, away from home) waits out a
    // timeout on every connect, which made each round about 2 s instead of 250 ms.
    std::vector<size_t> answering(const std::vector<Probe>& firstRound);

    // StreamingPreferences::VideoCodecConfig, which slot 0 and the helpers are set by; kept the same
    // there by static_asserts in forkdisplaycoordinator.cpp
    constexpr int k_VccAutomatic = 0, k_VccH264 = 1, k_VccHevc = 2, k_VccHevcHdr = 3, k_VccAv1 = 4;
    int codecConfig(Codec codec);

    // The "iMac bitrate" setting's range; 0 is automatic
    constexpr int k_ImacMinBitrateKbps = 2000;
    constexpr int k_ImacMaxBitrateKbps = 100000;

    // An automatic bitrate straight from the PC stops here: the iMac's hardware decodes H.264 only,
    // which tops out well below what a Mac display may get
    constexpr int k_DirectMaxBitrateKbps = 50000;

    struct ImacStream {
        Codec codec = Codec::H264;   // through this Mac on Automatic: what slot 0's setting asks for (HEVC when automatic)
        bool sameAsMain = false;     // through this Mac on Automatic: the helper takes slot 0's codec setting as is
        int kbps = 0;
        bool automaticKbps = true;
        std::string note;            // why the codec isn't the one set; empty when it is
    };

    // The codec and bitrate of the iMac's display's stream from the PC: the iMac's Moonlight's
    // straight from the PC, the helper's through this Mac.
    // - Codec: as set; on Automatic, straight from the PC one the iMac decodes in hardware (HEVC,
    //   then AV1, then H.264), through this Mac slot 0's. Straight from the PC, a codec the iMac's
    //   DisplayExtend can't be asked for is H.264, with a note.
    // - Bitrate: as set; on Automatic, the slot's (slot 0's scaled by pixel rate, ForkDisplayGroup::
    //   plan(), so sized for slot 0's codec), times two when the iMac's is H.264 and slot 0's isn't,
    //   halved the other way round (slot 0 on Automatic counts as HEVC). At the scaled 14.7 Mbps
    //   a 1080p60 desktop's colors pulsed on the iMac in H.264, as Apollo re-encoded the still
    //   picture, while the same display through this Mac (HEVC from the PC) was steady.
    ImacStream imacStream(Route route, CodecSetting codecSetting, int kbpsSetting, int slotKbps,
                          int mainCodecConfig, const ImacCodecs& imac);

    // "HEVC at 20000 kbps (set in Settings)", "H.264 at 29388 kbps (automatic)", "slot 0's codec at
    // 14694 kbps (automatic)", with the note after a semicolon
    std::string describe(const ImacStream& stream);
}
