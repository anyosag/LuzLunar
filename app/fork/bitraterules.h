#pragma once

#include <cstdint>

// [fork] Adaptive bitrate's controller (adaptivebitrate.*), kept free of Qt so tests can build it
// alone. Once a second it looks at the stream's losses and round-trip time and decides whether to
// ask the PC for a lower bitrate, or for more of the user's own bitrate back.
//
// - Waits 5 s after the stream starts and after each change, so a change shows before the next.
// - Cuts to 70% when 2% of frames or more are lost (and at least 3: a quiet desktop sends a few
//   frames a second, where one lost frame is 10%), or the connection is poor; holds 10 s.
// - Cuts to 90% after 3 seconds in a row of a round-trip time above the stream's lowest plus
//   max(30 ms, half of it), since a queue is building on the way; holds 10 s. "Lowest" is the
//   lowest of the whole stream, so a queue the stream builds itself keeps counting, however long it
//   lasts. But a queue the stream builds moves when it sends less: when two such cuts in a row
//   leave the round-trip time where the first found it (within max(10 ms, 15%)), above the line
//   all along, the route itself got slower, and its time becomes the lowest from then on. At the
//   floor, where it can't cut, the same check runs every 10 s. A second back under the line or a
//   loss (a queue overflowing) shows the queue was the stream's own, and starts the count over.
// - Climbs by 5% of the user's bitrate per 5 clean seconds, every 15 clean seconds once near the
//   bitrate it last had to leave. A climb holds only 5 s, so losses it brings are cut at once.
// - Never below max(3 Mb/s, 20% of the user's bitrate), 5 Mb/s with HDR; never above the user's.
namespace BitrateRules
{
    // The lowest it goes: max(3 Mb/s, 20% of the user's bitrate), 5 Mb/s with HDR, but never above
    // the user's bitrate
    int floorKbps(int chosenKbps, bool hdr);

    // The bitrate a stream launches with when the PC starts it at the user's own (Apollo's
    // LuzBitrateStart, luzBitrate=N): a quarter above, since the PC never raises a stream above its
    // launch bitrate, so there's room to raise it later. moonlight-common-c chooses the audio by the
    // launch bitrate (Limelight-internal.h: high quality from 15 Mb/s, 10 ms packets below 5 Mb/s),
    // so the launch stays on the user's side of both lines and the audio is what it would have been.
    int launchKbps(int chosenKbps);

    // One second of the stream
    struct Sample {
        double seconds = 0;     // since the stream started, steady
        double dropPercent = 0; // frames lost on the network, over the last seconds
        uint32_t lostFrames = 0; // how many that was
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
        uint32_t baseRttMs() const { return m_BaseRttMs; }

    private:
        int changeTo(int kbps, double now, double hold);

        int m_ChosenKbps;
        int m_FloorKbps;
        int m_CurrentKbps;
        int m_LastLossKbps = 0;
        int m_RttHighSeconds = 0;
        double m_HoldUntil;     // no change before this
        double m_NextClimbAt = 0; // no climb before this
        double m_LastBad = 0;   // the last second that lost frames or had a high round-trip time
        bool m_SeenBad = false;

        // The lowest round-trip time of the stream, or since the route last got slower
        uint32_t m_BaseRttMs = 0;
        // The lowest of the seconds in a row with a high round-trip time: the queue's level
        uint32_t m_HighRunMinMs = 0;
        // The queue's level at the first of the cuts for the round-trip time in a row; 0 for none
        uint32_t m_FlatRttLevelMs = 0;
        // The cuts since then that left it there
        int m_FlatRttCuts = 0;
    };
}
