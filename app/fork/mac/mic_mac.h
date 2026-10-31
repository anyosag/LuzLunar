#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "../micrules.h"

// [fork] This Mac's microphone and, on speakers, the stream's sound, in one AVAudioEngine, so voice
// processing cancels the echo of what it plays (forkmic.*). The microphone is live only while
// recording is asked for: playback alone never touches the input.
namespace ForkMicMac
{
    // Each 20 ms of the microphone, as luzmic::k_frame_samples mono samples at 48 kHz, on the
    // engine's audio thread
    using FrameSink = std::function<void(const float* samples)>;

    class Engine
    {
    public:
        // ring: the stream's sound, for when it plays through this engine
        Engine(std::shared_ptr<MicRules::PcmRing> ring, FrameSink sink);
        ~Engine();

        Engine(const Engine&) = delete;
        Engine& operator=(const Engine&) = delete;

        // What the engine does; it rebuilds itself on its own queue when this changes. playback:
        // the stream's sound through it (speakers); capture: record, from inputUid ("" for
        // macOS's default), with voice processing when it plays the stream too. Any thread.
        void configure(bool playback, bool capture, const std::string& inputUid);

        // The last configuration that asked for playback failed to start: SDL plays the stream
        bool playbackFailed() const;

    private:
        struct Impl;
        std::unique_ptr<Impl> m;
    };

    // Where the default output plays now
    MicRules::Output currentOutput();

    // Polls the default output every second on a queue of its own and calls changed with it when
    // it changes. An empty function stops.
    void watchOutput(std::function<void(MicRules::Output)> changed);

    // The Mac's microphones, the built-in marked
    std::vector<MicRules::Input> inputs();

    MicRules::Access access();

    // Asks macOS (once: it remembers); done on an arbitrary thread
    void requestAccess(std::function<void(bool granted)> done);
}
