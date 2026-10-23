// Unit tests for app/fork/streamsettingsrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/streamsettingsrules_test.cpp
#include "fork/streamsettingsrules.h"

#include <cstdio>

using namespace StreamSettingsRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Profile global()
{
    return { { Key::Resolution, ReconnectRules::packSize({ 3024, 1890 }) },
             { Key::Fps, 120 },
             { Key::Hdr, 0 },
             { Key::Codec, k_CodecAuto },
             { Key::Yuv444, 0 },
             { Key::Bitrate, 20000 },
             { Key::Fill, 0 },
             { Key::Vsync, 0 },
             { Key::Pacing, 0 },
             { Key::Mouse, 0 },
             { Key::Trackpad, ReconnectRules::k_TrackpadMacTrackpad } };
}

static void testPresets()
{
    CHECK(presetOf({}) == Preset::None);
    CHECK(presetOf(office()) == Preset::Office);
    CHECK(presetOf(gaming()) == Preset::Gaming);
    // A preset and anything else is Custom
    Profile more = office();
    more[Key::Fps] = 60;
    CHECK(presetOf(more) == Preset::Custom);
    // As is a preset's key at another value
    Profile other = gaming();
    other[Key::Hdr] = 0;
    CHECK(presetOf(other) == Preset::Custom);
    // Gaming leaves V-Sync to Settings, as the dialog's preset does
    CHECK(gaming().count(Key::Vsync) == 0);
}

static void testEffective()
{
    Profile g = global();
    CHECK(effective({}, g, Key::Fps) == 120);
    CHECK(effective({ { Key::Fps, 60 } }, g, Key::Fps) == 60);
    // Unknown to both: 0
    CHECK(effective({}, {}, Key::Bitrate) == 0);
}

static void testChanged()
{
    Profile g = global();
    // Setting a value Settings already has changes nothing the stream gets
    CHECK(changed({}, { { Key::Fps, 120 } }, g).empty());
    // Office against Settings: codec, 4:4:4, mouse, V-Sync and pacing differ; HDR is off in both
    std::vector<Key> keys = changed({}, office(), g);
    CHECK((keys == std::vector<Key> { Key::Codec, Key::Yuv444, Key::Vsync, Key::Pacing, Key::Mouse }));
    // Back to Settings
    CHECK((changed(office(), {}, g) == keys));
}

static void testReconnects()
{
    Stream stream;
    stream.startedTrackpad = ReconnectRules::k_TrackpadMacTrackpad;
    stream.bitrateLive = true;
    stream.bitrateMaxKbps = 25000;

    for (Key key : { Key::Resolution, Key::Fps, Key::Hdr, Key::Codec, Key::Yuv444 }) {
        CHECK(alwaysReconnects(key, stream) && reconnects(key, 0, stream));
    }
    for (Key key : { Key::Fill, Key::Vsync, Key::Pacing, Key::Mouse, Key::Bitrate }) {
        CHECK(!alwaysReconnects(key, stream));
    }
    for (Key key : { Key::Fill, Key::Vsync, Key::Pacing, Key::Mouse }) {
        CHECK(!reconnects(key, 1, stream));
    }
    // The bitrate within Apollo's max, live
    CHECK(!reconnects(Key::Bitrate, 25000, stream));
    CHECK(reconnects(Key::Bitrate, 40000, stream));
    stream.bitrateLive = false;
    CHECK(reconnects(Key::Bitrate, 10000, stream));
    // Then every bitrate reconnects, so the row says so by its label alone
    CHECK(alwaysReconnects(Key::Bitrate, stream));
    // The trackpad as Control Center's
    CHECK(!reconnects(Key::Trackpad, ReconnectRules::k_TrackpadMacMouse, stream));
    CHECK(reconnects(Key::Trackpad, ReconnectRules::k_TrackpadWindowsTouchpad, stream));

    // Apply or Apply and Reconnect
    Profile g = global();
    stream.bitrateLive = true;
    CHECK(!anyReconnects(changed({}, { { Key::Vsync, 1 }, { Key::Bitrate, 15000 } }, g), { { Key::Vsync, 1 }, { Key::Bitrate, 15000 } }, g,
                         stream));
    CHECK(anyReconnects(changed({}, office(), g), office(), g, stream));
}

static void testMouse()
{
    Profile g = global();
    // Office's remote desktop mouse needs Mac mouse; Settings here have Mac trackpad
    CHECK(!absoluteMouse(office(), g));
    Profile mouse = office();
    mouse[Key::Trackpad] = ReconnectRules::k_TrackpadMacMouse;
    CHECK(absoluteMouse(mouse, g));
    CHECK(!absoluteMouse({}, g));
}

static void testToApply()
{
    Profile g = global();
    // The stream as it runs: at 60 after Quality's reconnect, and at the 40 Mb/s Settings gives 4:4:4
    Profile actual = g;
    actual[Key::Fps] = 60;
    actual[Key::Bitrate] = 40000;

    // Nothing chosen: nothing to apply, whatever the stream runs at
    CHECK(toApply({}, g, actual, {}).empty());
    // 120 chosen again: the stream runs at 60, so it applies
    CHECK((toApply({ { Key::Fps, 120 } }, g, actual, { Key::Fps }) == std::vector<Key> { Key::Fps }));
    // Global chosen for it does too, Settings having 120
    CHECK((toApply({}, g, actual, { Key::Fps }) == std::vector<Key> { Key::Fps }));
    // 60 chosen: the stream has it already
    CHECK(toApply({ { Key::Fps, 60 } }, g, actual, { Key::Fps }).empty());
    // 20 Mb/s chosen, which the panel's Global shows, while the stream runs at 40
    CHECK((toApply({ { Key::Bitrate, 20000 } }, g, actual, { Key::Bitrate }) == std::vector<Key> { Key::Bitrate }));

    // The mouse goes with the trackpad: Office's remote desktop mouse, the stream in Mac trackpad
    // without it; Mac mouse chosen brings the remote desktop's mouse
    Profile draft = office();
    draft[Key::Trackpad] = ReconnectRules::k_TrackpadMacMouse;
    Profile running = g;
    running[Key::Mouse] = 0;
    std::vector<Key> keys = toApply(draft, g, running, { Key::Trackpad });
    CHECK((keys == std::vector<Key> { Key::Mouse, Key::Trackpad }));
    // Office's mouse alone, with Mac trackpad: the stream can't have it, and doesn't
    CHECK(toApply(office(), g, running, { Key::Mouse }).empty());
}

static void testDifferences()
{
    CHECK(differences({}, {}).empty());
    std::set<Key> keys = differences(office(), gaming());
    // Gaming sets no V-Sync; both set the rest, HDR and 4:4:4 and the codec, mouse and pacing to others
    CHECK((keys == std::set<Key> { Key::Hdr, Key::Codec, Key::Yuv444, Key::Vsync, Key::Pacing, Key::Mouse }));
    CHECK((differences(office(), {}) == std::set<Key> { Key::Hdr, Key::Codec, Key::Yuv444, Key::Vsync, Key::Pacing, Key::Mouse }));
}

int main()
{
    testPresets();
    testEffective();
    testChanged();
    testReconnects();
    testMouse();
    testToApply();
    testDifferences();

    if (s_Failures == 0) {
        std::printf("streamsettingsrules: all tests passed\n");
        return 0;
    }
    std::printf("streamsettingsrules: %d failure(s)\n", s_Failures);
    return 1;
}
