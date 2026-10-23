#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <vector>

// [fork] Reconnecting a stream with some of its settings changed, from the notch bar (Session's
// forkReconnect(), StreamProfiles::createReconnectSession()): what the new stream gets, and the frame
// rates and resolutions Quality offers. Free of Qt, so tests can build it alone
// (tests/fork/reconnectrules_test.cpp).
namespace ReconnectRules
{
    // Trackpad modes, as StreamingPreferences::TrackpadMode numbers them
    const int k_TrackpadMacMouse = 0;
    const int k_TrackpadWindowsTouchpad = 1;
    const int k_TrackpadMacTrackpad = 2;

    // The settings a reconnect can change, as the stream has them
    struct Settings {
        int width = 0;
        int height = 0;
        int fps = 0;
        int bitrateKbps = 0;
        bool hdr = false;
        bool yuv444 = false;
        int trackpadMode = k_TrackpadMacMouse;
        bool absoluteMouse = false;     // the mouse as a remote desktop's, not captured
    };

    // What a reconnect changes; 0 or nullopt keeps the stream's
    struct Overrides {
        int width = 0;
        int height = 0;
        int fps = 0;
        int bitrateKbps = 0;
        std::optional<bool> hdr;
        std::optional<bool> yuv444;
        std::optional<int> trackpadMode;
    };

    // What was chosen in the notch bar for the stream, which the stream after its reconnect keeps, as
    // it's the same stream to the user
    struct Choices {
        std::optional<bool> adaptive;   // adaptive bitrate, as Quality's switch left it
        int manualKbps = 0;             // the bitrate set by hand while not adapting; 0 for none
        std::optional<bool> saver;      // Stream Battery Saver switched by hand (PowerRules::Saver::manual())
        bool lowPowerMode = false;      // Low Power Mode then: a choice by hand holds until it changes
    };

    // The choices the next stream keeps: a bitrate set by hand only while not adapting, and none after
    // a reconnect at another bitrate
    inline Choices carried(Choices choices, const Overrides& overrides)
    {
        if (overrides.bitrateKbps > 0 || choices.adaptive.value_or(false)) {
            choices.manualKbps = 0;
        }
        return choices;
    }

    // The new stream's settings: the overrides over the stream's own, sizes even as the decoders want
    // (as StreamProfiles::createSession() rounds them). The bitrate stays the stream's own unless it's
    // overridden, whatever else changes: it's what the user chose for this stream.
    inline Settings apply(Settings settings, const Overrides& overrides)
    {
        if (overrides.width > 0 && overrides.height > 0) {
            settings.width = overrides.width & ~1;
            settings.height = overrides.height & ~1;
        }
        if (overrides.fps > 0) {
            settings.fps = overrides.fps;
        }
        if (overrides.bitrateKbps > 0) {
            settings.bitrateKbps = overrides.bitrateKbps;
        }
        if (overrides.hdr) {
            settings.hdr = *overrides.hdr;
        }
        if (overrides.yuv444) {
            settings.yuv444 = *overrides.yuv444;
        }
        if (overrides.trackpadMode) {
            settings.trackpadMode = *overrides.trackpadMode;
        }
        // The trackpad as a touchpad needs the game's mouse, as StreamProfiles::createSession() has it
        if (settings.trackpadMode != k_TrackpadMacMouse) {
            settings.absoluteMouse = false;
        }
        return settings;
    }

    // Whether switching the stream's trackpad mode takes a reconnect. Apollo sets its side up when
    // the stream starts: in Mac trackpad mode its touchpad takes only gestures and Windows' pointer
    // speed is held, for the whole stream. So into Mac trackpad reconnects unless the stream started
    // in it, and into Windows touchpad reconnects if it did. Mac mouse is the Mac's alone.
    inline bool trackpadNeedsReconnect(int startedMode, int nextMode)
    {
        if (nextMode == k_TrackpadMacTrackpad) {
            return startedMode != k_TrackpadMacTrackpad;
        }
        if (nextMode == k_TrackpadWindowsTouchpad) {
            return startedMode == k_TrackpadMacTrackpad;
        }
        return false;
    }

    // Quality's frame rates: 60, 90 and 120 up to the screen's highest, and the stream's own if it's
    // another
    inline std::vector<int> fpsChoices(int currentFps, int screenMaxFps)
    {
        std::vector<int> choices;
        for (int fps : { 60, 90, 120 }) {
            if (fps == 60 || fps <= screenMaxFps) {
                choices.push_back(fps);
            }
        }
        if (currentFps > 0 && std::find(choices.begin(), choices.end(), currentFps) == choices.end()) {
            choices.push_back(currentFps);
            std::sort(choices.begin(), choices.end());
        }
        return choices;
    }

    struct Size {
        int width = 0;
        int height = 0;

        bool operator==(const Size& other) const { return width == other.width && height == other.height; }
    };

    // Quality's resolutions: the stream's shape as large as the screen holds it, and at 5/6, 3/4, 2/3
    // and 1/2 of that, not below 720 lines, even, largest first, the stream's own among them
    inline std::vector<Size> resolutionChoices(Size current, Size screen)
    {
        std::vector<Size> choices;
        if (current.width <= 0 || current.height <= 0 || screen.width <= 0 || screen.height <= 0) {
            if (current.width > 0 && current.height > 0) {
                choices.push_back(current);
            }
            return choices;
        }
        double aspect = static_cast<double>(current.width) / current.height;
        // As wide as the screen, unless that's too tall for it
        double fullWidth = std::min(static_cast<double>(screen.width), screen.height * aspect);
        for (double scale : { 1.0, 5.0 / 6, 3.0 / 4, 2.0 / 3, 1.0 / 2 }) {
            int width = static_cast<int>(std::lround(fullWidth * scale)) & ~1;
            int height = static_cast<int>(std::lround(width / aspect)) & ~1;
            if (height < 720) {
                continue;
            }
            Size size { width, height };
            if (std::find(choices.begin(), choices.end(), size) == choices.end()) {
                choices.push_back(size);
            }
        }
        if (std::find(choices.begin(), choices.end(), current) == choices.end()) {
            choices.push_back(current);
        }
        std::sort(choices.begin(), choices.end(), [](const Size& a, const Size& b) {
            return a.height != b.height ? a.height > b.height : a.width > b.width;
        });
        return choices;
    }

    // A resolution in a notch bar action's int value, and back
    inline int packSize(Size size)
    {
        return static_cast<int>((static_cast<uint32_t>(size.width & 0x7fff) << 16) | static_cast<uint32_t>(size.height & 0xffff));
    }

    inline Size unpackSize(int value)
    {
        uint32_t bits = static_cast<uint32_t>(value);
        return Size { static_cast<int>(bits >> 16), static_cast<int>(bits & 0xffff) };
    }
}
