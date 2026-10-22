#pragma once

#include <string>
#include <vector>

// [fork] Upscaling's rules (forkupscaling.*), in plain C++ so they're unit tested
// (tests/fork/upscalerules_test.cpp): which mode a stream gets, which scale factor super
// resolution uses, and the stats overlay's line.
namespace UpscaleRules
{
    // Settings › Video › Upscaling, saved as fork/upscaling
    enum class Mode {
        Off = 0,     // the renderers' own scaling, as upstream
        Fast = 1,    // Lanczos with the Vulkan renderer, MetalFX's spatial scaler with Metal
        Quality = 2, // VideoToolbox's low-latency super resolution, then Fast for what's left
    };

    // A saved value; anything unknown is Off
    Mode modeFromInt(int value);

    // What a stream gets: Low Power Mode and full color (4:4:4) streams use Fast instead of
    // Quality, the first to save power and the second because super resolution is made for
    // 4:2:0 video
    Mode effectiveMode(Mode requested, bool lowPowerMode, bool yuv444);

    // Whether the video's area on screen is more than 2 % larger than the frame on either side
    bool needsUpscale(int frameWidth, int frameHeight, int rectWidth, int rectHeight);

    // The largest of the supported factors that doesn't go beyond what the area needs (the
    // smaller of its two ratios, so a stretched picture never gets more than either side
    // needs, with 2 % to spare), or 0 when none fits. The renderer scales what's left.
    float pickScaleFactor(int frameWidth, int frameHeight, int rectWidth, int rectHeight,
                          const std::vector<float>& supported);

    enum class Engine {
        None,            // nothing upscaled: the video already fills its area, or it's off
        Bilinear,        // vt_metal's own sampling, when MetalFX can't
        Lanczos,         // libplacebo's
        MetalFx,         // MetalFX's spatial scaler
        SuperResolution, // VideoToolbox's low-latency super resolution
    };

    const char* engineName(Engine engine);

    // What the frame on screen went through
    struct Status
    {
        Engine engine = Engine::None;
        int frameWidth = 0;
        int frameHeight = 0;
        int outWidth = 0;
        int outHeight = 0;
        double ms = -1;   // the time it took, when known
        std::string note; // why Quality or MetalFX isn't used, if it was asked for
    };

    // "Upscaling: VT super resolution 1512x982 -> 3024x1964 (2x), 2.1 ms\n", with the note in
    // parentheses; ASCII only, for the overlay's font. Empty for a stream that never asked.
    std::string overlayLine(const Status& status);
}
