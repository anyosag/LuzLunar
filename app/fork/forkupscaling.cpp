#include "forkupscaling.h"

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

#include "mac/macintegration.h"
#include "SDL_compat.h"

extern "C" {
#include <libavutil/frame.h>
}

namespace ForkUpscaling
{

namespace
{
    std::atomic<int> s_Mode { static_cast<int>(UpscaleRules::Mode::Off) };

    // Everything below is under s_Lock: the render thread reports, the decode thread reads the
    // overlay line and the main thread logs the summary
    std::mutex s_Lock;
    UpscaleRules::Status s_Status;
    std::string s_QualityNote;
    bool s_HaveReport = false;

    // The time reports since the last overlay line, and over the whole stream
    double s_WindowMs = 0;
    int s_WindowCount = 0;
    double s_StreamMs = 0;
    int s_StreamTimed = 0;

    // Frames reported by engine, for the summary
    int s_Frames[5] = {};
}

void FrameFree::operator()(AVFrame* frame) const
{
    av_frame_free(&frame);
}

void activate(int requestedMode, bool yuv444)
{
    UpscaleRules::Mode requested = UpscaleRules::modeFromInt(requestedMode);
    bool lowPower = MacIntegration::lowPowerModeEnabled();
    UpscaleRules::Mode mode = UpscaleRules::effectiveMode(requested, lowPower, yuv444);

    {
        std::lock_guard<std::mutex> lock(s_Lock);
        s_Status = UpscaleRules::Status();
        s_QualityNote.clear();
        s_HaveReport = false;
        s_WindowMs = 0;
        s_WindowCount = 0;
        s_StreamMs = 0;
        s_StreamTimed = 0;
        memset(s_Frames, 0, sizeof(s_Frames));
        if (requested == UpscaleRules::Mode::Quality && mode != requested) {
            s_QualityNote = lowPower ? "Quality: Low Power Mode is on" : "Quality: full color stream";
        }
    }

    resetSuperResolution();
    s_Mode.store(static_cast<int>(mode));

    static const char* const names[] = { "off", "fast", "quality" };
    if (mode != requested) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Upscaling: %s instead of %s, because %s",
                    names[static_cast<int>(mode)], names[static_cast<int>(requested)],
                    lowPower ? "Low Power Mode is on" : "the stream is full color (4:4:4)");
    }
    else if (mode != UpscaleRules::Mode::Off) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Upscaling: %s", names[static_cast<int>(mode)]);
    }
}

void deactivate()
{
    UpscaleRules::Mode mode = UpscaleRules::modeFromInt(s_Mode.exchange(static_cast<int>(UpscaleRules::Mode::Off)));
    resetSuperResolution();

    if (mode == UpscaleRules::Mode::Off) {
        return;
    }

    std::lock_guard<std::mutex> lock(s_Lock);
    int total = 0;
    for (int count : s_Frames) {
        total += count;
    }
    if (total == 0) {
        return;
    }

    using UpscaleRules::Engine;
    char average[48] = "";
    if (s_StreamTimed > 0) {
        snprintf(average, sizeof(average), " (%.1f ms on average)", s_StreamMs / s_StreamTimed);
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Upscaling this stream: %d frames by VT super resolution%s, %d by MetalFX, %d by Lanczos, %d bilinear, %d not upscaled",
                s_Frames[static_cast<int>(Engine::SuperResolution)],
                average,
                s_Frames[static_cast<int>(Engine::MetalFx)],
                s_Frames[static_cast<int>(Engine::Lanczos)],
                s_Frames[static_cast<int>(Engine::Bilinear)],
                s_Frames[static_cast<int>(Engine::None)]);
}

UpscaleRules::Mode mode()
{
    return UpscaleRules::modeFromInt(s_Mode.load());
}

void report(UpscaleRules::Engine engine, int frameWidth, int frameHeight, int outWidth, int outHeight,
            double ms, const char* note)
{
    std::lock_guard<std::mutex> lock(s_Lock);

    // Why Quality or MetalFX isn't in use: the renderer's own reason, else Quality's
    const char* why = note;
    if (why == nullptr && engine != UpscaleRules::Engine::SuperResolution && !s_QualityNote.empty()) {
        why = s_QualityNote.c_str();
    }

    bool changed = !s_HaveReport || engine != s_Status.engine ||
                   frameWidth != s_Status.frameWidth || frameHeight != s_Status.frameHeight ||
                   outWidth != s_Status.outWidth || outHeight != s_Status.outHeight ||
                   s_Status.note != (why != nullptr ? why : "");

    s_Status.engine = engine;
    s_Status.frameWidth = frameWidth;
    s_Status.frameHeight = frameHeight;
    s_Status.outWidth = outWidth;
    s_Status.outHeight = outHeight;
    s_Status.note = why != nullptr ? why : "";
    s_HaveReport = true;

    if (ms >= 0) {
        s_WindowMs += ms;
        s_WindowCount++;
        s_StreamMs += ms;
        s_StreamTimed++;
    }
    s_Frames[static_cast<int>(engine)]++;

    if (changed) {
        UpscaleRules::Status logged = s_Status;
        logged.ms = ms;
        std::string line = UpscaleRules::overlayLine(logged);
        if (!line.empty()) {
            line.pop_back();
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] %s", line.c_str());
        }
    }
}

void reportPlacebo(bool superResolved, int frameWidth, int frameHeight, int rectWidth, int rectHeight)
{
    if (superResolved || mode() == UpscaleRules::Mode::Off) {
        return;
    }

    if (UpscaleRules::needsUpscale(frameWidth, frameHeight, rectWidth, rectHeight)) {
        report(UpscaleRules::Engine::Lanczos, frameWidth, frameHeight, rectWidth, rectHeight);
    }
    else {
        report(UpscaleRules::Engine::None, frameWidth, frameHeight, rectWidth, rectHeight, -1,
               "the video already fills its area");
    }
}

void setQualityNote(const char* note)
{
    std::lock_guard<std::mutex> lock(s_Lock);
    s_QualityNote = note != nullptr ? note : "";
}

void appendOverlayLine(char* text, int maxLength)
{
    std::string line;
    {
        std::lock_guard<std::mutex> lock(s_Lock);
        if (!s_HaveReport || mode() == UpscaleRules::Mode::Off) {
            return;
        }
        UpscaleRules::Status status = s_Status;
        status.ms = s_WindowCount > 0 ? s_WindowMs / s_WindowCount : -1;
        s_WindowMs = 0;
        s_WindowCount = 0;
        line = UpscaleRules::overlayLine(status);
    }

    size_t length = strlen(text);
    if (line.empty() || maxLength <= 0 || length + line.size() >= static_cast<size_t>(maxLength)) {
        return;
    }
    memcpy(text + length, line.c_str(), line.size() + 1);
}

#ifndef Q_OS_DARWIN
AVFrame* superResolve(const AVFrame*, int, int)
{
    return nullptr;
}

bool superResolutionActive()
{
    return false;
}

bool superResolutionSupported()
{
    return false;
}

void resetSuperResolution()
{
}
#endif

}
