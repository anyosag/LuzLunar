#include "forkaspect.h"

#include <algorithm>
#include <cmath>

namespace ForkAspect
{

namespace
{
    // Heights offered for every ratio
    const int k_Heights[] = { 720, 1080, 1440, 2160, 2880 };

    // Monitor sizes people look for, offered for any ratio they match
    const Size k_WellKnown[] = {
        // 21:9 and 32:9
        { 2560, 1080 }, { 3440, 1440 }, { 5120, 2160 }, { 3840, 1600 }, { 3840, 1080 }, { 5120, 1440 },
        // 16:10
        { 1280, 800 }, { 1440, 900 }, { 1680, 1050 }, { 1920, 1200 }, { 2560, 1600 },
        // 4:3 and 5:4
        { 1024, 768 }, { 1600, 1200 }, { 2048, 1536 }, { 1280, 1024 },
        // 3:2
        { 1920, 1280 }, { 2560, 1700 },
    };

    // How far a size's ratio may be from the one asked for to count as that ratio
    const double k_Tolerance = 0.01;

    // Floating point error must not turn 3023.9999999999995 into 3022
    const double k_Epsilon = 1e-6;

    bool inRange(const Size& size)
    {
        return size.width >= k_MinSide && size.width <= k_MaxSide &&
               size.height >= k_MinSide && size.height <= k_MaxSide;
    }

    long long pixels(const Size& size)
    {
        return static_cast<long long>(size.width) * size.height;
    }

    // A plain decimal like "16" or "2.39"; a comma works as the decimal point too
    bool parseNumber(const std::string& text, double* value)
    {
        double whole = 0, fraction = 0, scale = 1;
        bool digits = false, point = false;
        for (char c : text) {
            if (c >= '0' && c <= '9') {
                digits = true;
                if (point) {
                    scale /= 10;
                    fraction += (c - '0') * scale;
                }
                else {
                    whole = whole * 10 + (c - '0');
                    if (whole > 1e9) {
                        return false;
                    }
                }
            }
            else if ((c == '.' || c == ',') && !point) {
                point = true;
            }
            else {
                return false;
            }
        }

        *value = whole + fraction;
        return digits;
    }

    // The nearest integer, then rounded down to even; 0 for anything that doesn't fit an int
    int roundedEven(double value)
    {
        if (!std::isfinite(value) || value < 0 || value > 1e9) {
            return 0;
        }
        return evenDown(static_cast<int>(std::lround(value)));
    }

    std::string trim(const std::string& text)
    {
        size_t first = text.find_first_not_of(" \t");
        if (first == std::string::npos) {
            return std::string();
        }
        return text.substr(first, text.find_last_not_of(" \t") - first + 1);
    }
}

int evenDown(int value)
{
    return value > 0 ? value - (value % 2) : 0;
}

Size normalize(int width, int height)
{
    return Size {
        std::min(std::max(evenDown(width), k_MinSide), k_MaxSide),
        std::min(std::max(evenDown(height), k_MinSide), k_MaxSide),
    };
}

Size fitInBox(double ratio, Size box)
{
    box.width = evenDown(box.width);
    box.height = evenDown(box.height);
    if (!(ratio > 0) || box.width <= 0 || box.height <= 0) {
        return Size();
    }

    // Too wide for the box when the full height is used: the width limits, else the height
    if (box.height * ratio > box.width + k_Epsilon) {
        int height = static_cast<int>(std::floor(box.width / ratio + k_Epsilon));
        return Size { box.width, std::min(evenDown(height), box.height) };
    }

    int width = static_cast<int>(std::floor(box.height * ratio + k_Epsilon));
    return Size { std::min(evenDown(width), box.width), box.height };
}

std::vector<Preset> presetsFor(double ratio, Size box)
{
    std::vector<Preset> candidates;
    if (!(ratio > 0)) {
        return candidates;
    }

    // Well-known sizes first, since each one replaces the generated size at its height
    std::vector<Size> wellKnown;
    for (const Size& size : k_WellKnown) {
        if (std::fabs(static_cast<double>(size.width) / size.height / ratio - 1) <= k_Tolerance) {
            wellKnown.push_back(size);
            candidates.push_back(Preset { size.width, size.height, false, false });
        }
    }

    for (int height : k_Heights) {
        bool replaced = std::any_of(wellKnown.begin(), wellKnown.end(),
                                    [height](const Size& size) { return size.height == height; });
        if (!replaced) {
            candidates.push_back(Preset { linkedWidth(height, ratio), height, false, false });
        }
    }

    Size fit = fitInBox(ratio, box);
    if (fit.width > 0) {
        candidates.push_back(Preset { fit.width, fit.height, true, false });
    }

    bool haveBox = box.width > 0 && box.height > 0;
    std::vector<Preset> presets;
    for (Preset candidate : candidates) {
        if (!inRange(Size { candidate.width, candidate.height })) {
            continue;
        }
        candidate.largerThanDisplay = haveBox && (candidate.width > box.width || candidate.height > box.height);

        // The same size again (a generated one that is also well-known, or the fit): keep one
        auto same = std::find_if(presets.begin(), presets.end(), [&candidate](const Preset& preset) {
            return preset.width == candidate.width && preset.height == candidate.height;
        });
        if (same != presets.end()) {
            same->fillsDisplay = same->fillsDisplay || candidate.fillsDisplay;
        }
        else {
            presets.push_back(candidate);
        }
    }

    std::sort(presets.begin(), presets.end(), [](const Preset& a, const Preset& b) {
        long long pixelsA = pixels(Size { a.width, a.height });
        long long pixelsB = pixels(Size { b.width, b.height });
        return pixelsA != pixelsB ? pixelsA < pixelsB : a.width < b.width;
    });
    return presets;
}

double parseRatio(const std::string& text)
{
    std::string width = trim(text);
    std::string height = "1";

    size_t colon = width.find(':');
    if (colon != std::string::npos) {
        height = trim(width.substr(colon + 1));
        width = trim(width.substr(0, colon));
    }

    double w, h;
    if (!parseNumber(width, &w) || !parseNumber(height, &h) || w <= 0 || h <= 0) {
        return 0;
    }

    double ratio = w / h;
    return ratio >= 1.0 / 32 && ratio <= 32 ? ratio : 0;
}

int linkedHeight(int width, double ratio)
{
    return roundedEven(width > 0 && ratio > 0 ? width / ratio : 0);
}

int linkedWidth(int height, double ratio)
{
    return roundedEven(height > 0 && ratio > 0 ? height * ratio : 0);
}

}
