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

static void testCarried()
{
    Choices choices;
    choices.adaptive = false;
    choices.manualKbps = 15000;
    choices.saver = false;
    choices.lowPowerMode = true;

    // Another frame rate keeps all of it
    Overrides fps;
    fps.fps = 60;
    Choices kept = carried(choices, fps);
    CHECK(kept.adaptive == std::optional<bool>(false) && kept.manualKbps == 15000);
    CHECK(kept.saver == std::optional<bool>(false) && kept.lowPowerMode);

    // Another bitrate replaces the one set by hand
    Overrides bitrate;
    bitrate.bitrateKbps = 10000;
    CHECK(carried(choices, bitrate).manualKbps == 0);
    CHECK(carried(choices, bitrate).adaptive == std::optional<bool>(false));

    // Adapting, no bitrate by hand
    choices.adaptive = true;
    CHECK(carried(choices, fps).manualKbps == 0);

    // The remote desktop's mouse a touchpad mode took, for Mac mouse to give back after the reconnect
    choices.absoluteBeforeTouchpad = true;
    CHECK(carried(choices, bitrate).absoluteBeforeTouchpad);
}

static void testTrackpad()
{
    // Started in Mac trackpad: Apollo's touchpad takes only gestures for the whole stream
    CHECK(!trackpadNeedsReconnect(k_TrackpadMacTrackpad, k_TrackpadMacTrackpad));
    CHECK(trackpadNeedsReconnect(k_TrackpadMacTrackpad, k_TrackpadWindowsTouchpad));
    CHECK(!trackpadNeedsReconnect(k_TrackpadMacTrackpad, k_TrackpadMacMouse));
    // Started otherwise: Mac trackpad needs Apollo's side set up at the start
    CHECK(trackpadNeedsReconnect(k_TrackpadWindowsTouchpad, k_TrackpadMacTrackpad));
    CHECK(!trackpadNeedsReconnect(k_TrackpadWindowsTouchpad, k_TrackpadMacMouse));
    CHECK(trackpadNeedsReconnect(k_TrackpadMacMouse, k_TrackpadMacTrackpad));
    CHECK(!trackpadNeedsReconnect(k_TrackpadMacMouse, k_TrackpadWindowsTouchpad));

    // A reconnect into a touchpad mode takes the game's mouse
    Settings settings;
    settings.trackpadMode = k_TrackpadMacMouse;
    settings.absoluteMouse = true;
    Overrides overrides;
    overrides.trackpadMode = k_TrackpadWindowsTouchpad;
    Settings next = apply(settings, overrides);
    CHECK(next.trackpadMode == k_TrackpadWindowsTouchpad && !next.absoluteMouse);
    // Mac mouse keeps the remote desktop's
    CHECK(apply(settings, Overrides()).absoluteMouse);
}

int main()
{
    testApply();
    testFps();
    testResolutions();
    testPacking();
    testCarried();
    testTrackpad();

    if (s_Failures == 0) {
        std::printf("reconnectrules: all tests passed\n");
        return 0;
    }
    std::printf("reconnectrules: %d failure(s)\n", s_Failures);
    return 1;
}
