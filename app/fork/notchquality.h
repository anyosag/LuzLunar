#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>

#include "bitraterules.h"
#include "powerrules.h"

// [fork] The notch bar's Quality item and menu without AppKit (mac/notchmenus_mac.mm draws them), so
// tests can build it alone (tests/fork/notchquality_test.cpp): which reason line and caption show,
// how long ago, and the bitrate slider's range and steps. The strings are the menu's, translated there.
namespace NotchQuality
{
    // Why the bitrate can't change during the stream
    enum class Why {
        None,
        Encoder,    // the PC's encoder can't
        Apollo,     // the PC's Apollo can't: an older one, off, no permission
        NotApollo,  // the PC isn't LuzLunar's Apollo
    };

    // What the Quality item and menu show, gathered on the main thread
    struct State {
        bool known = false;     // the PC said whether it can change the bitrate
        bool live = true;       // it can, as far as known
        Why why = Why::None;
        bool adapting = false;  // adaptive bitrate is on
        int ownKbps = 0;        // the user's bitrate
        int targetKbps = 0;     // what the PC runs the stream at; 0 while unknown (then it's the user's)
        int minKbps = 0;        // what a request can set, from the PC; 0 while unknown
        int maxKbps = 0;

        // Adaptive bitrate's last change, while adapting
        BitrateRules::Reason changeReason = BitrateRules::Reason::None;
        double changeAgoSeconds = 0;
        uint32_t changeRttMs = 0;
        uint32_t changeBaseRttMs = 0;
        double changeDropPercent = 0;
        bool changePoor = false;

        bool saver = false;     // Stream Battery Saver is on (powerrules.h)
    };

    // Stream Battery Saver holds the stream at its cap or below: on, and the PC changes the bitrate live
    inline bool saverCaps(const State& state)
    {
        return state.saver && state.live;
    }

    // The yellow note under Quality's title
    enum class SaverNote {
        None,
        Caps,               // "Stream Battery Saver caps the bitrate at 10 Mb/s."
        NeedsReconnect,     // "On this PC, Stream Battery Saver needs a reconnect to cap the bitrate."
    };

    inline SaverNote saverNote(const State& state)
    {
        if (!state.saver) {
            return SaverNote::None;
        }
        return state.live ? SaverNote::Caps : SaverNote::NeedsReconnect;
    }

    // The bitrate the stream runs at, as far as known
    inline int shownKbps(const State& state)
    {
        return state.targetKbps > 0 ? state.targetKbps : state.ownKbps;
    }

    // Below the user's bitrate, by adaptive bitrate or by hand: the item's orange arrow
    inline bool lowered(const State& state)
    {
        return state.ownKbps > 0 && shownKbps(state) < state.ownKbps;
    }

    // "18", "18.5": megabits a second, to a tenth, without a needless ".0"
    inline std::string mbps(int kbps)
    {
        char text[24];
        int tenths = static_cast<int>(std::lround(kbps / 100.0));
        if (tenths % 10 == 0) {
            std::snprintf(text, sizeof(text), "%d", tenths / 10);
        }
        else {
            std::snprintf(text, sizeof(text), "%d.%d", tenths / 10, tenths % 10);
        }
        return text;
    }

    // "4", "2.5", "12": a percentage, to a tenth below 10
    inline std::string percent(double value)
    {
        char text[24];
        if (value >= 10) {
            std::snprintf(text, sizeof(text), "%.0f", value);
            return text;
        }
        int tenths = static_cast<int>(std::lround(value * 10));
        if (tenths % 10 == 0) {
            std::snprintf(text, sizeof(text), "%d", tenths / 10);
        }
        else {
            std::snprintf(text, sizeof(text), "%d.%d", tenths / 10, tenths % 10);
        }
        return text;
    }

