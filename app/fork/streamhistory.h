#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <vector>

// [fork] The latency of a stream from a click to the picture, in four parts, and the last two
// minutes of it, for the notch bar's Stream status (mac/notchstatus_mac.mm). ForkStreamStats fills
// it from the decoder's stats windows (streamstats.cpp). Free of Qt and Moonlight's headers, so
// tests can build it on its own (tests/fork/streamhistory_test.cpp).
namespace StreamHistory
{
    // What latency() needs from a stats window (VIDEO_STATS, streaming/video/decoder.h)
    struct Totals {
        uint32_t totalHostProcessingLatency = 0;    // in 0.1 ms
        uint32_t framesWithHostProcessingLatency = 0;
        uint64_t totalDecodeTimeUs = 0;
        uint32_t decodedFrames = 0;
        uint64_t totalPacerTimeUs = 0;
        uint64_t totalRenderTimeUs = 0;
        uint32_t renderedFrames = 0;
        uint32_t lastRttMs = 0;                     // 0: not measured
    };

    enum Part {
        PcCaptureAndEncode,
        NetworkRoundTrip,
        MacDecode,
        Display,            // the frame queue and drawing, including V-Sync
        PartCount,
    };

    // Milliseconds; NaN where unknown
    using Parts = std::array<double, PartCount>;

    inline double unknown()
    {
        return std::numeric_limits<double>::quiet_NaN();
    }

    inline bool known(double value)
    {
        return !std::isnan(value);
    }

    inline Parts unknownParts()
    {
        Parts parts;
        parts.fill(unknown());
        return parts;
    }

    // The averages Moonlight's stats overlay shows (FFmpegVideoDecoder::stringifyVideoStats()).
    // Mac decode leaves out reassembly (a frame's first packet to its last), which is the frame's
    // transfer rather than decoding, as the overlay does.
    inline Parts latency(const Totals& totals)
    {
        Parts parts = unknownParts();
        if (totals.framesWithHostProcessingLatency > 0) {
            parts[PcCaptureAndEncode] = totals.totalHostProcessingLatency / 10.0 / totals.framesWithHostProcessingLatency;
        }
        if (totals.lastRttMs > 0) {
            parts[NetworkRoundTrip] = totals.lastRttMs;
        }
        if (totals.decodedFrames > 0) {
            parts[MacDecode] = totals.totalDecodeTimeUs / 1000.0 / totals.decodedFrames;
        }
        if (totals.renderedFrames > 0) {
            parts[Display] = (totals.totalPacerTimeUs + totals.totalRenderTimeUs) / 1000.0 / totals.renderedFrames;
        }
        return parts;
    }

    // The known parts added up; NaN when none is known
    inline double total(const Parts& parts)
    {
        double sum = 0;
        bool any = false;
        for (double part : parts) {
            if (known(part)) {
                sum += part;
                any = true;
            }
        }
        return any ? sum : unknown();
    }

    // One stats window, about two seconds of the stream (the decoder sums its last two)
    struct Sample {
        double seconds = 0;             // when, on a steady clock
        Parts parts = unknownParts();
        double fps = 0;
        double dropPercent = 0;         // frames lost on the network
        double targetMbps = 0;          // the bitrate the PC runs the stream at, as it confirmed; 0 while unknown
        bool lowered = false;           // it went down here, by adaptive bitrate or by hand (History::add() sets it)
        double pacingLowest = unknown();    // the PC's frame pacing scores since the last sample (hostcadence.h)
        double pacingAverage = unknown();
    };

    class History
    {
    public:
        static constexpr std::size_t Capacity = 150;
        static constexpr double WindowSeconds = 120;
        // Samples come about a second apart, each covering about two: further apart than this,
        // frames stopped in between (as on a still desktop), and the graph's line breaks
        static constexpr double GapSeconds = 2.5;

        void reset()
        {
            m_Samples.clear();
            m_LastTargetMbps = 0;
        }

        // Marks the sample lowered when the bitrate went down since the last; not when it goes up
        void add(Sample sample)
        {
            sample.lowered = m_LastTargetMbps > 0 && sample.targetMbps > 0 && sample.targetMbps < m_LastTargetMbps;
            if (sample.targetMbps > 0) {
                m_LastTargetMbps = sample.targetMbps;
            }
            m_Samples.push_back(sample);
            while (m_Samples.size() > Capacity) {
                m_Samples.pop_front();
            }
        }

        bool empty() const { return m_Samples.empty(); }
        const Sample& latest() const { return m_Samples.back(); }

        // The samples from the last `seconds` before now, oldest first
        std::vector<Sample> window(double now, double seconds = WindowSeconds) const
        {
            std::vector<Sample> samples;
            for (const Sample& sample : m_Samples) {
                if (now - sample.seconds <= seconds) {
                    samples.push_back(sample);
                }
            }
            return samples;
        }

    private:
        std::deque<Sample> m_Samples;
        double m_LastTargetMbps = 0;
    };

    // Where each stretch the graph draws as one line starts, in samples oldest first: a new one
    // after every gap of more than History::GapSeconds
    inline std::vector<std::size_t> runStarts(const std::vector<Sample>& samples)
    {
        std::vector<std::size_t> starts;
        for (std::size_t i = 0; i < samples.size(); i++) {
            if (i == 0 || samples[i].seconds - samples[i - 1].seconds > History::GapSeconds) {
                starts.push_back(i);
            }
        }
        return starts;
    }
}
