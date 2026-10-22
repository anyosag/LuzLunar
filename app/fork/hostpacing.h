#pragma once

#include <cstdint>

// [fork] How evenly the PC sends frames (hostcadence.h), for the stream running now: fed each
// frame from the decode thread, shown in the stats overlay, and summed up in the log when the
// stream ends.
namespace ForkHostPacing
{
    // A new stream: forgets the last one's
    void reset();

    // Each frame as it arrives, in order; on the decode thread
    void observe(int frameNumber, uint32_t rtpTimestamp);

    // Appends "Host frame pacing: 98.7 % (spread 0.8 ms)" to the stats overlay's text, once there's a score
    void appendOverlayLine(char* text, int maxLength);

    // Logs the stream's average and lowest scores
    void logSummary();
}
