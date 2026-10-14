#include "streamstats.h"

#include <atomic>
#include <mutex>

#include <Limelight.h>

namespace ForkStreamStats
{

namespace
{
    std::atomic<bool> s_Wanted { false };
    std::mutex s_ListenerMutex;
    std::function<void(const Snapshot&)> s_Listener;
}

bool wanted()
{
    return s_Wanted.load(std::memory_order_relaxed);
}

void setListener(std::function<void(const Snapshot&)> listener)
{
    std::lock_guard<std::mutex> lock(s_ListenerMutex);
    s_Listener = std::move(listener);
    s_Wanted = static_cast<bool>(s_Listener);
}

void publish(const VIDEO_STATS& stats, int videoFormat, double averageMbps)
{
    Snapshot snapshot;
    snapshot.fps = stats.renderedFps;
    snapshot.rttMs = stats.lastRtt;
    snapshot.mbps = averageMbps;
    snapshot.codec = codecName(videoFormat);
    snapshot.dropPercent = stats.totalFrames != 0 ? 100.0 * stats.networkDroppedFrames / stats.totalFrames : 0.0;

    std::lock_guard<std::mutex> lock(s_ListenerMutex);
    if (s_Listener) {
        s_Listener(snapshot);
    }
}

QString codecName(int videoFormat)
{
    QString name;
    if (videoFormat & VIDEO_FORMAT_MASK_H264) {
        name = "H.264";
    }
    else if (videoFormat & VIDEO_FORMAT_MASK_H265) {
        name = "HEVC";
    }
    else if (videoFormat & VIDEO_FORMAT_MASK_AV1) {
        name = "AV1";
    }
    else {
        name = "?";
    }

    if (videoFormat & VIDEO_FORMAT_MASK_YUV444) {
        name += " 4:4:4";
    }
    if (videoFormat & VIDEO_FORMAT_MASK_10BIT) {
        name += LiGetCurrentHostDisplayHdrMode() ? " HDR" : " 10-bit";
    }
    return name;
}

}
