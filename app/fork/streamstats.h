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
    };

    // True while a listener is set; checked by the decoder before it computes anything
    bool wanted();

    // The listener runs on the decode thread, so it must be quick and thread-safe.
    // Once setListener() returns, a previous listener is no longer running or called.
    void setListener(std::function<void(const Snapshot&)> listener);

    void publish(const VIDEO_STATS& stats, int videoFormat, double averageMbps);

    // Called by Session::clConnectionStatusUpdate() on moonlight-common-c's receive thread. Returns
    // true when the listener showed the poor connection warning itself, so Moonlight's status
    // overlay doesn't need to.
    bool reportConnectionStatus(bool poor, bool suggestLowerBitrate);

    // Same rules as setListener(): once it returns, a previous listener is no longer running or called.
    void setConnectionListener(std::function<bool(bool poor, bool suggestLowerBitrate)> listener);

    QString codecName(int videoFormat);
}
