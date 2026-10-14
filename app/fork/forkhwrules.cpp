#include "forkhwrules.h"

#include <cmath>
#include <cstdio>
#include <numeric>

namespace ForkHwRules
{

namespace
{
    // The hardware H.264 decoder stops at 4096 pixels on a side; 8192 is the most any of them handle
    const int k_MaxH264Side = 4096;
    const int k_MaxSide = 8192;

    // A frame rate a little above the refresh rate (125 on 120 Hz) isn't worth a warning
    const int k_RefreshSlack = 5;

    struct NamedRatio {
        const char* name;
        double ratio;
    };

    // Ultrawide "21:9" panels are really 64:27 (2560x1080, 5120x2160) or 7:3, and 3440x1440 is in between
    const NamedRatio k_NamedRatios[] = {
        { "1:1", 1.0 },
        { "5:4", 5.0 / 4 },
        { "4:3", 4.0 / 3 },
        { "3:2", 3.0 / 2 },
        { "16:10", 16.0 / 10 },
        { "16:9", 16.0 / 9 },
        { "21:9", 7.0 / 3 },
        { "21:9", 64.0 / 27 },
        { "32:9", 32.0 / 9 },
    };
}

std::vector<std::string> checkStream(const Decoders& decoders, const Display& display,
                                     int width, int height, int fps, Codec codec, bool hdr)
{
    std::vector<std::string> warnings;

    if (codec == Codec::H264) {
        if (!decoders.h264) {
            warnings.push_back("This Mac has no hardware H.264 decoder, so H.264 would be decoded in software and may stutter.");
        }
        else if (width > k_MaxH264Side || height > k_MaxH264Side) {
            warnings.push_back("This Mac can't decode H.264 above 4096 pixels wide or tall in hardware, so this stream would be decoded in software. Use HEVC or AV1, or lower the resolution.");
        }
    }
    else if (codec == Codec::HEVC && !decoders.hevc) {
        warnings.push_back("This Mac has no hardware HEVC decoder, so HEVC would be decoded in software and may stutter. Use H.264 or Automatic.");
    }
    else if (codec == Codec::AV1 && !decoders.av1) {
        warnings.push_back("This Mac has no hardware AV1 decoder (that needs an M3 or later), so AV1 would be decoded in software and may stutter. Use HEVC or Automatic.");
    }

    if (hdr) {
        if (codec == Codec::H264) {
            warnings.push_back("HDR needs HEVC or AV1, so it has no effect while H.264 is forced.");
        }
        else if (!decoders.hevcMain10 && !decoders.av1) {
            warnings.push_back("HDR needs hardware HEVC Main10 or AV1 decoding, and this Mac has neither, so HDR would be decoded in software and may stutter.");
        }
    }

    if (width > k_MaxSide || height > k_MaxSide) {
        warnings.push_back("This resolution is above 8192 pixels wide or tall, which is more than this Mac's hardware decoders handle.");
    }

    if (display.maxRefresh > 0 && fps > display.maxRefresh + k_RefreshSlack) {
        std::string name = display.name.empty() ? "This display" : display.name;
        warnings.push_back(name + " refreshes at up to " + std::to_string(display.maxRefresh) +
                           " Hz, so frames above that are dropped.");
    }

    return warnings;
}

std::string ratioLabel(int width, int height)
{
    if (width <= 0 || height <= 0) {
        return std::string();
    }

    if (height > width) {
        std::string landscape = ratioLabel(height, width);
        size_t colon = landscape.find(':');
        return landscape.substr(colon + 1) + ":" + landscape.substr(0, colon);
    }

    double ratio = static_cast<double>(width) / height;

    // The closest usual name within 1%
    const NamedRatio* best = nullptr;
    double bestOff = 0.01;
    for (const NamedRatio& named : k_NamedRatios) {
        double off = std::fabs(ratio / named.ratio - 1);
        if (off <= bestOff) {
            best = &named;
            bestOff = off;
        }
    }
    if (best != nullptr) {
        return best->name;
    }

    int divisor = std::gcd(width, height);
    int reducedWidth = width / divisor;
    int reducedHeight = height / divisor;
    if (reducedWidth <= 32 && reducedHeight <= 32) {
        return std::to_string(reducedWidth) + ":" + std::to_string(reducedHeight);
    }

    char decimal[32];
    std::snprintf(decimal, sizeof(decimal), "%.2f:1", ratio);
    return decimal;
}

}
