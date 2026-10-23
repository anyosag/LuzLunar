#pragma once

#include <map>
#include <vector>

#include "reconnectrules.h"

// [fork] The notch bar's Stream Settings: a draft of the app's stream profile, changed in a panel
// during the stream and applied to it or saved for the next. These are its rules: what each setting
// is now, the presets, what changed, and which changes reconnect the stream. Free of Qt, so tests
// can build it alone (tests/fork/streamsettingsrules_test.cpp); ForkStreamSettings (streamsettings.h)
// holds the draft and names things.
namespace StreamSettingsRules
{
    // A profile's settings, as StreamProfiles stores them (streamprofiles.cpp). The resolution is
    // one setting, its width and height packed (ReconnectRules::packSize()); the aspect ratio
    // isn't stored, it only picks sizes.
    enum class Key {
        Resolution,
        Fps,
        Hdr,
        Codec,          // StreamingPreferences::VideoCodecConfig
        Yuv444,
        Bitrate,        // kbps
        Fill,           // fullscreenStretch
        Vsync,
        Pacing,
        Mouse,          // absoluteMouseMode: the remote desktop's mouse
        Trackpad,       // StreamingPreferences::TrackpadMode
    };

    inline const std::vector<Key>& keys()
    {
        static const std::vector<Key> all = { Key::Resolution, Key::Fps, Key::Hdr, Key::Codec, Key::Yuv444, Key::Bitrate,
                                              Key::Fill, Key::Vsync, Key::Pacing, Key::Mouse, Key::Trackpad };
        return all;
    }

    // The settings a profile sets; the others follow Settings
    using Profile = std::map<Key, int>;

    // StreamingPreferences::VideoCodecConfig's values the presets use
    const int k_CodecAuto = 0;
    const int k_CodecHevc = 2;
    const int k_CodecAv1 = 4;

    // StreamProfileDialog.qml's presets
    inline const Profile& office()
    {
        static const Profile profile = { { Key::Codec, k_CodecHevc }, { Key::Yuv444, 1 }, { Key::Hdr, 0 },
                                         { Key::Mouse, 1 },          { Key::Vsync, 1 },  { Key::Pacing, 1 } };
        return profile;
    }

    inline const Profile& gaming()
    {
        static const Profile profile = { { Key::Codec, k_CodecAv1 }, { Key::Hdr, 1 }, { Key::Yuv444, 0 },
                                         { Key::Mouse, 0 },         { Key::Pacing, 0 } };
        return profile;
    }

    // The preset cards: lit while the profile is exactly a preset; Custom for anything else set
    enum class Preset { None, Office, Gaming, Custom };

    inline Preset presetOf(const Profile& profile)
    {
        if (profile.empty()) {
            return Preset::None;
        }
        return profile == office() ? Preset::Office : profile == gaming() ? Preset::Gaming : Preset::Custom;
    }

    // A setting as the stream gets it: the profile's, else Settings'
    inline int effective(const Profile& profile, const Profile& global, Key key)
    {
        auto it = profile.find(key);
        if (it != profile.end()) {
            return it->second;
        }
        auto fallback = global.find(key);
        return fallback != global.end() ? fallback->second : 0;
    }

    // The settings whose effective value differs between two profiles, in keys()' order
    inline std::vector<Key> changed(const Profile& from, const Profile& to, const Profile& global)
    {
        std::vector<Key> result;
        for (Key key : keys()) {
            if (effective(from, global, key) != effective(to, global, key)) {
                result.push_back(key);
            }
        }
        return result;
    }

    // What the stream can do now, for which changes reconnect it
    struct Stream {
        int startedTrackpad = ReconnectRules::k_TrackpadMacMouse; // the mode Apollo set its side up for
        bool bitrateLive = false;       // the PC changes the bitrate during the stream
        int bitrateMaxKbps = 0;         // up to this (Apollo's max: the stream's launch bitrate)
    };

    // Settings that always reconnect: the picture and the video take a new stream
    inline bool alwaysReconnects(Key key)
    {
        return key == Key::Resolution || key == Key::Fps || key == Key::Hdr || key == Key::Codec || key == Key::Yuv444;
    }

    // Whether a setting at this value takes a reconnect. Fill, V-Sync, frame pacing and the mouse apply
    // in the stream (V-Sync and frame pacing with a new picture); the bitrate within what the PC takes
    // live; the trackpad as Control Center's does.
    inline bool reconnects(Key key, int value, const Stream& stream)
    {
        if (alwaysReconnects(key)) {
            return true;
        }
        if (key == Key::Bitrate) {
            return !stream.bitrateLive || value > stream.bitrateMaxKbps;
        }
        if (key == Key::Trackpad) {
            return ReconnectRules::trackpadNeedsReconnect(stream.startedTrackpad, value);
        }
        return false;
    }

    // Whether applying these changes reconnects: "Apply and Reconnect" rather than "Apply"
    inline bool anyReconnects(const std::vector<Key>& changes, const Profile& draft, const Profile& global, const Stream& stream)
    {
        for (Key key : changes) {
            if (reconnects(key, effective(draft, global, key), stream)) {
                return true;
            }
        }
        return false;
    }

    // The remote desktop's mouse goes only with Mac mouse, as StreamProfiles::createSession() has it
    inline bool absoluteMouse(const Profile& profile, const Profile& global)
    {
        return effective(profile, global, Key::Mouse) != 0 &&
               effective(profile, global, Key::Trackpad) == ReconnectRules::k_TrackpadMacMouse;
    }
}
