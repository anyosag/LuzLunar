// Unit tests for app/fork/forkaspect.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/aspect_test.cpp app/fork/forkaspect.cpp
#include "fork/forkaspect.h"

#include <cmath>
#include <cstdio>

using namespace ForkAspect;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

// The preset with this size, or null
static const Preset* find(const std::vector<Preset>& presets, int width, int height)
{
    for (const Preset& preset : presets) {
        if (preset.width == width && preset.height == height) {
            return &preset;
        }
    }
    return nullptr;
}

static bool has(const std::vector<Preset>& presets, int width, int height)
{
    return find(presets, width, height) != nullptr;
}

// Smallest first, no duplicates, every side even and between 256 and 8192
static bool wellFormed(const std::vector<Preset>& presets)
{
    for (size_t i = 0; i < presets.size(); i++) {
        const Preset& preset = presets[i];
        if (preset.width % 2 != 0 || preset.height % 2 != 0 ||
                preset.width < k_MinSide || preset.width > k_MaxSide ||
                preset.height < k_MinSide || preset.height > k_MaxSide) {
            return false;
        }
        if (i > 0) {
            const Preset& before = presets[i - 1];
            if (static_cast<long long>(preset.width) * preset.height <=
                    static_cast<long long>(before.width) * before.height) {
                return false;
            }
        }
    }
    return true;
}

static int fillCount(const std::vector<Preset>& presets)
{
    int count = 0;
    for (const Preset& preset : presets) {
        count += preset.fillsDisplay ? 1 : 0;
    }
    return count;
}

