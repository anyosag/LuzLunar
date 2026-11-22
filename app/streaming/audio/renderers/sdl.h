#pragma once

#include "renderer.h"
#include "SDL_compat.h"

#include <memory>

#include "fork/audiohealth.h" // [fork]
#include "fork/audiopacing.h" // [fork]

class SdlAudioRenderer : public IAudioRenderer
{
public:
    SdlAudioRenderer();

    virtual ~SdlAudioRenderer();

    virtual bool prepareForPlayback(const OPUS_MULTISTREAM_CONFIGURATION* opusConfig);

    virtual void* getAudioBuffer(int* size);

    virtual bool submitAudio(int bytesWritten);

    virtual AudioFormat getAudioBufferFormat();

private:
    SDL_AudioDeviceID m_AudioDevice;
    void* m_AudioBuffer;
    Uint32 m_FrameSize;
    Uint32 m_FrameDurationMs;
    std::unique_ptr<AudioHealth::Monitor> m_ForkHealth; // [fork] late, dry and thrown-away packets, for the log
    double m_ForkBytesPerMs = 0; // [fork]
    std::unique_ptr<AudioPacing::Pacer> m_ForkPacer; // [fork] the reserve, the drift, the cap (audiopacing.h)
    int m_ForkFrameBytes = 0; // [fork] one sample of every channel
};
