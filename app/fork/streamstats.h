#pragma once

#include <cstdint>
#include <functional>

#include <QString>

#include "streaming/video/decoder.h"

// Live stream statistics for fork UI such as the notch bar. FFmpegVideoDecoder publishes them
// about once a second from its decode thread, but only while a listener is set. Connection quality
// changes from moonlight-common-c come through here too.
namespace ForkStreamStats
{
    struct Snapshot {
        double fps;           // frames rendered per second
        uint32_t rttMs;       // network round trip time
        double mbps;          // video bitrate
        QString codec;        // e.g. "AV1 HDR"
        double dropPercent;   // frames lost on the network
        double bitrateCapMbps = 0;  // what adaptive bitrate lowered the stream to; 0 while it isn't lowered
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

    void publish(const VIDEO_STATS& stats, int videoFormat, double averageMbps);

    // Called by Session::clConnectionStatusUpdate() on moonlight-common-c's receive thread. Returns
    // true when the listener showed the poor connection warning itself, so Moonlight's status
    // overlay doesn't need to.
    bool reportConnectionStatus(bool poor, bool suggestLowerBitrate);

    // Same rules as setListener(): once it returns, a previous listener is no longer running or called.
    // Also forgets the last reported status, so a new stream starts with an okay connection.
    void setConnectionListener(std::function<bool(bool poor, bool suggestLowerBitrate)> listener);

    // Whether the connection was poor at the last report, and if so whether a lower bitrate would help
    bool connectionPoor(bool* suggestLowerBitrate);

    // Moves a poor connection warning that's already up into Moonlight's status overlay, or out of it,
    // for a listener that starts or stops showing the warning itself between reports. Main thread.
    void setConnectionWarningInOverlay(bool inOverlay);

    QString codecName(int videoFormat);
}
