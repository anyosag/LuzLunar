#pragma once

#include <string>
#include <vector>

// Where the iMac's picture comes from in a multi-display stream (forkdisplaygroup.*), when one of the
// Mac's displays is DisplayExtend's: straight from the PC (Moonlight on the iMac streams that display
// from Apollo; DisplayExtend's client runs it) or through this Mac (a LuzLunar helper shows it on the
// virtual display, which DisplayExtend captures and streams to the iMac as usual). Chosen once per
// launch from what DisplayExtend's Host reports and what the probes measured.
//
// Kept free of Qt so it can be unit tested on its own (tests/fork/displayroute_test.cpp).
namespace ForkDisplayRoute
{
    // The "iMac picture" setting (ForkPreferences::imacRoute)
    enum class Setting { Automatic = 0, Direct = 1, ViaMac = 2 };

    enum class Route { Direct, ViaMac };

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
        int displayExtendFrames = 0;      // frames that went into it
        int imacRefreshHz = 60;
        int virtualRefreshHz = 60;        // the Mac's DisplayExtend display
    };

    struct Decision {
        Route route = Route::ViaMac;
        std::string address;              // the PC address the iMac streams from, for Direct
        double estDirectMs = -1, estViaMs = -1;   // -1 when not estimated
        std::string reason;               // why, for the log and Settings
    };

    // The thresholds an iMac to PC probe must meet for the direct route: every connect succeeds,
    // with a median and a worst case at most this long
    constexpr double k_DirectMaxMedianMs = 15;
    constexpr double k_DirectMaxWorstMs = 60;

    // Direct wins ties up to this much: it also skips DisplayExtend's re-encode, which costs picture
    constexpr double k_DirectBiasMs = 5;

    // DisplayExtend's delay when it hasn't measured enough frames: the p50 measured on the user's
    // Wi-Fi (DisplayExtend's PHASE0-RESULTS.md)
    constexpr double k_DefaultDisplayExtendMs = 20.7;
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
}
