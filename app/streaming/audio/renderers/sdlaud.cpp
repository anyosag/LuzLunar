#include "sdl.h"

#include <Limelight.h>

// [fork] moonlight-common-c's FEC and out-of-order counts, beside ours
static std::string forkRtpLine()
{
    RTP_AUDIO_STATS stats = {};
    LiGetRTPAudioStats(&stats);
    return AudioHealth::Monitor::rtpLine(stats.packetCountAudio, stats.packetCountFec, stats.packetCountFecRecovered,
                                         stats.packetCountFecFailed, stats.packetCountOOS);
}

// [fork] A steady clock in ms, finer than SDL_GetTicks()
static double forkNowMs()
{
    return static_cast<double>(SDL_GetPerformanceCounter()) * 1000.0 / static_cast<double>(SDL_GetPerformanceFrequency());
}

SdlAudioRenderer::SdlAudioRenderer()
    : m_AudioDevice(0),
      m_AudioBuffer(nullptr)
{
    SDL_assert(!SDL_WasInit(SDL_INIT_AUDIO));

    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "SDL_InitSubSystem(SDL_INIT_AUDIO) failed: %s",
                     SDL_GetError());
        SDL_assert(SDL_WasInit(SDL_INIT_AUDIO));
    }
}

bool SdlAudioRenderer::prepareForPlayback(const OPUS_MULTISTREAM_CONFIGURATION* opusConfig)
{
    SDL_AudioSpec want, have;

    SDL_zero(want);
    want.freq = opusConfig->sampleRate;
    want.format = AUDIO_F32SYS;
    want.channels = opusConfig->channelCount;

    // On PulseAudio systems, setting a value too small can cause underruns for other
    // applications sharing this output device. We impose a floor of 480 samples (10 ms)
    // to mitigate this issue. Otherwise, we will buffer up to 3 frames of audio which
    // is 15 ms at regular 5 ms frames and 30 ms at 10 ms frames for slow connections.
    // The buffering helps avoid audio underruns due to network jitter.
    want.samples = SDL_max(480, opusConfig->samplesPerFrame * 3);

    m_FrameDurationMs = opusConfig->samplesPerFrame / (opusConfig->sampleRate / 1000);
    m_FrameSize = opusConfig->samplesPerFrame *
                  opusConfig->channelCount *
                  getAudioBufferSampleSize();

    m_AudioDevice = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (m_AudioDevice == 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Failed to open audio device: %s",
                     SDL_GetError());
        return false;
    }

    // [fork] Room for one more sample of every channel: the pacer may play a packet's last one twice
    m_ForkFrameBytes = opusConfig->channelCount * getAudioBufferSampleSize();
    m_AudioBuffer = SDL_malloc(m_FrameSize + m_ForkFrameBytes);
    if (m_AudioBuffer == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Failed to allocate audio buffer");
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Desired audio buffer: %u samples (%u bytes)",
                want.samples,
                want.samples * want.channels * getAudioBufferSampleSize());

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Obtained audio buffer: %u samples (%u bytes)",
                have.samples,
                have.size);

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "SDL audio driver: %s",
                SDL_GetCurrentAudioDriver());

    // [fork] A gap between packets longer than the device's buffer can leave the speakers with nothing
    double deviceMs = have.freq > 0 ? have.samples * 1000.0 / have.freq : 15.0;
    m_ForkHealth = std::make_unique<AudioHealth::Monitor>(deviceMs);
    m_ForkBytesPerMs = m_FrameDurationMs > 0 ? static_cast<double>(m_FrameSize) / m_FrameDurationMs : 0;

    // [fork] Playback starts once the pacer has its reserve (submitAudio()), not now
    m_ForkPacer = std::make_unique<AudioPacing::Pacer>(have.freq > 0 ? have.freq : opusConfig->sampleRate);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Audio (SDL): plays from a %.0f ms reserve, drift corrected, throws a packet away past %.0f ms",
                AudioPacing::Settings().targetMs, AudioPacing::Settings().capMs);

    return true;
}

