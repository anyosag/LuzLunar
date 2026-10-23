#pragma once

#include <cstdint>
#include <functional>
#include <vector>

#include <QString>

#include "streamhistory.h"
#include "streaming/video/decoder.h"

// Live stream statistics for fork UI such as the notch bar. FFmpegVideoDecoder publishes them
// about once a second from its decode thread, but only while a listener is set. Connection quality
// changes from moonlight-common-c come through here too.
namespace ForkStreamStats
{
    struct Snapshot {
        double seconds = 0;         // when, on nowSeconds()'s clock
        double fps = 0;             // frames rendered per second
        uint32_t rttMs = 0;         // network round trip time; 0 when not measured
        uint32_t rttVarianceMs = 0;
        double mbps = 0;            // video bitrate
        QString codec;              // e.g. "AV1 · HDR"
        double dropPercent = 0;     // frames lost on the network
        uint32_t droppedFrames = 0; // how many, of
        uint32_t totalFrames = 0;   // the frames the percentage is over
        double jitterDropPercent = 0;   // frames dropped as they arrived too unevenly to show
        double bitrateCapMbps = 0;  // what adaptive bitrate lowered the stream to; 0 while it isn't lowered
        StreamHistory::Parts latencyMs = StreamHistory::unknownParts();    // from a click to the picture
        double pacingLowest = StreamHistory::unknown();     // the PC's frame pacing since the last snapshot
        double pacingAverage = StreamHistory::unknown();
    };

    // True while a listener is set; checked by the decoder before it computes anything
    bool wanted();

    // The listener runs on the decode thread, so it must be quick and thread-safe.
    // Once setListener() returns, a previous listener is no longer running or called.
    void setListener(std::function<void(const Snapshot&)> listener);

    // A second listener, for adaptive bitrate (adaptivebitrate.*); the same rules
    void setBitrateListener(std::function<void(const Snapshot&)> listener);

    // What adaptive bitrate lowered the stream to, for the snapshots; 0 while it isn't lowered.
    // Any thread.
    void setBitrateCap(double mbps);

    // Also adds the snapshot to the stream's history, before the listeners hear it
    void publish(const VIDEO_STATS& stats, int videoFormat, double averageMbps);

    // The clock snapshots and the history use, in seconds
    double nowSeconds();

    // A new stream: forgets the last one's history and snapshot. Before any listener is set.
    void resetHistory();

    // The last two minutes, oldest first. Any thread.
    std::vector<StreamHistory::Sample> history();

    // The last snapshot published; false before the first. Any thread.
    bool latest(Snapshot* snapshot);

    // Called by Session::clConnectionStatusUpdate() on moonlight-common-c's receive thread. Returns
    // true when the listener showed the poor connection warning itself, so Moonlight's status
    // overlay doesn't need to.
    bool reportConnectionStatus(bool poor, bool suggestLowerBitrate);

    // Same rules as setListener(): once it returns, a previous listener is no longer running or called.
    // Also forgets the last reported status, so a new stream starts with an okay connection.
    void setConnectionListener(std::function<bool(bool poor, bool suggestLowerBitrate)> listener);

    // Forgets the last reported status, so a stream doesn't start with the poor connection the last
    // one ended with. Any thread.
    void resetConnectionStatus();

    // Whether the connection was poor at the last report, and if so whether a lower bitrate would help
    bool connectionPoor(bool* suggestLowerBitrate);

    // Moves a poor connection warning that's already up into Moonlight's status overlay, or out of it,
    // for a listener that starts or stops showing the warning itself between reports. Main thread.
    void setConnectionWarningInOverlay(bool inOverlay);

    // "HEVC · HDR", "AV1 · 4:4:4 · 10-bit"
    QString codecName(int videoFormat);
}
