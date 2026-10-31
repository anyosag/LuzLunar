#pragma once

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include "luzmic.h"

// [fork] This Mac's microphone on the PC, without CoreAudio, Opus or Qt (forkmic.* and
// mac/mic_mac.mm do the rest), so tests can build it alone: when a stream asks, when the Mac
// records, which microphone, when the stream's sound goes through voice processing, the frames'
// numbers and times, and the stream's sound on its way to the voice-processing engine.
namespace MicRules
{
    // The Opus encoder: 20 ms of mono 48 kHz speech a frame, its loss covered by the next one
    constexpr int k_BitrateBps = 28000;      // 24 to 32 kb/s; a frame never passes luzmic::k_max_opus
    constexpr int k_ExpectedLossPercent = 10;
    constexpr int k_RingFrames = 48000 * 60 / 1000; // 60 ms of the stream's sound waiting for the engine, at most

    // luzMic's value for the launch: "1" when the setting is on, the PC's Apollo offers it
    // (<LuzMic>1) and this isn't a multi-display stream's other window; "" otherwise
    std::string launchValue(bool setting, int hostVersion, bool helperWindow);

    // Where the default output plays
    enum class Transport { BuiltIn, Bluetooth, BluetoothLE, Usb, Hdmi, DisplayPort, AirPlay, Thunderbolt, Virtual, Aggregate, Unknown };
    enum class Output { Speakers, Headphones };

    // builtInHeadphones: the built-in output's data source is its headphone jack. Bluetooth and USB
    // are taken for headphones (AirPods, headsets); HDMI, DisplayPort and AirPlay for a display's or a
    // room's speakers; anything else for speakers, where an echo is the worse mistake
    Output classifyOutput(Transport transport, bool builtInHeadphones);

    // The stream's sound plays through the microphone's voice-processing engine (echo cancellation)
    // only on speakers; on headphones it stays with SDL's renderer, untouched
    bool voiceProcessedPlayback(bool streamAsked, Output output);

    struct Input {
        std::string uid;
        std::string name;
        bool builtIn = false;
    };

    // saved: the UID chosen in Settings ("" for the built-in microphone). That one while it's
    // there; else the built-in, even with AirPods on (recording from them makes their sound a phone
    // call's); else "", macOS's default input
    std::string chooseInput(const std::string& saved, const std::vector<Input>& inputs);

    // macOS's answer to recording
    enum class Access { Granted, Denied, Undetermined };

    // What Control Center's Microphone tile says
    enum class Status {
        Off,          // not asked: the setting is off (or a multi-display stream's other window)
        NeedsApollo,  // the PC's Apollo can't
        NoAccess,     // macOS said no: System Settings › Privacy & Security › Microphone
        NotOnPc,      // asked, but the PC hasn't said it's ready (no Steam microphone, no permission)
        Standby,      // ready, nothing on the PC records
        Live,         // recording for the PC
        Muted,        // the PC records, but this stream's microphone is muted
    };

    struct Situation {
        bool settingOn = false;
        bool asked = false;          // the stream launched with luzMic=1
        bool hostOffers = false;     // and the PC's Apollo said so (the feature flag)
        Access access = Access::Undetermined;
        bool hostReady = false;      // its STATE says ready
        bool hostRecording = false;  // and that something records
        bool muted = false;          // Control Center's Microphone off, for this stream
    };

    Status status(const Situation& situation);

    // Record now: asked, the PC records, not muted, and macOS hasn't said no (Undetermined asks)
    bool shouldCapture(const Situation& situation);

    // The frames' headers. Sequence numbers run on across recordings, so a late frame of the last
    // one never passes for one of the next; a recording's time starts at the clock and goes up 20 ms
    // a frame; its first frame says it's first.
    class FrameClock
    {
    public:
        void startRecording(std::uint32_t nowMs);
        luzmic::frame_t next();  // opus left empty

    private:
        std::uint16_t m_Sequence = 0;
        std::uint32_t m_TimeMs = 0;
        bool m_Start = true;
    };

    // The stream's sound in any of its layouts (2, 6 or 8 channels, interleaved as moonlight-common-c
    // has them: FL FR C LFE BL BR SL SR) as interleaved stereo; LFE left out
    void downmixToStereo(const float* in, int channels, int frames, float* out);

    // The stream's stereo sound between moonlight's audio thread and the engine's render callback.
    // At most capacity frames: the oldest go when more come, so the delay stays bounded; silence when
    // it runs dry.
    class PcmRing
    {
    public:
        explicit PcmRing(int capacityFrames);

        void push(const float* stereo, int frames);

        // Fills left and right (non-interleaved) with frames frames; returns how many came from the
        // ring, the rest being zeros
        int pull(float* left, float* right, int frames);

        int queued() const;
        void clear();

    private:
        mutable std::mutex m_Mutex;
        std::vector<float> m_Data;  // interleaved stereo
        int m_Capacity;
        int m_Read = 0;
        int m_Count = 0;
    };
}