SdlAudioRenderer::~SdlAudioRenderer()
{
    // [fork] What the stream's sound went through, for telling a crackle's cause
    if (m_ForkHealth) {
        std::string summary = m_ForkHealth->summary();
        if (!summary.empty()) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Audio (SDL), the whole stream: %s; %s", summary.c_str(), forkRtpLine().c_str());
        }
    }

    if (m_AudioDevice != 0) {
        // Stop playback
        SDL_PauseAudioDevice(m_AudioDevice, 1);
        SDL_CloseAudioDevice(m_AudioDevice);
    }

    if (m_AudioBuffer != nullptr) {
        SDL_free(m_AudioBuffer);
    }

    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    SDL_assert(!SDL_WasInit(SDL_INIT_AUDIO));
}

void* SdlAudioRenderer::getAudioBuffer(int*)
{
    return m_AudioBuffer;
}

bool SdlAudioRenderer::submitAudio(int bytesWritten)
{
    if (bytesWritten == 0) {
        // Nothing to do
        return true;
    }

    // [fork] The packet, with what's still waiting for the device
    double forkNow = forkNowMs();
    double forkQueuedMs = m_ForkBytesPerMs > 0 ? SDL_GetQueuedAudioSize(m_AudioDevice) / m_ForkBytesPerMs : 0;
    if (m_ForkHealth) {
        m_ForkHealth->packet(forkNow, forkQueuedMs);
    }

    // Don't queue if there's already more than 30 ms of audio data waiting
    // in Moonlight's audio queue.
    if (LiGetPendingAudioDuration() > 30) {
        if (m_ForkHealth) {
            m_ForkHealth->thrownAway(); // [fork]
        }
        return true;
    }

    // Our device may enter a permanent error status upon removal, so we need
    // to recreate the audio device to pick up the new default audio device.
    if (SDL_GetAudioDeviceStatus(m_AudioDevice) == SDL_AUDIO_STOPPED) {
        return false;
    }

    // [fork] Upstream held this (the decoder's) thread while SDL's queue passed 50 ms, so
    // moonlight-common-c's queue passed 30 ms and packets were thrown away above; and played each
    // packet as it came, with no reserve, so a late one was a tick. The pacer keeps a reserve,
    // holds it against the clocks' drift, and throws a packet away only past its cap
    // (audiopacing.h); this thread is never held
    int frameBytes = m_ForkFrameBytes > 0 ? m_ForkFrameBytes : 1;
    AudioPacing::Decision pace;
    if (m_ForkPacer) {
        pace = m_ForkPacer->packet(forkNow, forkQueuedMs, bytesWritten / frameBytes);
    }
    if (pace.drop) {
        if (m_ForkHealth) {
            m_ForkHealth->thrownAway();
        }
        return true;
    }
    if (pace.hold) {
        // The PC paused (silence) and everything played: build the reserve again
        SDL_PauseAudioDevice(m_AudioDevice, 1);
    }
    if (pace.adjust < 0 && bytesWritten >= 2 * frameBytes) {
        bytesWritten -= frameBytes;     // the speakers run behind: leave the last frame out
    }
    else if (pace.adjust > 0 && bytesWritten >= frameBytes) {
        // The speakers run ahead: play the last frame twice (the buffer has room for it)
        char* buffer = static_cast<char*>(m_AudioBuffer);
        SDL_memcpy(buffer + bytesWritten, buffer + bytesWritten - frameBytes, frameBytes);
        bytesWritten += frameBytes;
    }

    if (SDL_QueueAudio(m_AudioDevice, m_AudioBuffer, bytesWritten) < 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Failed to queue audio sample: %s",
                     SDL_GetError());
        return false;
    }

    if (pace.start) {
        SDL_PauseAudioDevice(m_AudioDevice, 0); // [fork] the reserve is there
    }

    // [fork] Every 10 s with anything to say
    if (m_ForkHealth) {
        std::string line = m_ForkHealth->report(forkNow);
        if (!line.empty()) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Audio (SDL), last 10 s: %s; %s", line.c_str(), forkRtpLine().c_str());
        }
    }

    return true;
}

IAudioRenderer::AudioFormat SdlAudioRenderer::getAudioBufferFormat()
{
    return AudioFormat::Float32NE;
}