    // The line under the switch
    enum class Line {
        None,
        LoweredLoss,        // "Lowered 1 min ago: 4% of frames lost"
        LoweredPoor,        // "Lowered 1 min ago: the connection was poor"
        LoweredRoundTrip,   // "Lowered 1 min ago: round-trip 48 ms, usually 8 ms"
        Climbing,           // "Climbing back to your 20 Mb/s"
        Holding,            // "Holding the bitrate you set"
        EncoderCant,        // "This PC's encoder can't change the bitrate during a stream."
        ApolloCant,         // "This PC's Apollo can't change the bitrate during a stream."
        PcCant,             // "This PC can't change the bitrate during a stream."
    };

    inline Line line(const State& state)
    {
        if (!state.live) {
            return state.why == Why::Encoder ? Line::EncoderCant : state.why == Why::NotApollo ? Line::PcCant : Line::ApolloCant;
        }
        if (!state.adapting) {
            return Line::Holding;
        }
        if (!lowered(state)) {
            return Line::None;
        }
        if (saverCaps(state) && shownKbps(state) >= std::min(state.ownKbps, PowerRules::k_SaverKbps)) {
            // At Stream Battery Saver's cap, which its note says
            return Line::None;
        }
        switch (state.changeReason) {
        case BitrateRules::Reason::Loss:
            // Called poor with few frames lost: the losses weren't why
            return state.changePoor && state.changeDropPercent < 2 ? Line::LoweredPoor : Line::LoweredLoss;
        case BitrateRules::Reason::RoundTrip:
            return Line::LoweredRoundTrip;
        default:
            // Climbing, or turned on below the user's bitrate and about to
            return Line::Climbing;
        }
    }

    // The caption under the slider
    enum class Caption {
        Adapting,       // "Adapting never goes above your 20 Mb/s."
        ByHand,         // "Up to 25 Mb/s without reconnecting."
        CantChange,     // "Changing it takes a new stream."
    };

    inline Caption caption(const State& state)
    {
        if (!state.live) {
            return Caption::CantChange;
        }
        return state.adapting ? Caption::Adapting : Caption::ByHand;
    }

    // "just now", "40 s ago", "1 min ago", "3 min ago"
    struct Ago {
        enum Unit { JustNow, Seconds, Minutes } unit = JustNow;
        int value = 0;
    };

    inline Ago ago(double seconds)
    {
        Ago result;
        if (seconds < 10) {
            return result;
        }
        if (seconds < 60) {
            result.unit = Ago::Seconds;
            result.value = static_cast<int>(seconds / 10) * 10;
            return result;
        }
        result.unit = Ago::Minutes;
        result.value = static_cast<int>(seconds / 60);
        return result;
    }

    // The slider: from 3 Mb/s (or the user's bitrate, if lower) to the most the PC takes, which is
    // the bitrate the stream launched with (Stream Battery Saver's cap while it's on), in steps of
    // half a megabit, its top a stop of its own
    struct Range {
        int minKbps = 3000;
        int maxKbps = 3000;
        int stepKbps = 500;
    };

    inline Range range(const State& state)
    {
        Range result;
        int own = state.ownKbps > 0 ? state.ownKbps : 3000;
        result.minKbps = std::max(std::min(3000, own), state.minKbps);
        int top = state.maxKbps > 0 ? state.maxKbps : own;
        if (saverCaps(state)) {
            // Up to the saver's cap while it's on
            top = std::min(top, PowerRules::k_SaverKbps);
        }
        result.maxKbps = std::max(top, result.minKbps);
        return result;
    }

    inline int snap(int kbps, const Range& range)
    {
        if (kbps >= range.maxKbps - range.stepKbps / 2) {
            return range.maxKbps;
        }
        int stepped = static_cast<int>(std::lround(static_cast<double>(kbps) / range.stepKbps)) * range.stepKbps;
        return std::max(range.minKbps, std::min(stepped, range.maxKbps));
    }

    inline bool sliderEnabled(const State& state)
    {
        return state.live && !state.adapting;
    }

    inline bool switchEnabled(const State& state)
    {
        return state.live;
    }
}
