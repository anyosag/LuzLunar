#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "streamhistory.h"

// [fork] The notch bar's Stream status without AppKit (mac/notchstatus_mac.mm draws it), so tests
// can build it alone (tests/fork/notchstatus_test.cpp): the latency graph's scale, the two-minute
// summary, the latency bar's segments, where the pointer is on the graph, the stream's health, and
// the bar item's text. The numbers follow the canvas the bar was designed on.
namespace NotchStatus
{
    using StreamHistory::Sample;

    constexpr double k_GraphWidth = 270;
    constexpr double k_PlotHeight = 63;         // the line's 0 ms to the scale's top
    constexpr double k_TooltipWidth = 74;
    constexpr double k_SegmentGap = 2;
    constexpr double k_NearestSeconds = 1;      // the pointer reads a sample this close, or a gap
    constexpr double k_PoorLossPercent = 2;
    constexpr double k_HealthSeconds = 5;

    // The graph's scale: 0–63 ms, or more when a peak needs it, with gridlines at a quarter and a
    // half of a round step
    struct Scale {
        double topMs = 63;
        double stepMs = 25;     // gridlines at step and 2 × step
    };

    inline Scale scaleFor(double peakMs)
    {
        Scale scale;
        if (StreamHistory::known(peakMs)) {
            scale.topMs = std::max(63.0, std::ceil(peakMs * 1.05));
        }
        scale.stepMs = 25;
        for (double step : { 500.0, 250.0, 100.0, 50.0, 25.0 }) {
            if (2 * step <= scale.topMs * 0.95) {
                scale.stepMs = step;
                break;
            }
        }
        return scale;
    }

    // Height above the graph's baseline for a latency, capped at the top
    inline double heightFor(double ms, const Scale& scale)
    {
        return std::min(ms, scale.topMs) / scale.topMs * k_PlotHeight;
    }

    // "usually N ms · peak N ms": the upper median and the first highest, over samples with a total
    struct Summary {
        bool any = false;
        double usualMs = 0;
        double peakMs = 0;
        std::size_t peakIndex = 0;      // in the samples given
    };

    inline Summary summarize(const std::vector<Sample>& samples)
    {
        Summary summary;
        std::vector<double> totals;
        for (std::size_t i = 0; i < samples.size(); i++) {
            double total = StreamHistory::total(samples[i].parts);
            if (!StreamHistory::known(total)) {
                continue;
            }
            if (!summary.any || total > summary.peakMs) {
                summary.peakMs = total;
                summary.peakIndex = i;
            }
            summary.any = true;
            totals.push_back(total);
        }
        if (summary.any) {
            std::sort(totals.begin(), totals.end());
            summary.usualMs = totals[totals.size() / 2];
        }
        return summary;
    }

    // Whether the bitrate was lowered within a few seconds of a sample, as in "peaked at 60 ms
    // 62 seconds ago, when the bitrate was lowered"
    inline bool loweredNear(const std::vector<Sample>& samples, std::size_t index, double withinSeconds = 3)
    {
        if (index >= samples.size()) {
            return false;
        }
        for (const Sample& sample : samples) {
            if (sample.lowered && std::fabs(sample.seconds - samples[index].seconds) <= withinSeconds) {
                return true;
            }
        }
        return false;
    }

    // The latency bar: each known part's share of the room, less 2 points between the parts shown
    inline std::array<double, StreamHistory::PartCount> segmentWidths(const StreamHistory::Parts& parts,
                                                                       double room = k_GraphWidth)
    {
        std::array<double, StreamHistory::PartCount> widths {};
        int shown = 0;
        double total = 0;
        for (double part : parts) {
            if (StreamHistory::known(part) && part > 0) {
                shown++;
                total += part;
            }
        }
        if (shown == 0) {
            return widths;
        }
        double available = std::max(room - (shown - 1) * k_SegmentGap, 0.0);
        for (std::size_t i = 0; i < parts.size(); i++) {
            if (StreamHistory::known(parts[i]) && parts[i] > 0) {
                widths[i] = parts[i] / total * available;
            }
        }
        return widths;
    }

    // Across the graph: two minutes ago at 0, now at the right edge
    inline double xForAge(double ageSeconds, double width = k_GraphWidth)
    {
        return width * (1 - ageSeconds / StreamHistory::History::WindowSeconds);
    }

    inline double ageForX(double x, double width = k_GraphWidth)
    {
        double age = (1 - x / width) * StreamHistory::History::WindowSeconds;
        return std::max(0.0, std::min(age, StreamHistory::History::WindowSeconds));
    }

    // The sample nearest to ageSeconds before now, if one is within k_NearestSeconds; -1 for a gap
    inline int nearest(const std::vector<Sample>& samples, double now, double ageSeconds)
    {
        int best = -1;
        double bestDistance = k_NearestSeconds;
        for (std::size_t i = 0; i < samples.size(); i++) {
            double distance = std::fabs((now - samples[i].seconds) - ageSeconds);
            if (distance <= bestDistance) {
                best = static_cast<int>(i);
                bestDistance = distance;
            }
        }
        return best;
    }

    // Right of the cursor in the graph's left half, left of it in the right half, inside the graph
    inline double tooltipX(double cursorX, double width = k_GraphWidth)
    {
        double x = cursorX < width / 2 ? cursorX + 8 : cursorX - k_TooltipWidth - 8;
        return std::max(0.0, std::min(width - k_TooltipWidth, x));
    }

    // Whole seconds ago, as "N s ago"; 0 reads "Now"
    inline int secondsAgo(double ageSeconds)
    {
        return std::max(0, static_cast<int>(std::lround(ageSeconds)));
    }

    // The header's dot: no video yet, or Moonlight's poor connection warning or frames lost lately.
    // haveVideo: any snapshot this stream, even one older than the history (a still desktop sends
    // no frames, which isn't a fault).
    enum class Health {
        Waiting,
        Smooth,
        Poor,
    };

    inline Health health(bool haveVideo, bool poorReported, const std::vector<Sample>& samples, double now)
    {
        if (!haveVideo) {
            return Health::Waiting;
        }
        if (poorReported) {
            return Health::Poor;
        }
        for (const Sample& sample : samples) {
            if (now - sample.seconds <= k_HealthSeconds && sample.dropPercent >= k_PoorLossPercent) {
                return Health::Poor;
            }
        }
        return Health::Smooth;
    }

    // The bar item: "5 GHz · 120 fps · 8 ms · 18.2 Mb/s ↓15". band is empty when it isn't shown;
    // an RTT of 0 wasn't measured. The bitrate goes to the Quality item once the bar has one.
    inline std::string barText(const std::string& band, double fps, uint32_t rttMs, double mbps, double capMbps)
    {
        char text[96];
        char rtt[16];
        if (rttMs > 0) {
            std::snprintf(rtt, sizeof(rtt), "%u ms", rttMs);
        }
        else {
            std::snprintf(rtt, sizeof(rtt), "— ms");
        }
        char cap[16] = "";
        if (capMbps > 0) {
            std::snprintf(cap, sizeof(cap), " ↓%.0f", capMbps);
        }
        std::snprintf(text, sizeof(text), "%s%s%.0f fps · %s · %.1f Mb/s%s",
                      band.c_str(), band.empty() ? "" : " · ", fps, rtt, mbps, cap);
        return text;
    }
}
