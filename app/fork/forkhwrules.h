#pragma once

#include <string>
#include <vector>

// What this Mac can and can't do for a stream, kept free of Qt, SDL and AppKit so it can be unit
// tested on its own (tests/fork/hwrules_test.cpp). ClientHardware fills in the facts.
namespace ForkHwRules
{
    // One screen. A display with a notch has two shapes: the full panel, including the strip beside
    // the notch (3024x1964, about 1.54:1, on a 14" MacBook Pro), and the area below the notch
    // (3024x1890, 16:10). Without a notch both are the same.
    struct Display {
        std::string name;
        int nativeWidth = 0, nativeHeight = 0;     // the full panel, in pixels
        int safeWidth = 0, safeHeight = 0;         // below the notch, in pixels
        double scale = 1;                          // pixels per point at the current setting
        bool hasNotch = false;
        int maxRefresh = 0;                        // Hz; 0 if unknown
        bool hdr = false;

        // For the host's virtual display (clientdisplay.*); appended so older initializers still fit
        int widthMm = 0, heightMm = 0;             // physical size; 0 if unknown
        bool p3 = false;                           // shows the Display P3 gamut
        double edrPotential = 1;                   // the most the panel can go above SDR white
        double edrCurrent = 1;                     // above SDR white right now, which follows brightness
        double edrReference = 0;                   // in a reference preset; 0 otherwise
        int minRefresh = 0;                        // Hz; ProMotion's lowest; 0 if unknown
    };

    // Which codecs this Mac decodes in hardware (Main10 is 10-bit HEVC, needed for HDR)
    struct Decoders {
        bool h264 = false, hevc = false, hevcMain10 = false, av1 = false;
    };

    enum class Codec { Auto, H264, HEVC, AV1 };

    // Short, user-facing warnings for the stream settings on this hardware; empty if all is fine.
    // They're advice only: a stream still starts, though it may decode in software.
    std::vector<std::string> checkStream(const Decoders& decoders, const Display& display,
                                         int width, int height, int fps, Codec codec, bool hdr);

    // 1920x1080 as "16:9", 3024x1890 as "16:10", 3440x1440 as "21:9": the usual name if the ratio
    // is within 1% of it, else a reduced "W:H" when both terms are 32 or less, else a decimal like
    // "1.54:1". A portrait size gives the landscape label turned around ("9:16"). Empty for a
    // size that makes no sense.
    std::string ratioLabel(int width, int height);
}
