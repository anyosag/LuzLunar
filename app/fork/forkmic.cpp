#include "forkmic.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <QReadLocker>

#include <SDL.h>
#include <opus.h>

#include "backend/nvcomputer.h"
#include "forkevents.h"
#include "forkhostmessages.h"
#include "forkpreferences.h"
#include "luzmic.h"
#include "mac/mic_mac.h"
#include "streaming/audio/renderers/renderer.h"

namespace
{
    // Read on the main thread before the stream (prepare())
    std::mutex s_Mutex;
    std::string s_LaunchValue;          // "1" when the next launch asks
    bool s_Setting = false;
    bool s_HostOffers = false;
    std::string s_SavedInput;           // Settings' microphone, "" for the built-in
    Uint32 s_EventType = 0;

    // The stream's, under s_Mutex
    bool s_Active = false;              // between connectionStarting() and connectionStopped(), for a stream that asked
    MicRules::Situation s_Situation;
    MicRules::Output s_Output = MicRules::Output::Speakers;
    bool s_RendererLive = false;        // the renderer below exists: the stream plays through the engine
    bool s_PlaybackBroken = false;      // the engine couldn't play it: SDL does, for the rest of the stream
    bool s_Capturing = false;
    bool s_AccessAsked = false;
    MicRules::Status s_PostedStatus = MicRules::Status::Off;
    std::shared_ptr<MicRules::PcmRing> s_Ring;
    std::unique_ptr<ForkMicMac::Engine> s_Engine;
    std::atomic<bool> s_WantRenderer { false };

    // The encoder, on the engine's audio thread
    std::mutex s_EncoderMutex;
    OpusEncoder* s_Encoder = nullptr;
    MicRules::FrameClock s_Clock;

    std::uint32_t nowMs()
    {
        using namespace std::chrono;
        return static_cast<std::uint32_t>(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
    }

    const char* statusName(MicRules::Status status)
    {
        switch (status) {
        case MicRules::Status::Off: return "off";
        case MicRules::Status::NeedsApollo: return "needs Apollo";
        case MicRules::Status::NoAccess: return "no access in macOS";
        case MicRules::Status::NotOnPc: return "not ready on the PC";
        case MicRules::Status::Standby: return "standing by";
        case MicRules::Status::Live: return "live";
        case MicRules::Status::Muted: return "muted";
        }
        return "?";
    }

    // Each 20 ms of the microphone, on the engine's audio thread
    void sendFrame(const float* samples)
    {
        std::lock_guard<std::mutex> lock(s_EncoderMutex);
        if (s_Encoder == nullptr) {
            return;
        }
        unsigned char opus[luzmic::k_max_opus];
        int size = opus_encode_float(s_Encoder, samples, luzmic::k_frame_samples, opus, static_cast<opus_int32>(luzmic::k_max_opus));
        if (size <= 0) {
            return;
        }
        luzmic::frame_t frame = s_Clock.next();
        frame.opus = opus;
        frame.opus_size = static_cast<std::size_t>(size);
        std::vector<std::uint8_t> packet = luzmic::encode_frame(frame);
        if (!packet.empty()) {
            LiSendForkInputPacket(packet.data(), static_cast<uint32_t>(packet.size()), luzmic::k_channel, false);
        }
    }

    // What applyLocked() leaves for after the lock: SDL's event watchers run inside SDL_PushEvent(),
    // and macOS may answer at once
    struct After {
        bool askAccess = false;
        bool statusChanged = false;
    };

    void finish(const After& after);

    // Under s_Mutex: the engine as things are now
    After applyLocked()
    {
        After after;
        MicRules::Status status = MicRules::status(s_Situation);
        if (status != s_PostedStatus) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: %s", statusName(status));
            s_PostedStatus = status;
            after.statusChanged = true;
        }
        if (!s_Active || !s_Engine) {
            return after;
        }

        bool capture = MicRules::shouldCapture(s_Situation);
        if (capture && s_Situation.access == MicRules::Access::Undetermined) {
            // macOS asks the user; recording waits for the answer
            after.askAccess = !s_AccessAsked;
            s_AccessAsked = true;
            capture = false;
        }
        if (capture && !s_Capturing) {
            std::lock_guard<std::mutex> lock(s_EncoderMutex);
            s_Clock.startRecording(nowMs());
            if (s_Encoder != nullptr) {
                opus_encoder_ctl(s_Encoder, OPUS_RESET_STATE);
            }
        }
        s_Capturing = capture;
        std::string input = capture ? MicRules::chooseInput(s_SavedInput, ForkMicMac::inputs()) : std::string();
        s_Engine->configure(s_RendererLive, capture, input);
        return after;
    }

    void apply()
    {
        After after;
        {
            std::lock_guard<std::mutex> lock(s_Mutex);
            after = applyLocked();
        }
        finish(after);
    }

