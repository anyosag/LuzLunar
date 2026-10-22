#include "bitraterules.h"

#include <algorithm>
#include <cmath>

namespace BitrateRules
{
namespace
{
    const double k_StartSettle = 5;         // s after the stream starts
    const double k_ClimbClean = 5;          // clean s per climb
    const double k_ClimbCleanNearLoss = 15; // clean s per climb near the bitrate that lost last
    const double k_CutHold = 10;            // s after a cut
    const double k_LossPercent = 2.0;
    const double k_LossCut = 0.7;
    const double k_RttCut = 0.9;
    const int k_RttHighSeconds = 3;
    const uint32_t k_RttMarginMs = 30;
    const double k_RttBucket = 15;          // s per bucket of the lowest round-trip time
    const double k_ClimbStep = 0.05;        // of the user's bitrate
    const double k_NearLoss = 0.85;         // of the bitrate that lost last

    uint32_t lowestOf(uint32_t a, uint32_t b)
    {
        if (a == 0) {
            return b;
        }
        if (b == 0) {
            return a;
        }
        return std::min(a, b);
    }
}

int floorKbps(int chosenKbps, bool hdr)
{
    int floor = std::max(hdr ? 5000 : 3000, chosenKbps / 5);
    return std::min(floor, chosenKbps);
}

Controller::Controller(int chosenKbps, bool hdr)
    : m_ChosenKbps(chosenKbps),
      m_FloorKbps(BitrateRules::floorKbps(chosenKbps, hdr)),
      m_CurrentKbps(chosenKbps),
      m_HoldUntil(k_StartSettle)
{
}

uint32_t Controller::baseRttMs() const
{
    return lowestOf(m_RttMinNow, m_RttMinBefore);
}

void Controller::noteRtt(uint32_t rttMs, double now)
{
    if (now - m_RttBucketStart >= k_RttBucket) {
        m_RttMinBefore = m_RttMinNow;
        m_RttMinNow = 0;
        m_RttBucketStart = now;
    }
    if (rttMs > 0) {
        m_RttMinNow = lowestOf(m_RttMinNow, rttMs);
    }
}

int Controller::changeTo(int kbps, double now, double hold)
{
    m_CurrentKbps = kbps;
    m_HoldUntil = now + hold;
    m_RttHighSeconds = 0;
    return kbps;
}

int Controller::tick(const Sample& sample)
{
    const double now = sample.seconds;

    // The base round-trip time is the lowest before this second: a queue building now shows against it
    uint32_t base = baseRttMs();
    noteRtt(sample.rttMs, now);

    bool lossy = sample.dropPercent >= k_LossPercent || sample.poor;
    bool rttHigh = sample.rttMs > 0 && base > 0 &&
                   sample.rttMs > base + std::max(k_RttMarginMs, base / 2);
    m_RttHighSeconds = rttHigh ? m_RttHighSeconds + 1 : 0;
    if (lossy || rttHigh) {
        m_LastBad = now;
        m_SeenBad = true;
    }

    if (now < m_HoldUntil) {
        return 0;
    }

    if (lossy || m_RttHighSeconds >= k_RttHighSeconds) {
        int target = std::max(m_FloorKbps, (int) std::lround(m_CurrentKbps * (lossy ? k_LossCut : k_RttCut)));
        if (target >= m_CurrentKbps) {
            // At the floor already
            return 0;
        }
        m_LastLossKbps = m_CurrentKbps;
        return changeTo(target, now, k_CutHold);
    }

    if (m_CurrentKbps >= m_ChosenKbps) {
        return 0;
    }
    bool nearLoss = m_LastLossKbps > 0 && m_CurrentKbps >= m_LastLossKbps * k_NearLoss;
    double clean = nearLoss ? k_ClimbCleanNearLoss : k_ClimbClean;
    if (m_SeenBad && now - m_LastBad < clean) {
        return 0;
    }
    int step = std::max(1, (int) std::lround(m_ChosenKbps * k_ClimbStep));
    int target = std::min(m_ChosenKbps, m_CurrentKbps + step);
    if (m_LastLossKbps > 0 && target >= m_LastLossKbps) {
        // Back past it without losses
        m_LastLossKbps = 0;
    }
    return changeTo(target, now, clean);
}
}
