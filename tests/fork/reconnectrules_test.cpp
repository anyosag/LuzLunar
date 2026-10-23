// Unit tests for app/fork/reconnectrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/reconnectrules_test.cpp
#include "fork/reconnectrules.h"

#include <cstdio>

using namespace ReconnectRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Settings canvas()
{
    Settings settings;
    settings.width = 3024;
    settings.height = 1890;
    settings.fps = 120;
    settings.bitrateKbps = 20000;
    settings.hdr = true;
    return settings;
}

static void testApply()
{
    // Nothing changed: the same stream
    Settings same = apply(canvas(), Overrides());
    CHECK(same.width == 3024 && same.height == 1890 && same.fps == 120 && same.bitrateKbps == 20000 && same.hdr && !same.yuv444);

    // Reconnect at 60 fps: the bitrate stays the user's
    Overrides at60;
    at60.fps = 60;
    Settings s = apply(canvas(), at60);
    CHECK(s.fps == 60 && s.bitrateKbps == 20000 && s.width == 3024);

    // Another resolution, rounded down to even sizes
    Overrides smaller;
    smaller.width = 2269;
    smaller.height = 1419;
    s = apply(canvas(), smaller);
    CHECK(s.width == 2268 && s.height == 1418 && s.fps == 120);

    // Stream Battery Saver's reconnect at 10 Mb/s, and the switches
    Overrides saver;
    saver.bitrateKbps = 10000;
    saver.hdr = false;
    s = apply(canvas(), saver);
    CHECK(s.bitrateKbps == 10000 && !s.hdr);
}

static void testFps()
{
    CHECK((fpsChoices(120, 120) == std::vector<int> { 60, 90, 120 }));
    // A 60 Hz screen: 60 alone, and the stream's own if it asked for more
    CHECK((fpsChoices(60, 60) == std::vector<int> { 60 }));
    CHECK((fpsChoices(120, 60) == std::vector<int> { 60, 120 }));
    CHECK((fpsChoices(100, 120) == std::vector<int> { 60, 90, 100, 120 }));
}

static void testResolutions()
{
    // A 14" MacBook Pro's area below the notch, streamed at it
    std::vector<Size> choices = resolutionChoices({ 3024, 1890 }, { 3024, 1890 });
    CHECK(choices.size() == 5);
    CHECK((choices[0] == Size { 3024, 1890 }));
    CHECK((choices[1] == Size { 2520, 1574 }));
    CHECK((choices[2] == Size { 2268, 1418 }));
    CHECK((choices[3] == Size { 2016, 1260 }));
    CHECK((choices[4] == Size { 1512, 944 }));

    // A 16:9 stream on it: the stream's shape, never wider than the screen
    choices = resolutionChoices({ 2560, 1440 }, { 3024, 1890 });
    CHECK((choices[0] == Size { 3024, 1700 }));     // as wide as the screen; 1890 lines would be 3360 wide
    CHECK(std::find(choices.begin(), choices.end(), Size { 2560, 1440 }) != choices.end());
    for (const Size& size : choices) {
        CHECK(size.width <= 3024 && size.height >= 720 && size.width % 2 == 0 && size.height % 2 == 0);
    }

    // Unknown screen: the stream's own alone
    CHECK((resolutionChoices({ 1920, 1080 }, { 0, 0 }) == std::vector<Size> { { 1920, 1080 } }));
}

static void testPacking()
{
    for (Size size : { Size { 3024, 1890 }, Size { 7680, 4320 }, Size { 1280, 720 } }) {
        CHECK(unpackSize(packSize(size)) == size);
        CHECK(packSize(size) > 0);
    }
}

int main()
{
    testApply();
    testFps();
    testResolutions();
    testPacking();

    if (s_Failures == 0) {
        std::printf("reconnectrules: all tests passed\n");
        return 0;
    }
    std::printf("reconnectrules: %d failure(s)\n", s_Failures);
    return 1;
}
