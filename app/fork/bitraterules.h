#pragma once

#include <cstdint>

// [fork] Adaptive bitrate's controller (adaptivebitrate.*), kept free of Qt so tests can build it
// alone. Once a second it looks at the stream's losses and round-trip time and decides whether to
// ask the PC for a lower bitrate, or for more of the user's own bitrate back.
//
// - Waits 5 s after the stream starts and after each change, so a change shows before the next.
// - Cuts to 70% when 2% of frames or more are lost, or the connection is poor; holds 10 s.
// - Cuts to 90% after 3 seconds in a row of a round-trip time above the stream's lowest plus
//   max(30 ms, half of it), since the queue on the way is growing; holds 10 s. "Lowest" is over the
//   last 15 to 30 s, so a route that got slower for good stops counting as a queue.
// - Climbs by 5% of the user's bitrate per 5 clean seconds, every 15 clean seconds once near the
//   bitrate it last had to leave.
// - Never below max(3 Mb/s, 20% of the user's bitrate), 5 Mb/s with HDR; never above the user's.
namespace BitrateRules
{
    // The lowest it goes: max(3 Mb/s, 20% of the user's bitrate), 5 Mb/s with HDR, but never above
    // the user's bitrate
    int floorKbps(int chosenKbps, bool hdr);

    // One second of the stream
    struct Sample {
        double seconds = 0;     // since the stream started, steady
        double dropPercent = 0; // frames lost on the network, over the last seconds
        uint32_t rttMs = 0;     // round-trip time; 0 when unknown
        bool poor = false;      // moonlight-common-c calls the connection poor
    };

    class Controller
    {
    public:
        Controller(int chosenKbps, bool hdr);

        // The bitrate to ask for now, or 0 to stay at currentKbps()
        int tick(const Sample& sample);

        int chosenKbps() const { return m_ChosenKbps; }
        int floorKbps() const { return m_FloorKbps; }
        int currentKbps() const { return m_CurrentKbps; }

        // Below the user's bitrate
        bool lowered() const { return m_CurrentKbps < m_ChosenKbps; }

        // The bitrate it had to leave last; 0 once it's back above it
        int lastLossKbps() const { return m_LastLossKbps; }

        // The round-trip time the stream counts as its own, without a queue; 0 while unknown
        uint32_t baseRttMs() const;

    private:
        int changeTo(int kbps, double now, double hold);
        void noteRtt(uint32_t rttMs, double now);

        int m_ChosenKbps;
        int m_FloorKbps;
        int m_CurrentKbps;
        int m_LastLossKbps = 0;
        int m_RttHighSeconds = 0;
        double m_HoldUntil;     // no change before this
        double m_LastBad = 0;   // the last second that lost frames or had a high round-trip time
        bool m_SeenBad = false;

        // The lowest round-trip time in this 15 s bucket and the one before
        uint32_t m_RttMinNow = 0;
        uint32_t m_RttMinBefore = 0;
        double m_RttBucketStart = 0;
    };
}
