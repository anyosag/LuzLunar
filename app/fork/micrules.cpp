#include "micrules.h"

#include <algorithm>

namespace MicRules
{

std::string launchValue(bool setting, int hostVersion, bool helperWindow)
{
    return setting && hostVersion >= luzmic::k_serverinfo_version && !helperWindow ? "1" : "";
}

Output classifyOutput(Transport transport, bool builtInHeadphones)
{
    switch (transport) {
    case Transport::BuiltIn:
        return builtInHeadphones ? Output::Headphones : Output::Speakers;
    case Transport::Bluetooth:
    case Transport::BluetoothLE:
    case Transport::Usb:
        return Output::Headphones;
    default:
        return Output::Speakers;
    }
}

bool voiceProcessedPlayback(bool streamAsked, Output output)
{
    return streamAsked && output == Output::Speakers;
}

std::string chooseInput(const std::string& saved, const std::vector<Input>& inputs)
{
    if (!saved.empty()) {
        for (const Input& input : inputs) {
            if (input.uid == saved) {
                return saved;
            }
        }
    }
    for (const Input& input : inputs) {
        if (input.builtIn) {
            return input.uid;
        }
    }
    return "";
}

Status status(const Situation& situation)
{
    if (!situation.settingOn || !situation.asked) {
        return Status::Off;
    }
    if (!situation.hostOffers) {
        return Status::NeedsApollo;
    }
    if (situation.access == Access::Denied) {
        return Status::NoAccess;
    }
    if (!situation.hostReady) {
        return Status::NotOnPc;
    }
    if (!situation.hostRecording) {
        return Status::Standby;
    }
    return situation.muted ? Status::Muted : Status::Live;
}

bool shouldCapture(const Situation& situation)
{
    return status(situation) == Status::Live;
}

void FrameClock::startRecording(std::uint32_t nowMs)
{
    m_TimeMs = nowMs;
    m_Start = true;
}

luzmic::frame_t FrameClock::next()
{
    luzmic::frame_t frame;
    frame.flags = m_Start ? luzmic::flag_start : 0;
    frame.sequence = m_Sequence++;
    frame.time_ms = m_TimeMs;
    m_TimeMs += luzmic::k_frame_ms;
    m_Start = false;
    return frame;
}

void downmixToStereo(const float* in, int channels, int frames, float* out)
{
    // ITU-style: the centre and the surrounds at -3 dB into each side
    constexpr float k_Side = 0.7071f;
    for (int i = 0; i < frames; i++) {
        const float* f = in + static_cast<size_t>(i) * static_cast<size_t>(channels);
        float left = f[0];
        float right = channels > 1 ? f[1] : f[0];
        if (channels >= 6) {
            left += k_Side * (f[2] + f[4]);
            right += k_Side * (f[2] + f[5]);
        }
        if (channels >= 8) {
            left += k_Side * f[6];
            right += k_Side * f[7];
        }
        if (channels >= 6) {
            // Keep a loud mix from clipping: the most the extra channels add
            float scale = channels >= 8 ? 1.0f / (1.0f + 3 * k_Side) : 1.0f / (1.0f + 2 * k_Side);
            left *= scale;
            right *= scale;
        }
        out[2 * i] = left;
        out[2 * i + 1] = right;
    }
}

PcmRing::PcmRing(int capacityFrames, int primeFrames)
    : m_Data(static_cast<size_t>(std::max(capacityFrames, 1)) * 2),
      m_Capacity(std::max(capacityFrames, 1)),
      m_Prime(std::clamp(primeFrames, 0, std::max(capacityFrames, 1) / 2))
{
}

void PcmRing::push(const float* stereo, int frames)
{
    std::lock_guard<std::mutex> lock(m_Mutex);
    // More than fits: only the newest
    if (frames > m_Capacity) {
        stereo += static_cast<size_t>(frames - m_Capacity) * 2;
        frames = m_Capacity;
    }
    int over = m_Count + frames - m_Capacity;
    if (over > 0) {
        m_Read = (m_Read + over) % m_Capacity;
        m_Count -= over;
    }
    int write = (m_Read + m_Count) % m_Capacity;
    for (int i = 0; i < frames; i++) {
        m_Data[static_cast<size_t>(write) * 2] = stereo[2 * i];
        m_Data[static_cast<size_t>(write) * 2 + 1] = stereo[2 * i + 1];
        write = (write + 1) % m_Capacity;
    }
    m_Count += frames;
}

int PcmRing::pull(float* left, float* right, int frames)
{
    std::lock_guard<std::mutex> lock(m_Mutex);
    frames = std::max(frames, 0);

    if (m_Prime > 0 && !m_Primed) {
        if (m_Count < m_Prime) {
            // Filling the cushion
            std::fill(left, left + frames, 0.0f);
            std::fill(right, right + frames, 0.0f);
            return 0;
        }
        m_Primed = true;
        m_SinceDrift = 0;
    }

    int got = 0;
    while (got < frames && m_Count > 0) {
        left[got] = m_Data[static_cast<size_t>(m_Read) * 2];
        right[got] = m_Data[static_cast<size_t>(m_Read) * 2 + 1];
        got++;

        int consume = 1;
        if (m_Prime > 0 && ++m_SinceDrift >= k_RingDriftEveryFrames) {
            m_SinceDrift = 0;
            if (m_Count > 2 * m_Prime) {
                consume = 2;    // the PC runs ahead: leave a frame out
            }
            else if (m_Count < m_Prime / 2) {
                consume = 0;    // the speakers run ahead: play this frame twice
            }
        }
        consume = std::min(consume, m_Count);
        m_Read = (m_Read + consume) % m_Capacity;
        m_Count -= consume;
    }

    if (got < frames) {
        std::fill(left + got, left + frames, 0.0f);
        std::fill(right + got, right + frames, 0.0f);
        if (m_Prime > 0) {
            // Dry: one gap, then play again from a full cushion, rather than a click every packet
            m_Primed = false;
        }
    }
    return got;
}

int PcmRing::queued() const
{
    std::lock_guard<std::mutex> lock(m_Mutex);
    return m_Count;
}

void PcmRing::clear()
{
    std::lock_guard<std::mutex> lock(m_Mutex);
    m_Read = 0;
    m_Count = 0;
    m_Primed = false;
    m_SinceDrift = 0;
}

}
