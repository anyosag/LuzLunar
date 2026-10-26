#include "hostpacing.h"

#include <cstdio>
#include <cstring>
#include <mutex>

#include "SDL_compat.h"

#include "hostcadence.h"

namespace ForkHostPacing
{

namespace
{
    std::mutex s_Mutex;
    HostCadence s_Cadence;
    HostCadenceSummary s_Summary;
    HostCadenceSummary s_Window;    // since takeWindow()
    bool s_HaveScore = false;
    double s_Percent = 0;
    double s_DeviationMs = 0;
}

void reset()
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    s_Cadence = HostCadence();
    s_Summary = HostCadenceSummary();
    s_Window = HostCadenceSummary();
    s_HaveScore = false;
}

void observe(int frameNumber, uint32_t rtpTimestamp)
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    HostCadence::Sample sample = s_Cadence.observe(static_cast<uint32_t>(frameNumber), rtpTimestamp);
    if (!sample.valid) {
        return;
    }
    s_Percent = HostCadence::smoothnessPercent(sample.varianceTicksSquared);
    s_DeviationMs = HostCadence::deviationMs(sample.varianceTicksSquared);
    s_HaveScore = true;
    s_Summary.add(s_Percent);
    s_Window.add(s_Percent);
}

bool takeWindow(double* average, double* lowest)
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    if (s_Window.empty()) {
        return false;
    }
    *average = s_Window.average();
    *lowest = s_Window.lowest();
    s_Window = HostCadenceSummary();
    return true;
}

void appendOverlayLine(char* text, int maxLength)
{
    double percent;
    double deviationMs;
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!s_HaveScore) {
            return;
        }
        percent = s_Percent;
        deviationMs = s_DeviationMs;
    }
    size_t length = strlen(text);
    if (maxLength <= 0 || length >= static_cast<size_t>(maxLength)) {
        return;
    }
    // A whole line or nothing; the overlay's font has no Greek, so no σ
    char line[96];
    int written = snprintf(line, sizeof(line), "Host frame pacing: %.1f %% (spread %.1f ms)\n", percent, deviationMs);
    if (written > 0 && length + static_cast<size_t>(written) < static_cast<size_t>(maxLength)) {
        memcpy(text + length, line, static_cast<size_t>(written) + 1);
    }
}

void logSummary()
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    if (s_Summary.empty()) {
        return;
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Host frame pacing: %.1f %% on average, %.1f %% at worst, over %llu frames",
                s_Summary.average(), s_Summary.lowest(), static_cast<unsigned long long>(s_Summary.count()));
}

}
