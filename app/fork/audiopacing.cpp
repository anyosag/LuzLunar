#include "audiopacing.h"

#include <algorithm>

namespace AudioPacing
{

Pacer::Pacer(int sampleRate, Settings settings)
    : m_Settings(settings),
      m_SampleRate(std::max(sampleRate, 1))
{
}

Decision Pacer::packet(double nowMs, double queuedMs, int frames)
{
    Decision decision;
    double gap = m_LastMs < 0 ? 0 : nowMs - m_LastMs;
    m_LastMs = nowMs;
    double packetMs = std::max(frames, 0) * 1000.0 / m_SampleRate;

    if (m_Playing && gap >= m_Settings.pauseMs && queuedMs <= 0) {
        // The PC paused (silence) and the device has played everything: build the reserve again,
        // so the sound that starts now doesn't play from nothing
        m_Playing = false;
        decision.hold = true;
    }

    if (!m_Playing) {
        if (queuedMs + packetMs >= m_Settings.targetMs) {
            m_Playing = true;
            m_SinceAdjust = 0;
            decision.start = true;
        }
        return decision;
    }

    if (queuedMs > m_Settings.capMs) {
        decision.drop = true;
        return decision;
    }

    m_SinceAdjust += std::max(frames, 0);
    if (m_SinceAdjust >= m_Settings.driftEveryFrames) {
        m_SinceAdjust = 0;
        if (queuedMs > m_Settings.highMs) {
            decision.adjust = -1;
        }
        else if (queuedMs < m_Settings.lowMs) {
            decision.adjust = +1;
        }
    }
    return decision;
}

}
