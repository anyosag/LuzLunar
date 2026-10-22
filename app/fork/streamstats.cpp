#include "streamstats.h"

#include <atomic>
#include <cstring>
#include <mutex>

#include <Limelight.h>

#include "streaming/session.h"

namespace ForkStreamStats
{

namespace
{
    std::atomic<bool> s_Wanted { false };
    std::mutex s_ListenerMutex;
    std::function<void(const Snapshot&)> s_Listener;
    std::function<void(const Snapshot&)> s_BitrateListener;
    std::atomic<double> s_BitrateCapMbps { 0 };

    std::mutex s_ConnectionListenerMutex;
    std::function<bool(bool, bool)> s_ConnectionListener;
    bool s_ConnectionPoor = false;
    bool s_SuggestLowerBitrate = false;

    // Moonlight's own warning text, as in Session::clConnectionStatusUpdate()
    const char* overlayWarningText(bool suggestLowerBitrate)
    {
        return suggestLowerBitrate ? "Slow connection to PC\nReduce your bitrate" : "Poor connection to PC";
    }
}

bool wanted()
{
    return s_Wanted.load(std::memory_order_relaxed);
}

void setListener(std::function<void(const Snapshot&)> listener)
{
    std::lock_guard<std::mutex> lock(s_ListenerMutex);
    s_Listener = std::move(listener);
    s_Wanted = s_Listener || s_BitrateListener;
}

void setBitrateListener(std::function<void(const Snapshot&)> listener)
{
    std::lock_guard<std::mutex> lock(s_ListenerMutex);
    s_BitrateListener = std::move(listener);
    s_Wanted = s_Listener || s_BitrateListener;
}

void setBitrateCap(double mbps)
{
    s_BitrateCapMbps = mbps;
}

void publish(const VIDEO_STATS& stats, int videoFormat, double averageMbps)
{
    Snapshot snapshot;
    snapshot.fps = stats.renderedFps;
    snapshot.rttMs = stats.lastRtt;
    snapshot.mbps = averageMbps;
    snapshot.codec = codecName(videoFormat);
    snapshot.dropPercent = stats.totalFrames != 0 ? 100.0 * stats.networkDroppedFrames / stats.totalFrames : 0.0;
    snapshot.bitrateCapMbps = s_BitrateCapMbps;

    std::lock_guard<std::mutex> lock(s_ListenerMutex);
    if (s_BitrateListener) {
        s_BitrateListener(snapshot);
    }
    if (s_Listener) {
        s_Listener(snapshot);
    }
}

bool reportConnectionStatus(bool poor, bool suggestLowerBitrate)
{
    std::lock_guard<std::mutex> lock(s_ConnectionListenerMutex);
    s_ConnectionPoor = poor;
    s_SuggestLowerBitrate = suggestLowerBitrate;
    return s_ConnectionListener && s_ConnectionListener(poor, suggestLowerBitrate);
}

void setConnectionListener(std::function<bool(bool poor, bool suggestLowerBitrate)> listener)
{
    std::lock_guard<std::mutex> lock(s_ConnectionListenerMutex);
    s_ConnectionListener = std::move(listener);
    s_ConnectionPoor = false;
    s_SuggestLowerBitrate = false;
}

bool connectionPoor(bool* suggestLowerBitrate)
{
    std::lock_guard<std::mutex> lock(s_ConnectionListenerMutex);
    *suggestLowerBitrate = s_SuggestLowerBitrate;
    return s_ConnectionPoor;
}

void setConnectionWarningInOverlay(bool inOverlay)
{
    bool suggestLowerBitrate;
    if (!connectionPoor(&suggestLowerBitrate)) {
        return;
    }

    Session* session = Session::get();
    if (session == nullptr) {
        return;
    }

    Overlay::OverlayManager& overlays = session->getOverlayManager();
    const char* text = overlayWarningText(suggestLowerBitrate);
    if (inOverlay) {
        // Doesn't cover a status message that's up, like gamepad mouse mode's
        if (!overlays.isOverlayEnabled(Overlay::OverlayStatusUpdate)) {
            overlays.updateOverlayText(Overlay::OverlayStatusUpdate, text);
            overlays.setOverlayState(Overlay::OverlayStatusUpdate, true);
        }
    }
    else {
        const char* current = overlays.getOverlayText(Overlay::OverlayStatusUpdate);
        if (overlays.isOverlayEnabled(Overlay::OverlayStatusUpdate) && current != nullptr && strcmp(current, text) == 0) {
            overlays.setOverlayState(Overlay::OverlayStatusUpdate, false);
        }
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
