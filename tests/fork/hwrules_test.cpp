// Unit tests for app/fork/forkhwrules.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/hwrules_test.cpp app/fork/forkhwrules.cpp
#include "fork/forkhwrules.h"

#include <cstdio>
#include <string>

using namespace ForkHwRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool contains(const std::vector<std::string>& warnings, const char* text)
{
    for (const std::string& warning : warnings) {
        if (warning.find(text) != std::string::npos) {
            return true;
        }
    }
    return false;
}

// Every warning is a sentence with exactly one full stop at the end
static bool wellFormed(const std::vector<std::string>& warnings)
{
    for (const std::string& warning : warnings) {
        if (warning.empty() || warning.back() != '.' || warning.find("..") != std::string::npos ||
                warning.find(" .") != std::string::npos) {
            return false;
        }
    }
    return true;
}

int main()
{
    // An M4 Pro MacBook Pro: everything in hardware, a 120 Hz HDR panel with a notch
    const Decoders all = { true, true, true, true };
    const Display builtin = { "Built-in Retina Display", 3024, 1964, 3024, 1890, 2.0, true, 120, true };

    // Plain settings give no warnings, whatever the codec
    const Codec codecs[] = { Codec::Auto, Codec::H264, Codec::HEVC, Codec::AV1 };
    for (Codec codec : codecs) {
        CHECK(checkStream(all, builtin, 3024, 1964, 120, codec, false).empty());
    }
    CHECK(checkStream(all, builtin, 1920, 1080, 60, Codec::Auto, true).empty());

    // H.264 stops at 4096 on either side, but only when it's forced
    CHECK(checkStream(all, builtin, 4096, 2160, 60, Codec::H264, false).empty());
    CHECK(checkStream(all, builtin, 2160, 4096, 60, Codec::H264, false).empty());
    CHECK(contains(checkStream(all, builtin, 4097, 2160, 60, Codec::H264, false), "H.264 above 4096"));
    CHECK(contains(checkStream(all, builtin, 2160, 4097, 60, Codec::H264, false), "H.264 above 4096"));
    CHECK(checkStream(all, builtin, 4097, 2160, 60, Codec::Auto, false).empty());
    CHECK(checkStream(all, builtin, 4097, 2160, 60, Codec::HEVC, false).empty());
    CHECK(checkStream(all, builtin, 4097, 2160, 60, Codec::AV1, false).empty());

    // A forced codec the hardware lacks. Automatic never warns, since it picks what works.
    const Decoders noAv1 = { true, true, true, false };
    const Decoders noHevc = { true, false, false, true };
    const Decoders noH264 = { false, true, true, true };
    CHECK(contains(checkStream(noAv1, builtin, 1920, 1080, 60, Codec::AV1, false), "no hardware AV1"));
    CHECK(checkStream(noAv1, builtin, 1920, 1080, 60, Codec::HEVC, false).empty());
    CHECK(checkStream(noAv1, builtin, 1920, 1080, 60, Codec::Auto, false).empty());
    CHECK(contains(checkStream(noHevc, builtin, 1920, 1080, 60, Codec::HEVC, false), "no hardware HEVC"));
    CHECK(checkStream(noHevc, builtin, 1920, 1080, 60, Codec::AV1, false).empty());
    CHECK(contains(checkStream(noH264, builtin, 1920, 1080, 60, Codec::H264, false), "no hardware H.264"));
    CHECK(checkStream(noH264, builtin, 1920, 1080, 60, Codec::HEVC, false).empty());
    // Without H.264 hardware at all, the size warning would only repeat it
    CHECK(checkStream(noH264, builtin, 4097, 2160, 60, Codec::H264, false).size() == 1);

    // HDR needs HEVC Main10 or AV1 in hardware; either one is enough
    const Decoders noMain10 = { true, true, false, false };
    const Decoders main10Only = { true, true, true, false };
    const Decoders av1Only = { true, true, false, true };
    CHECK(contains(checkStream(noMain10, builtin, 1920, 1080, 60, Codec::Auto, true), "HDR needs hardware HEVC Main10 or AV1"));
    CHECK(checkStream(noMain10, builtin, 1920, 1080, 60, Codec::Auto, false).empty());
    CHECK(checkStream(main10Only, builtin, 1920, 1080, 60, Codec::Auto, true).empty());
    CHECK(checkStream(av1Only, builtin, 1920, 1080, 60, Codec::Auto, true).empty());
    CHECK(!contains(checkStream(all, builtin, 1920, 1080, 60, Codec::HEVC, true), "HDR"));
    // No decoders at all, like a VM
    CHECK(contains(checkStream(Decoders(), builtin, 1920, 1080, 60, Codec::Auto, true), "HDR needs hardware"));
    // Moonlight turns HDR off for H.264
    CHECK(contains(checkStream(all, builtin, 1920, 1080, 60, Codec::H264, true), "HDR needs HEVC or AV1"));

    // Either side above 8192
    CHECK(checkStream(all, builtin, 8192, 4320, 60, Codec::Auto, false).empty());
    CHECK(checkStream(all, builtin, 4320, 8192, 60, Codec::Auto, false).empty());
    CHECK(contains(checkStream(all, builtin, 8194, 4320, 60, Codec::Auto, false), "above 8192"));
    CHECK(contains(checkStream(all, builtin, 4320, 8194, 60, Codec::Auto, false), "above 8192"));
    CHECK(contains(checkStream(all, builtin, 8193, 4320, 60, Codec::Auto, false), "above 8192"));

    // The frame rate may be 5 above the display's refresh rate
    CHECK(checkStream(all, builtin, 1920, 1080, 120, Codec::Auto, false).empty());
    CHECK(checkStream(all, builtin, 1920, 1080, 125, Codec::Auto, false).empty());
    CHECK(contains(checkStream(all, builtin, 1920, 1080, 126, Codec::Auto, false), "up to 120 Hz, so frames above that are dropped"));
    CHECK(contains(checkStream(all, builtin, 1920, 1080, 240, Codec::Auto, false), "Built-in Retina Display refreshes"));
    // The same frame rate is fine on a faster display, and an unknown refresh rate never warns
    Display fast = builtin;
    fast.maxRefresh = 144;
    CHECK(checkStream(all, fast, 1920, 1080, 144, Codec::Auto, false).empty());
    CHECK(contains(checkStream(all, fast, 1920, 1080, 150, Codec::Auto, false), "up to 144 Hz"));
    Display unknown = builtin;
    unknown.maxRefresh = 0;
    CHECK(checkStream(all, unknown, 1920, 1080, 240, Codec::Auto, false).empty());
    // A display without a name still reads well
    Display unnamed = builtin;
    unnamed.name.clear();
    CHECK(contains(checkStream(all, unnamed, 1920, 1080, 240, Codec::Auto, false), "This display refreshes at up to 120 Hz"));

    // Several problems give several warnings, each a plain sentence
    std::vector<std::string> many = checkStream(noMain10, builtin, 8194, 4320, 240, Codec::Auto, true);
    CHECK(many.size() == 3);
    CHECK(wellFormed(many));
    std::vector<std::string> forced = checkStream(Decoders(), builtin, 8194, 4320, 240, Codec::AV1, true);
    CHECK(forced.size() == 4);
    CHECK(wellFormed(forced));
    CHECK(wellFormed(checkStream(all, builtin, 4097, 4097, 240, Codec::H264, true)));

    // Names for the usual ratios
    CHECK(ratioLabel(3024, 1890) == "16:10");
    CHECK(ratioLabel(1920, 1080) == "16:9");
    CHECK(ratioLabel(3840, 2160) == "16:9");
    CHECK(ratioLabel(2560, 1600) == "16:10");
    CHECK(ratioLabel(1920, 1200) == "16:10");
    CHECK(ratioLabel(2048, 1536) == "4:3");
    CHECK(ratioLabel(1280, 1024) == "5:4");
    CHECK(ratioLabel(3000, 2000) == "3:2");
    CHECK(ratioLabel(1000, 1000) == "1:1");
    CHECK(ratioLabel(5120, 1440) == "32:9");

    // Ultrawide: 64:27 (2560x1080), 7:3 and 3440x1440 in between are all called 21:9
    CHECK(ratioLabel(2560, 1080) == "21:9");
    CHECK(ratioLabel(5120, 2160) == "21:9");
    CHECK(ratioLabel(3440, 1440) == "21:9");
    CHECK(ratioLabel(2520, 1080) == "21:9");

    // Within 1%: 1366x768 is 683:384, which is 16:9 in practice
    CHECK(ratioLabel(1366, 768) == "16:9");
    CHECK(ratioLabel(1400, 768) != "16:9");

    // The notched panel's full shape is none of the usual ratios
    CHECK(ratioLabel(3024, 1964) == "1.54:1");
    CHECK(ratioLabel(1512, 982) == "1.54:1");

    // Not a usual ratio: a small reduced one if there is one, else a decimal
    CHECK(ratioLabel(1900, 1000) == "19:10");
    CHECK(ratioLabel(2000, 1000) == "2:1");
    CHECK(ratioLabel(3840, 1600) == "12:5");
    CHECK(ratioLabel(4096, 2160) == "1.90:1");
    CHECK(ratioLabel(3999, 1000) == "4.00:1");

    // Portrait sizes turn the label around, and nonsense gives nothing
    CHECK(ratioLabel(1080, 1920) == "9:16");
    CHECK(ratioLabel(1890, 3024) == "10:16");
    CHECK(ratioLabel(1964, 3024) == "1:1.54");
    CHECK(ratioLabel(0, 1080).empty());
    CHECK(ratioLabel(1920, 0).empty());
    CHECK(ratioLabel(-1920, 1080).empty());

    if (s_Failures == 0) {
        std::printf("All fork hardware rules tests passed\n");
    }
    return s_Failures == 0 ? 0 : 1;
}