    void finish(const After& after)
    {
        if (after.statusChanged && s_EventType != 0) {
            SDL_Event event = {};
            event.type = s_EventType;
            SDL_PushEvent(&event);
        }
        if (after.askAccess) {
            ForkMicMac::requestAccess([](bool granted) {
                {
                    std::lock_guard<std::mutex> lock(s_Mutex);
                    s_Situation.access = granted ? MicRules::Access::Granted : MicRules::Access::Denied;
                }
                apply();
            });
        }
    }

    // Apollo's STATE, on moonlight-common-c's control receive thread
    void stateArrived(const std::uint8_t* payload, int length)
    {
        luzmic::state_t state;
        if (length < 0 || !luzmic::decode_state(payload, static_cast<std::size_t>(length), state)) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(s_Mutex);
            if (!s_Active) {
                return;
            }
            s_Situation.hostReady = state.ready();
            s_Situation.hostRecording = state.recording();
        }
        apply();
    }

    // Headphones came or went, on a CoreAudio poll's queue
    void outputChanged(MicRules::Output output)
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!s_Active) {
            return;
        }
        s_Output = output;
        s_WantRenderer = !s_PlaybackBroken && MicRules::voiceProcessedPlayback(true, output);
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: this Mac plays on %s",
                    output == MicRules::Output::Speakers ? "speakers: the stream's sound goes through the microphone's engine" :
                                                           "headphones: the stream's sound stays untouched");
    }

    void setRendererLive(bool live)
    {
        After after;
        {
            std::lock_guard<std::mutex> lock(s_Mutex);
            s_RendererLive = live;
            after = applyLocked();
        }
        finish(after);
    }

    // The stream's sound, downmixed to stereo, into the ring the engine plays from
    class MicEngineAudioRenderer : public IAudioRenderer
    {
    public:
        explicit MicEngineAudioRenderer(std::shared_ptr<MicRules::PcmRing> ring)
            : m_Ring(std::move(ring))
        {
        }

        ~MicEngineAudioRenderer() override
        {
            if (m_Live) {
                setRendererLive(false);
                m_Ring->clear();
            }
        }

        bool prepareForPlayback(const OPUS_MULTISTREAM_CONFIGURATION* opusConfig) override
        {
            if (opusConfig == nullptr || opusConfig->sampleRate != luzmic::k_sample_rate || opusConfig->channelCount < 1 ||
                opusConfig->channelCount > 8) {
                return false;
            }
            m_Channels = opusConfig->channelCount;
            m_Buffer.resize(static_cast<size_t>(m_Channels) * static_cast<size_t>(std::max(opusConfig->samplesPerFrame, 1)));
            m_Live = true;
            setRendererLive(true);
            return true;
        }

        void* getAudioBuffer(int* size) override
        {
            size_t floats = static_cast<size_t>(std::max(*size, 0)) / sizeof(float);
            if (m_Buffer.size() < floats) {
                m_Buffer.resize(floats);
            }
            return m_Buffer.data();
        }

        bool submitAudio(int bytesWritten) override
        {
            int frames = bytesWritten / static_cast<int>(sizeof(float) * static_cast<size_t>(m_Channels));
            if (frames <= 0) {
                return true;
            }
            if (m_Stereo.size() < static_cast<size_t>(frames) * 2) {
                m_Stereo.resize(static_cast<size_t>(frames) * 2);
            }
            MicRules::downmixToStereo(m_Buffer.data(), m_Channels, frames, m_Stereo.data());
            m_Ring->push(m_Stereo.data(), frames);
            return true;
        }

        AudioFormat getAudioBufferFormat() override
        {
            return AudioFormat::Float32NE;
        }

    private:
        std::shared_ptr<MicRules::PcmRing> m_Ring;
        int m_Channels = 2;
        bool m_Live = false;
        std::vector<float> m_Buffer;
        std::vector<float> m_Stereo;
    };
}

namespace ForkMic
{

void prepare(NvComputer* computer, bool helperWindow)
{
    if (s_EventType == 0) {
        // On the main thread before another uses it
        s_EventType = ForkEvents::registerType();
    }

    int hostVersion;
    {
        QReadLocker lock(&computer->lock);
        hostVersion = computer->apolloMic;
    }
    ForkPreferences* prefs = ForkPreferences::get();
    std::lock_guard<std::mutex> lock(s_Mutex);
    s_Setting = prefs->macMicrophone();
    s_SavedInput = prefs->macMicrophoneDevice().toStdString();
    s_HostOffers = hostVersion >= luzmic::k_serverinfo_version;
    s_LaunchValue = MicRules::launchValue(s_Setting, hostVersion, helperWindow);
    if (s_Setting && !s_HostOffers && !helperWindow) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: the PC's Apollo can't take this Mac's microphone");
    }
}

QString launchArgument()
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    if (s_LaunchValue.empty()) {
        return QString();
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: lending it to the PC while an app there records (luzMic=1)");
    return QStringLiteral("&luzMic=") + QString::fromStdString(s_LaunchValue);
}

