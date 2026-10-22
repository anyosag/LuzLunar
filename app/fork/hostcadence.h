#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

// [fork] How evenly the PC sends frames, from the RTP timestamps it stamps on them (90 kHz), so
// nothing on this Mac (network, decoding, display) affects it. Over the last 30 frame intervals:
// the spread of their lengths, scored 100 / (1 + (σ / 6 ms)^4). A σ of 1 ms scores 99.9 %, 3 ms
// 94 % and 6 ms 50 %. A lost frame, a repeated or backward timestamp starts the window again.
// A port of Nonary's moonlight-qt (app/streaming/video/incomingframetiming.h, GPLv3).
//
// Apollo snaps a frame's timestamp to the ideal cadence when it's within a quarter frame of it,
// so the score shows frames held or skipped on the PC rather than small jitter. On a still
// desktop Apollo only sends frames when something changes, so the score is low there for no
// fault. Pure C++, so tests can build it on its own.
class HostCadence
{
public:
    static constexpr std::size_t WindowSize = 30;

    // σ in RTP ticks² → the score
    static double smoothnessPercent(double varianceTicksSquared)
    {
        constexpr double softKneeTicks = 6.0 * 90.0;
        const double normalized = varianceTicksSquared / (softKneeTicks * softKneeTicks);
        return 100.0 / (1.0 + normalized * normalized);
    }

    // The standard deviation of the window's intervals, in milliseconds
    static double deviationMs(double varianceTicksSquared)
    {
        return varianceTicksSquared > 0 ? std::sqrt(varianceTicksSquared) / 90.0 : 0.0;
    }

    struct Sample {
        bool valid = false;     // a full window of adjacent frames
        double varianceTicksSquared = 0;
    };

    // Each frame as it arrives, in order
    Sample observe(uint32_t frameNumber, uint32_t rtpTimestamp)
    {
        Sample sample;
        const uint32_t interval = rtpTimestamp - m_PreviousTimestamp;
        const bool adjacent = m_HaveFrame && frameNumber - m_PreviousFrame == 1;
        m_PreviousFrame = frameNumber;
        m_PreviousTimestamp = rtpTimestamp;
        m_HaveFrame = true;

        // Unsigned subtraction handles the wrap; a gap, a repeat or a step back starts again
        if (!adjacent || interval == 0 || interval >= 0x80000000U) {
            m_Count = 0;
            m_Next = 0;
            return sample;
        }

        m_Intervals[m_Next] = interval;
        m_Next = (m_Next + 1) % WindowSize;
        m_Count = std::min(m_Count + 1, WindowSize);
        if (m_Count < WindowSize) {
            return sample;
        }

        // Around the window's own mean, not the stream's frame rate, in two passes
        uint64_t total = 0;
        for (const uint32_t ticks : m_Intervals) {
            total += ticks;
        }
        const double mean = double(total) / WindowSize;
        for (const uint32_t ticks : m_Intervals) {
            const double deviation = double(ticks) - mean;
            sample.varianceTicksSquared += deviation * deviation;
        }
        sample.varianceTicksSquared /= WindowSize;
        sample.valid = true;
        return sample;
    }

private:
    std::array<uint32_t, WindowSize> m_Intervals {};
    std::size_t m_Count = 0;
    std::size_t m_Next = 0;
    uint32_t m_PreviousFrame = 0;
    uint32_t m_PreviousTimestamp = 0;
    bool m_HaveFrame = false;
};

// [fork] A stream's scores, for the line logged when it ends
class HostCadenceSummary
{
public:
    void add(double percent)
    {
        m_Total += percent;
        m_Lowest = m_Count == 0 ? percent : std::min(m_Lowest, percent);
        m_Count++;
    }

    bool empty() const { return m_Count == 0; }
    double average() const { return m_Count == 0 ? 0.0 : m_Total / m_Count; }
    double lowest() const { return m_Lowest; }
    uint64_t count() const { return m_Count; }

private:
    double m_Total = 0;
    double m_Lowest = 0;
    uint64_t m_Count = 0;
};
