// Unit tests for app/fork/upscalerules.*, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/upscalerules_test.cpp app/fork/upscalerules.cpp
#include "fork/upscalerules.h"

#include <cstdio>

using namespace UpscaleRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static void testModes()
{
    CHECK(modeFromInt(0) == Mode::Off);
    CHECK(modeFromInt(1) == Mode::Fast);
    CHECK(modeFromInt(2) == Mode::Quality);
    CHECK(modeFromInt(3) == Mode::Off);
    CHECK(modeFromInt(-1) == Mode::Off);

    CHECK(effectiveMode(Mode::Quality, false, false) == Mode::Quality);
    // Low Power Mode and full color streams use Fast instead
    CHECK(effectiveMode(Mode::Quality, true, false) == Mode::Fast);
    CHECK(effectiveMode(Mode::Quality, false, true) == Mode::Fast);
    // Fast and Off stay what they are
    CHECK(effectiveMode(Mode::Fast, true, true) == Mode::Fast);
    CHECK(effectiveMode(Mode::Off, true, true) == Mode::Off);
}

static void testNeedsUpscale()
{
    CHECK(needsUpscale(1512, 982, 3024, 1964));
    CHECK(needsUpscale(1920, 1080, 3024, 1701));
    // The same size, or within 2 %, isn't worth it
    CHECK(!needsUpscale(3024, 1964, 3024, 1964));
    CHECK(!needsUpscale(1920, 1080, 1950, 1097));
    // Smaller on screen: the renderer shrinks it
    CHECK(!needsUpscale(3840, 2160, 3024, 1701));
    // A stretch wider than the frame on one side only
    CHECK(needsUpscale(1920, 1200, 2400, 1200));
    CHECK(!needsUpscale(0, 0, 100, 100));
}

static void testScaleFactor()
{
    const std::vector<float> two = { 2.0f };
    const std::vector<float> many = { 1.5f, 2.0f, 3.0f, 4.0f };

    // Exactly twice, as a 14" MacBook Pro's panel is for half its size
    CHECK(pickScaleFactor(1512, 982, 3024, 1964, two) == 2.0f);
    CHECK(pickScaleFactor(1512, 982, 3024, 1964, many) == 2.0f);
    // Just short of twice still takes 2x, within 2 %
    CHECK(pickScaleFactor(1512, 982, 2990, 1942, two) == 2.0f);
    // 1.575x: 2x would be shrunk again, so 1.5x if offered, else nothing
    CHECK(pickScaleFactor(1920, 1080, 3024, 1701, two) == 0.0f);
    CHECK(pickScaleFactor(1920, 1080, 3024, 1701, many) == 1.5f);
    // A big window over a small stream takes the largest that fits
    CHECK(pickScaleFactor(960, 540, 3840, 2160, many) == 4.0f);
    CHECK(pickScaleFactor(960, 540, 3000, 1688, many) == 3.0f);
    // Stretched: the smaller ratio decides
    CHECK(pickScaleFactor(1280, 800, 3024, 1890, many) == 2.0f);
    // Nothing to do, or nothing offered
    CHECK(pickScaleFactor(3024, 1964, 3024, 1964, many) == 0.0f);
    CHECK(pickScaleFactor(1512, 982, 3024, 1964, {}) == 0.0f);
    CHECK(pickScaleFactor(0, 0, 3024, 1964, many) == 0.0f);
    // 1x is never a scale factor
    CHECK(pickScaleFactor(1512, 982, 3024, 1964, { 1.0f }) == 0.0f);
}

static void testOverlayLine()
{
    Status status;
    CHECK(overlayLine(status).empty());

    status.note = "the video already fills its area";
    CHECK(overlayLine(status) == "Upscaling: none (the video already fills its area)\n");

    status.engine = Engine::SuperResolution;
    status.frameWidth = 1512;
    status.frameHeight = 982;
    status.outWidth = 3024;
    status.outHeight = 1964;
    status.ms = 2.14;
    status.note.clear();
    CHECK(overlayLine(status) == "Upscaling: VT super resolution 1512x982 -> 3024x1964 (2x), 2.1 ms\n");

    status.engine = Engine::Lanczos;
    status.frameWidth = 1920;
    status.frameHeight = 1080;
    status.outWidth = 3024;
    status.outHeight = 1701;
    status.ms = -1;
    status.note = "Quality: needs macOS 26";
    CHECK(overlayLine(status) == "Upscaling: Lanczos 1920x1080 -> 3024x1701 (1.6x) (Quality: needs macOS 26)\n");

    CHECK(std::string(engineName(Engine::MetalFx)) == "MetalFX");
    CHECK(std::string(engineName(Engine::Bilinear)) == "bilinear");
}

int main()
{
    testModes();
    testNeedsUpscale();
    testScaleFactor();
    testOverlayLine();

    if (s_Failures == 0) {
        std::printf("upscalerules_test: all passed\n");
    }
    return s_Failures == 0 ? 0 : 1;
}
