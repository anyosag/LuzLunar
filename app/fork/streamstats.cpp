#include "streamstats.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>

#include <Limelight.h>

#include "hostpacing.h"
#include "streaming/session.h"

namespace ForkStreamStats
{

namespace
{
    std::atomic<bool> s_Wanted { false };
    std::mutex s_ListenerMutex;
    std::function<void(const Snapshot&)> s_Listener;
    std::function<void(const Snapshot&)> s_BitrateListener;
    std::atomic<double> s_TargetMbps { 0 };
    std::atomic<double> s_OwnMbps { 0 };

    std::mutex s_ConnectionListenerMutex;
    std::function<bool(bool, bool)> s_ConnectionListener;
    bool s_ConnectionPoor = false;
    bool s_SuggestLowerBitrate = false;

    std::mutex s_HistoryMutex;
    StreamHistory::History s_History;
    Snapshot s_Latest;
    bool s_HaveLatest = false;

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

void setBitrate(double targetMbps, double ownMbps)
{
    s_TargetMbps = targetMbps;
    s_OwnMbps = ownMbps;
}

void publish(const VIDEO_STATS& stats, int videoFormat, double averageMbps)
{
    Snapshot snapshot;
    snapshot.seconds = nowSeconds();
    snapshot.fps = stats.renderedFps;
    snapshot.rttMs = stats.lastRtt;
    snapshot.rttVarianceMs = stats.lastRttVariance;
    snapshot.mbps = averageMbps;
    snapshot.codec = codecName(videoFormat);
    snapshot.dropPercent = stats.totalFrames != 0 ? 100.0 * stats.networkDroppedFrames / stats.totalFrames : 0.0;
    snapshot.droppedFrames = stats.networkDroppedFrames;
    snapshot.totalFrames = stats.totalFrames;
    snapshot.jitterDropPercent = stats.decodedFrames != 0 ? 100.0 * stats.pacerDroppedFrames / stats.decodedFrames : 0.0;
    snapshot.targetMbps = s_TargetMbps;
    snapshot.ownMbps = s_OwnMbps;

    StreamHistory::Totals totals;
    totals.totalHostProcessingLatency = stats.totalHostProcessingLatency;
    totals.framesWithHostProcessingLatency = stats.framesWithHostProcessingLatency;
    totals.totalDecodeTimeUs = stats.totalDecodeTimeUs;
    totals.decodedFrames = stats.decodedFrames;
    totals.totalPacerTimeUs = stats.totalPacerTimeUs;
    totals.totalRenderTimeUs = stats.totalRenderTimeUs;
    totals.renderedFrames = stats.renderedFrames;
    totals.lastRttMs = stats.lastRtt;
    snapshot.latencyMs = StreamHistory::latency(totals);

    double pacingAverage;
    double pacingLowest;
    if (ForkHostPacing::takeWindow(&pacingAverage, &pacingLowest)) {
        snapshot.pacingAverage = pacingAverage;
        snapshot.pacingLowest = pacingLowest;
    }

    {
        StreamHistory::Sample sample;
        sample.seconds = snapshot.seconds;
        sample.parts = snapshot.latencyMs;
        sample.fps = snapshot.fps;
        sample.dropPercent = snapshot.dropPercent;
        sample.targetMbps = snapshot.targetMbps;
        sample.pacingLowest = snapshot.pacingLowest;
        sample.pacingAverage = snapshot.pacingAverage;

        std::lock_guard<std::mutex> lock(s_HistoryMutex);
        s_History.add(sample);
        s_Latest = snapshot;
        s_HaveLatest = true;
    }

    std::lock_guard<std::mutex> lock(s_ListenerMutex);
    if (s_BitrateListener) {
        s_BitrateListener(snapshot);
    }
    if (s_Listener) {
        s_Listener(snapshot);
    }
}

double nowSeconds()
{
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

void resetHistory()
{
    std::lock_guard<std::mutex> lock(s_HistoryMutex);
    s_History.reset();
    s_Latest = Snapshot();
    s_HaveLatest = false;
}

std::vector<StreamHistory::Sample> history()
{
    double now = nowSeconds();
    std::lock_guard<std::mutex> lock(s_HistoryMutex);
    return s_History.window(now);
}

bool latest(Snapshot* snapshot)
{
    std::lock_guard<std::mutex> lock(s_HistoryMutex);
    if (s_HaveLatest) {
        *snapshot = s_Latest;
    }
    return s_HaveLatest;
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

void resetConnectionStatus()
{
    std::lock_guard<std::mutex> lock(s_ConnectionListenerMutex);
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
        name += " · 4:4:4";
    }
    if (videoFormat & VIDEO_FORMAT_MASK_10BIT) {
        name += LiGetCurrentHostDisplayHdrMode() ? " · HDR" : " · 10-bit";
    }
    return name;
}

}