void connectionStarting()
{
    bool asked;
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        asked = !s_LaunchValue.empty();
        s_Situation = MicRules::Situation();
        s_Situation.settingOn = s_Setting;
        s_Situation.asked = asked;
        s_Situation.hostOffers = s_HostOffers;
        s_Situation.access = ForkMicMac::access();
        s_PostedStatus = MicRules::status(s_Situation);
        s_Capturing = false;
        s_AccessAsked = false;
        s_PlaybackBroken = false;
        s_RendererLive = false;
        s_Active = asked;
        if (asked) {
            s_Output = ForkMicMac::currentOutput();
            s_Ring = std::make_shared<MicRules::PcmRing>(MicRules::k_RingFrames);
            s_Engine = std::make_unique<ForkMicMac::Engine>(s_Ring, sendFrame);
        }
        s_WantRenderer = asked && MicRules::voiceProcessedPlayback(true, s_Output);
    }
    if (!asked) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(s_EncoderMutex);
        if (s_Encoder != nullptr) {
            // A connection that never started is never stopped
            opus_encoder_destroy(s_Encoder);
        }
        int error = OPUS_OK;
        s_Encoder = opus_encoder_create(luzmic::k_sample_rate, 1, OPUS_APPLICATION_VOIP, &error);
        if (s_Encoder != nullptr) {
            opus_encoder_ctl(s_Encoder, OPUS_SET_BITRATE(MicRules::k_BitrateBps));
            opus_encoder_ctl(s_Encoder, OPUS_SET_VBR(1));
            opus_encoder_ctl(s_Encoder, OPUS_SET_VBR_CONSTRAINT(1));
            opus_encoder_ctl(s_Encoder, OPUS_SET_INBAND_FEC(1));
            opus_encoder_ctl(s_Encoder, OPUS_SET_PACKET_LOSS_PERC(MicRules::k_ExpectedLossPercent));
            opus_encoder_ctl(s_Encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
            opus_encoder_ctl(s_Encoder, OPUS_SET_COMPLEXITY(8));
        }
        else {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: no Opus encoder (%d)", error);
        }
    }
    ForkHostMessages::setHandler(luzmic::k_type_state, stateArrived);
    ForkMicMac::watchOutput(outputChanged);
}

void connectionStopped()
{
    ForkHostMessages::setHandler(luzmic::k_type_state, ForkHostMessages::Handler());
    ForkMicMac::watchOutput(std::function<void(MicRules::Output)>());

    std::unique_ptr<ForkMicMac::Engine> engine;
    After after;
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!s_Active && !s_Engine) {
            return;
        }
        s_Active = false;
        s_WantRenderer = false;
        s_Capturing = false;
        s_Situation = MicRules::Situation();
        after = applyLocked();
        engine = std::move(s_Engine);
        s_Ring.reset();
    }
    finish(after);
    // Stops it, and waits for its audio thread, which encodes
    engine.reset();

    std::lock_guard<std::mutex> lock(s_EncoderMutex);
    if (s_Encoder != nullptr) {
        opus_encoder_destroy(s_Encoder);
        s_Encoder = nullptr;
    }
}

IAudioRenderer* createAudioRenderer(const OPUS_MULTISTREAM_CONFIGURATION* opusConfig)
{
    std::shared_ptr<MicRules::PcmRing> ring;
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!s_Active || !s_WantRenderer || s_RendererLive || !s_Ring) {
            return nullptr;
        }
        ring = s_Ring;
    }
    auto* renderer = new MicEngineAudioRenderer(ring);
    if (renderer->prepareForPlayback(opusConfig)) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: the stream's sound plays through its engine, for echo cancellation");
        return renderer;
    }
    delete renderer;
    return nullptr;
}

bool rendererStale(IAudioRenderer* renderer)
{
    bool ours = dynamic_cast<MicEngineAudioRenderer*>(renderer) != nullptr;
    if (ours && s_Engine && s_Engine->playbackFailed()) {
        // SDL plays the stream from now on
        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!s_PlaybackBroken) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: its engine can't play the stream; SDL does, without echo cancellation");
        }
        s_PlaybackBroken = true;
        s_WantRenderer = false;
        return true;
    }
    return ours != s_WantRenderer.load();
}

MicRules::Status status()
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    return MicRules::status(s_Situation);
}

bool muted()
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    return s_Situation.muted;
}

void setMuted(bool muted)
{
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!s_Active || s_Situation.muted == muted) {
            return;
        }
        s_Situation.muted = muted;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: %s for this stream", muted ? "muted" : "unmuted");
    }
    apply();
}

bool live()
{
    return status() == MicRules::Status::Live;
}

bool isStatusEvent(const SDL_Event& event)
{
    return s_EventType != 0 && event.type == s_EventType;
}

}
