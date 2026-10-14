#pragma once

#include <string>
#include <vector>

// Stream sizes for an aspect ratio, kept free of Qt and SDL so they can be unit tested on their
// own (tests/fork/aspect_test.cpp). Apollo makes a virtual display at exactly the size a stream
// asks for, so any ratio works; these lists are only suggestions.
namespace ForkAspect
{
    // The smallest and largest width or height the settings accept
    const int k_MinSide = 256;
    const int k_MaxSide = 8192;

    struct Size {
        int width = 0;
        int height = 0;
    };

    // A size offered for a ratio, as picked from a list
    struct Preset {
        int width = 0;
        int height = 0;
        bool fillsDisplay = false;        // the biggest size of this ratio that fits the display
        bool largerThanDisplay = false;   // wider or taller than the display (Apollo can render above the panel's resolution)
    };

    // 945 gives 944. Zero for anything below 2, since nothing sensible is left.
    int evenDown(int value);

    // Both sides even (rounded down) and between 256 and 8192
    Size normalize(int width, int height);

    // The largest even size with this width to height ratio that fits the box: one side is the
    // box's, the other is rounded down to even. 0x0 for a ratio or box that makes no sense.
    Size fitInBox(double ratio, Size box);

    // Sizes to offer for a ratio, smallest first, with no duplicates:
    //  - the largest that fits the box (fillsDisplay)
    //  - 720, 1080, 1440, 2160 and 2880 lines at the ratio
    //  - well-known monitor sizes (2560x1080, 3440x1440, 1920x1200...) within 1% of the ratio;
    //    one replaces the generated size with the same height, so 21:9 has 3440x1440 and no 3412x1440
    // Sizes with a side below 256 or above 8192 are dropped. Sizes beyond the box are kept and
    // marked largerThanDisplay. An empty box marks nothing.
    std::vector<Preset> presetsFor(double ratio, Size box);

    // "16:9", "21:9", "12:5" or a decimal like "2.39:1" (a lone "2.39" works too) as width over
    // height. 0 for text that isn't a ratio, or one no allowed size has (beyond 32:1 either way).
    double parseRatio(const std::string& text);

    // The other side for a given one, even, with the ratio kept (the aspect lock). 0 if the
    // ratio makes no sense.
    int linkedHeight(int width, double ratio);
    int linkedWidth(int height, double ratio);
}
