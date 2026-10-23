#include "bitraterules.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace BitrateRules
{
namespace
{
    const double k_StartSettle = 5;         // s after the stream starts
    const double k_ClimbClean = 5;          // clean s per climb
    const double k_ClimbCleanNearLoss = 15; // clean s per climb near the bitrate that lost last
    const double k_CutHold = 10;            // s after a cut
    const double k_LossPercent = 2.0;
    const uint32_t k_LossFrames = 3;        // lost frames that make a lossy second, with k_LossPercent
    const double k_LossCut = 0.7;
    const double k_RttCut = 0.9;
    const int k_RttHighSeconds = 3;
    const uint32_t k_RttMarginMs = 30;
    const uint32_t k_RttFlatMs = 10;        // within this (or 15%) of the first cut's level: unmoved
    const int k_FlatRttCuts = 2;            // cuts that didn't move it before the route counts as slower
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

int launchKbps(int chosenKbps)
{
    if (chosenKbps <= 0) {
        return chosenKbps;
    }
    long long kbps = static_cast<long long>(chosenKbps) * 5 / 4;
    // moonlight-common-c's HIGH_AUDIO_BITRATE_THRESHOLD (>=) and LOW_AUDIO_BITRATE_TRESHOLD (<)
    for (long long line : {5000LL, 15000LL}) {
        if (chosenKbps < line && kbps >= line) {
            kbps = line - 1;
        }
    }
    return static_cast<int>(std::min<long long>(kbps, std::numeric_limits<int>::max()));
}

Controller::Controller(int chosenKbps, bool hdr)
    : Controller(chosenKbps, hdr, chosenKbps)
{
}

Controller::Controller(int chosenKbps, bool hdr, int startKbps)
    : m_ChosenKbps(chosenKbps),
      m_FloorKbps(BitrateRules::floorKbps(chosenKbps, hdr)),
      m_CurrentKbps(std::max(m_FloorKbps, std::min(startKbps, chosenKbps))),
      m_HoldUntil(k_StartSettle)
{
}

int Controller::changeTo(int kbps, double now, double hold, Reason reason, const Sample& sample)
{
    m_LastChange.reason = reason;
    m_LastChange.seconds = now;
    m_LastChange.fromKbps = m_CurrentKbps;
    m_LastChange.toKbps = kbps;
    m_LastChange.rttMs = sample.rttMs;
    m_LastChange.baseRttMs = m_BaseRttMs;
    m_LastChange.dropPercent = sample.dropPercent;
    m_LastChange.poor = sample.poor;
    m_CurrentKbps = kbps;
    m_HoldUntil = now + hold;
    m_RttHighSeconds = 0;
    m_HighRunMinMs = 0;
    return kbps;
}

int Controller::tick(const Sample& sample)
{
    const double now = sample.seconds;

    // The base round-trip time is the lowest before this second: a queue building now shows against it
    uint32_t base = m_BaseRttMs;
    if (sample.rttMs > 0) {
        m_BaseRttMs = lowestOf(m_BaseRttMs, sample.rttMs);
    }

    bool lossy = (sample.dropPercent >= k_LossPercent && sample.lostFrames >= k_LossFrames) || sample.poor;
    bool rttHigh = sample.rttMs > 0 && base > 0 &&
                   sample.rttMs > base + std::max(k_RttMarginMs, base / 2);
    if (rttHigh) {
        m_RttHighSeconds++;
        m_HighRunMinMs = lowestOf(m_HighRunMinMs, sample.rttMs);
    }
    else {
        m_RttHighSeconds = 0;
        m_HighRunMinMs = 0;
        if (sample.rttMs > 0 && base > 0) {
            // The queue drained: it was the stream's own, so the route's count starts over
            m_FlatRttLevelMs = 0;
            m_FlatRttCuts = 0;
        }
    }
    if (lossy || rttHigh) {
        m_LastBad = now;
        m_SeenBad = true;
    }

    if (now < m_HoldUntil) {
        return 0;
    }

    if (lossy || m_RttHighSeconds >= k_RttHighSeconds) {
        if (lossy) {
            // A queue overflowing is the stream's own: the round-trip time's cuts start over
            m_FlatRttLevelMs = 0;
            m_FlatRttCuts = 0;
        }
        else {
            // A queue the stream builds shrinks when it sends less. If the last cuts didn't move the
            // round-trip time, the route got slower: its time is the base from now on, no cut.
            // Against the first of the cuts, so a queue that rises a little at each one still counts.
            uint32_t level = m_HighRunMinMs;
            if (m_FlatRttLevelMs > 0) {
                uint32_t tolerance = std::max(k_RttFlatMs, m_FlatRttLevelMs * 15 / 100);
                bool flat = level + tolerance >= m_FlatRttLevelMs && level <= m_FlatRttLevelMs + tolerance;
                m_FlatRttCuts = flat ? m_FlatRttCuts + 1 : 0;
            }
            if (m_FlatRttCuts >= k_FlatRttCuts) {
                m_BaseRttMs = level;
                m_FlatRttLevelMs = 0;
                m_FlatRttCuts = 0;
                m_RttHighSeconds = 0;
                m_HighRunMinMs = 0;
                return 0;
            }
            if (m_FlatRttCuts == 0) {
                m_FlatRttLevelMs = level;
            }
        }

        int target = std::max(m_FloorKbps, (int) std::lround(m_CurrentKbps * (lossy ? k_LossCut : k_RttCut)));
        if (target >= m_CurrentKbps) {
            // At the floor already: no change, but the next look waits as after a cut
            m_HoldUntil = now + k_CutHold;
            m_RttHighSeconds = 0;
            m_HighRunMinMs = 0;
            return 0;
        }
        m_LastLossKbps = m_CurrentKbps;
        return changeTo(target, now, k_CutHold, lossy ? Reason::Loss : Reason::RoundTrip, sample);
    }

    if (m_CurrentKbps >= m_ChosenKbps || now < m_NextClimbAt) {
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
    // The next climb waits as long, but a cut only the usual 5 s
    m_NextClimbAt = now + clean;
    return changeTo(target, now, k_ClimbClean, Reason::Climb, sample);
}
}
