#include "upscalerules.h"

#include <algorithm>
#include <cstdio>

namespace UpscaleRules
{

Mode modeFromInt(int value)
{
    switch (value) {
    case static_cast<int>(Mode::Fast):
        return Mode::Fast;
    case static_cast<int>(Mode::Quality):
        return Mode::Quality;
    default:
        return Mode::Off;
    }
}

Mode effectiveMode(Mode requested, bool lowPowerMode, bool yuv444)
{
    if (requested == Mode::Quality && (lowPowerMode || yuv444)) {
        return Mode::Fast;
    }
    return requested;
}

bool needsUpscale(int frameWidth, int frameHeight, int rectWidth, int rectHeight)
{
    if (frameWidth <= 0 || frameHeight <= 0) {
        return false;
    }
    return rectWidth > frameWidth * 1.02 || rectHeight > frameHeight * 1.02;
}

float pickScaleFactor(int frameWidth, int frameHeight, int rectWidth, int rectHeight,
                      const std::vector<float>& supported)
{
    if (frameWidth <= 0 || frameHeight <= 0 || rectWidth <= 0 || rectHeight <= 0) {
        return 0;
    }

    double needed = std::min(static_cast<double>(rectWidth) / frameWidth,
                             static_cast<double>(rectHeight) / frameHeight);
    float best = 0;
    for (float factor : supported) {
        if (factor > 1.01f && factor <= needed * 1.02 && factor > best) {
            best = factor;
        }
    }
    return best;
}

const char* engineName(Engine engine)
{
    switch (engine) {
    case Engine::Bilinear:
        return "bilinear";
    case Engine::Lanczos:
        return "Lanczos";
    case Engine::MetalFx:
        return "MetalFX";
    case Engine::SuperResolution:
        return "VT super resolution";
    case Engine::None:
    default:
        return "none";
    }
}

std::string overlayLine(const Status& status)
{
    char line[192];
    if (status.engine == Engine::None) {
        if (status.note.empty()) {
            return std::string();
        }
        std::snprintf(line, sizeof(line), "Upscaling: none (%s)\n", status.note.c_str());
        return line;
    }

    int written = std::snprintf(line, sizeof(line), "Upscaling: %s %dx%d -> %dx%d",
                                engineName(status.engine), status.frameWidth, status.frameHeight,
                                status.outWidth, status.outHeight);
    std::string text(line, written > 0 ? static_cast<size_t>(written) : 0);

    if (status.frameWidth > 0 && status.outWidth > 0) {
        std::snprintf(line, sizeof(line), " (%.2gx)", static_cast<double>(status.outWidth) / status.frameWidth);
        text += line;
    }
    if (status.ms >= 0) {
        std::snprintf(line, sizeof(line), ", %.1f ms", status.ms);
        text += line;
    }
    if (!status.note.empty()) {
        text += " (" + status.note + ")";
    }
    text += "\n";
    return text;
}

}