int main()
{
    // The two shapes of a 14" MacBook Pro's display: the area below the notch is 16:10, the full
    // panel (with the strip beside the notch) is about 1.54:1
    const Size below { 3024, 1890 };
    const Size full { 3024, 1964 };

    // Even rounding goes down, and sides stay between 256 and 8192
    CHECK(evenDown(945) == 944);
    CHECK(evenDown(944) == 944);
    CHECK(evenDown(1) == 0);
    CHECK(evenDown(0) == 0);
    CHECK(evenDown(-7) == 0);
    CHECK(normalize(945, 601).width == 944);
    CHECK(normalize(945, 601).height == 600);
    CHECK(normalize(100, 255).width == 256);
    CHECK(normalize(100, 255).height == 256);
    CHECK(normalize(9000, 8193).width == 8192);
    CHECK(normalize(9000, 8193).height == 8192);
    CHECK(normalize(8191, 257).width == 8190);
    CHECK(normalize(8191, 257).height == 256);
    CHECK(normalize(1920, 1080).width == 1920);
    CHECK(normalize(1920, 1080).height == 1080);
    CHECK(normalize(0, -5).width == 256);

    // The largest even size that fits: one side exact, the other rounded down
    Size fit = fitInBox(16.0 / 9, below);
    CHECK(fit.width == 3024 && fit.height == 1700);
    fit = fitInBox(64.0 / 27, below);
    CHECK(fit.width == 3024 && fit.height == 1274);
    fit = fitInBox(4.0 / 3, below);
    CHECK(fit.width == 2520 && fit.height == 1890);
    fit = fitInBox(32.0 / 9, below);
    CHECK(fit.width == 3024 && fit.height == 850);
    fit = fitInBox(16.0 / 10, below);
    CHECK(fit.width == 3024 && fit.height == 1890);
    fit = fitInBox(1.0, below);
    CHECK(fit.width == 1890 && fit.height == 1890);
    fit = fitInBox(3.0 / 2, below);
    CHECK(fit.width == 2834 && fit.height == 1890);
    fit = fitInBox(5.0 / 4, below);
    CHECK(fit.width == 2362 && fit.height == 1890);

    // The full panel's own ratio gives the panel, exactly
    fit = fitInBox(3024.0 / 1964, full);
    CHECK(fit.width == 3024 && fit.height == 1964);
    fit = fitInBox(3024.0 / 1890, below);
    CHECK(fit.width == 3024 && fit.height == 1890);

    // A portrait ratio, an odd box and nonsense
    fit = fitInBox(9.0 / 16, below);
    CHECK(fit.width == 1062 && fit.height == 1890);
    fit = fitInBox(16.0 / 9, Size { 1365, 767 });
    CHECK(fit.width == 1360 && fit.height == 766);
    CHECK(fitInBox(0, below).width == 0);
    CHECK(fitInBox(-1, below).width == 0);
    CHECK(fitInBox(16.0 / 9, Size { 0, 1080 }).width == 0);
    CHECK(fitInBox(std::nan(""), below).width == 0);

    // 16:9 in the area below the notch
    std::vector<Preset> presets = presetsFor(16.0 / 9, below);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 2560, 1440));
    CHECK(has(presets, 1920, 1080));
    CHECK(has(presets, 1280, 720));
    CHECK(has(presets, 3840, 2160));
    CHECK(has(presets, 5120, 2880));
    CHECK(has(presets, 3024, 1700));
    CHECK(presets.size() == 6);
    CHECK(fillCount(presets) == 1);
    CHECK(find(presets, 3024, 1700)->fillsDisplay);
    CHECK(!find(presets, 3024, 1700)->largerThanDisplay);
    CHECK(!find(presets, 2560, 1440)->fillsDisplay);
    CHECK(!find(presets, 2560, 1440)->largerThanDisplay);
    CHECK(find(presets, 3840, 2160)->largerThanDisplay);
    CHECK(find(presets, 5120, 2880)->largerThanDisplay);
    CHECK(!find(presets, 3840, 2160)->fillsDisplay);

    // 21:9 is 64:27, so the ultrawide sizes are in, and 3440x1440 replaces the generated 3412x1440
    presets = presetsFor(64.0 / 27, below);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 2560, 1080));
    CHECK(has(presets, 3440, 1440));
    CHECK(has(presets, 5120, 2160));
    CHECK(has(presets, 3024, 1274));
    CHECK(!has(presets, 3412, 1440));
    CHECK(find(presets, 3024, 1274)->fillsDisplay);
    CHECK(find(presets, 3440, 1440)->largerThanDisplay);
    CHECK(!find(presets, 2560, 1080)->largerThanDisplay);
    CHECK(fillCount(presets) == 1);

    // 32:9 has the super ultrawide sizes, and 2880 lines would be too wide
    presets = presetsFor(32.0 / 9, below);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 3840, 1080));
    CHECK(has(presets, 5120, 1440));
    CHECK(has(presets, 3024, 850));
    CHECK(has(presets, 7680, 2160));
    CHECK(!has(presets, 10240, 2880));
    CHECK(find(presets, 3024, 850)->fillsDisplay);

    // 16:10 has the usual laptop sizes, and the area below the notch fills itself
    presets = presetsFor(16.0 / 10, below);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 1280, 800));
    CHECK(has(presets, 1440, 900));
    CHECK(has(presets, 1680, 1050));
    CHECK(has(presets, 1920, 1200));
    CHECK(has(presets, 2560, 1600));
    CHECK(has(presets, 3024, 1890));
    CHECK(find(presets, 3024, 1890)->fillsDisplay);
    CHECK(!find(presets, 3024, 1890)->largerThanDisplay);
    CHECK(find(presets, 3456, 2160)->largerThanDisplay);

    // The full panel: its own size fills, with the ratio as 3024/1964
    presets = presetsFor(3024.0 / 1964, full);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 3024, 1964));
    CHECK(find(presets, 3024, 1964)->fillsDisplay);
    CHECK(!find(presets, 3024, 1964)->largerThanDisplay);
    CHECK(fillCount(presets) == 1);
    CHECK(!has(presets, 1920, 1200));

    // 4:3, 5:4 and 3:2 have their well-known sizes
    presets = presetsFor(4.0 / 3, below);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 1024, 768));
    CHECK(has(presets, 1600, 1200));
    CHECK(has(presets, 2048, 1536));
    CHECK(has(presets, 2520, 1890));
    presets = presetsFor(5.0 / 4, below);
    CHECK(has(presets, 1280, 1024));
    presets = presetsFor(3.0 / 2, below);
    CHECK(has(presets, 1920, 1280));
    CHECK(has(presets, 2560, 1700));

    // A square one: nothing well-known, and sizes below 256 never show
    presets = presetsFor(1.0, below);
    CHECK(wellFormed(presets));
    CHECK(has(presets, 720, 720));
    CHECK(has(presets, 1890, 1890));
    CHECK(has(presets, 2880, 2880));

    // A very wide ratio: only sizes within 8192 wide are left, and a 12:1 one has none (252 lines fit)
    presets = presetsFor(10.0, below);
    CHECK(wellFormed(presets));
    CHECK(presets.size() == 2);
    CHECK(has(presets, 3024, 302));
    CHECK(has(presets, 7200, 720));
    CHECK(!has(presets, 10800, 1080));
    CHECK(presetsFor(12.0, below).empty());

    // With no display nothing fills it and nothing is larger
    presets = presetsFor(16.0 / 9, Size());
    CHECK(wellFormed(presets));
    CHECK(has(presets, 1920, 1080));
    CHECK(fillCount(presets) == 0);
    CHECK(!find(presets, 3840, 2160)->largerThanDisplay);

    // A display bigger than the largest size: its fit is dropped, not clamped
    presets = presetsFor(16.0 / 9, Size { 10000, 6000 });
    CHECK(wellFormed(presets));
    CHECK(fillCount(presets) == 0);
    CHECK(presetsFor(0, below).empty());
    CHECK(presetsFor(-2, below).empty());

    // A well-known size that is the display itself gets both marks of it
    presets = presetsFor(16.0 / 10, Size { 2560, 1600 });
    CHECK(find(presets, 2560, 1600)->fillsDisplay);
    CHECK(!find(presets, 2560, 1600)->largerThanDisplay);
    CHECK(fillCount(presets) == 1);

    // Ratios written as W:H or a decimal
    CHECK(std::fabs(parseRatio("16:9") - 16.0 / 9) < 1e-9);
    CHECK(std::fabs(parseRatio("2.39:1") - 2.39) < 1e-9);
    CHECK(std::fabs(parseRatio("12:5") - 2.4) < 1e-9);
    CHECK(std::fabs(parseRatio("21:9") - 7.0 / 3) < 1e-9);
    CHECK(std::fabs(parseRatio("  4 : 3 ") - 4.0 / 3) < 1e-9);
    CHECK(std::fabs(parseRatio("2.39") - 2.39) < 1e-9);
    CHECK(std::fabs(parseRatio("2,39:1") - 2.39) < 1e-9);
    CHECK(std::fabs(parseRatio("9:16") - 9.0 / 16) < 1e-9);
    CHECK(std::fabs(parseRatio("1:1") - 1) < 1e-9);
    CHECK(std::fabs(parseRatio("1.85:1") - 1.85) < 1e-9);

    // Not ratios
    CHECK(parseRatio("abc") == 0);
    CHECK(parseRatio("") == 0);
    CHECK(parseRatio(":") == 0);
    CHECK(parseRatio("16:") == 0);
    CHECK(parseRatio(":9") == 0);
    CHECK(parseRatio("0:9") == 0);
    CHECK(parseRatio("16:0") == 0);
    CHECK(parseRatio("-16:9") == 0);
    CHECK(parseRatio("16:9:1") == 0);
    CHECK(parseRatio("16x9") == 0);
    CHECK(parseRatio("1.2.3:1") == 0);
    CHECK(parseRatio("1e3:1") == 0);
    CHECK(parseRatio("100:1") == 0);
    CHECK(parseRatio("1:100") == 0);

    // The aspect lock keeps the ratio and the other side even
    CHECK(linkedHeight(3440, 64.0 / 27) == 1450);
    CHECK(linkedHeight(1920, 16.0 / 9) == 1080);
    CHECK(linkedHeight(3024, 3024.0 / 1890) == 1890);
    CHECK(linkedHeight(1001, 16.0 / 9) == 562);
    CHECK(linkedWidth(1440, 64.0 / 27) == 3412);
    CHECK(linkedWidth(1080, 16.0 / 9) == 1920);
    CHECK(linkedWidth(1200, 16.0 / 10) == 1920);
    CHECK(linkedWidth(721, 16.0 / 9) == 1282);
    CHECK(linkedHeight(1920, 0) == 0);
    CHECK(linkedWidth(1080, -1) == 0);
    CHECK(linkedHeight(0, 1.5) == 0);
    CHECK(linkedWidth(1080, std::nan("")) == 0);
    CHECK(linkedWidth(1080, INFINITY) == 0);

    if (s_Failures == 0) {
        std::printf("All fork aspect ratio tests passed\n");
    }
    return s_Failures == 0 ? 0 : 1;
}
