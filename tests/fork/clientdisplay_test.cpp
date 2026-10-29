// Unit tests for app/fork/clientdisplay.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/clientdisplay_test.cpp app/fork/clientdisplay.cpp
#include "fork/clientdisplay.h"

#include <cstdio>
#include <string>

using namespace ClientDisplay;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool contains(const std::string& text, const char* part)
{
    return text.find(part) != std::string::npos;
}

// A 14" MacBook Pro's built-in screen
static ForkHwRules::Display macbookPro14()
{
    ForkHwRules::Display d { "Built-in Liquid Retina XDR Display", 3024, 1964, 3024, 1890, 2.0, true, 120, true };
    d.widthMm = 302;
    d.heightMm = 196;
    d.p3 = true;
    d.edrPotential = 16.0;
    d.minRefresh = 24;
    return d;
}

static void testMacBook()
{
    Description d = describe(macbookPro14(), true, 0);
    CHECK(d.hdr && d.peakNits == 1600 && d.fullFrameNits == 1000 && d.minLuminance == 50);
    CHECK(d.p3);
    CHECK(d.safeWidth == 3024 && d.safeHeight == 1890);

    std::string args = queryArgs(d);
    CHECK(args.rfind("&luzDisplay=1", 0) == 0);
    CHECK(contains(args, "&luzMm=302x196"));
    CHECK(contains(args, "&luzPanel=3024x1964&luzSafe=3024x1890"));
    CHECK(contains(args, "&luzHz=120"));
    CHECK(contains(args, "&luzGamut=p3"));
    CHECK(contains(args, "&luzHdr=1600,1000,50"));
    CHECK(contains(args, "&luzEdr=1600"));
    CHECK(contains(args, "&luzName=Built-in%20Liquid%20Retina%20XDR%20Display"));
}

static void testOverride()
{
    // A user's peak wins, for any HDR screen
    Description d = describe(macbookPro14(), true, 1000);
    CHECK(d.peakNits == 1000 && d.fullFrameNits == 1000 && d.minLuminance == 0);

    // and never makes an SDR screen HDR
    ForkHwRules::Display sdr = macbookPro14();
    sdr.hdr = false;
    d = describe(sdr, true, 1000);
    CHECK(!d.hdr && d.peakNits == 0);
    CHECK(contains(queryArgs(d), "&luzHdr=none"));
}

static void testUnknownHdr()
{
    // An external HDR monitor: HDR, but its brightness isn't known
    ForkHwRules::Display external { "LG HDR 4K", 3840, 2160, 3840, 2160, 1.0, false, 60, true };
    external.edrPotential = 4.0;
    Description d = describe(external, false, 0);
    CHECK(d.hdr && d.peakNits == 0);
    std::string args = queryArgs(d);
    CHECK(contains(args, "&luzHdr=unknown"));
    CHECK(contains(args, "&luzGamut=srgb"));
    CHECK(!contains(args, "&luzMm="));
    CHECK(contains(args, "&luzSafe=3840x2160"));

    // A built-in panel that isn't XDR
    ForkHwRules::Display air = macbookPro14();
    air.edrPotential = 2.0;
    CHECK(describe(air, true, 0).peakNits == 0);
}

static void testEdges()
{
    // Nothing to send without a size
    ForkHwRules::Display empty;
    CHECK(queryArgs(describe(empty, false, 0)).empty());

    // No safe area given: the panel's size
    ForkHwRules::Display noSafe { "Display 2", 2560, 1440, 0, 0, 1.0, false, 0, false };
    std::string args = queryArgs(describe(noSafe, false, 0));
    CHECK(contains(args, "&luzSafe=2560x1440"));
    CHECK(!contains(args, "&luzHz="));
    CHECK(contains(args, "&luzName=Display%202"));

    CHECK(percentEncode("A&b=c d/é") == "A%26b%3Dc%20d%2F%C3%A9");

    // Names stop at 63 bytes, never inside a character
    ForkHwRules::Display longName = noSafe;
    longName.name = std::string(62, 'a') + "\xc3\xa9";
    CHECK(describe(longName, false, 0).name == std::string(62, 'a'));
}

static void testPrimary()
{
    // Apollo reads this name (vdisplay_primary_policy::k_arg) and only the value 1
    CHECK(primaryArg(true) == "&luzPrimary=1");
    CHECK(primaryArg(false).empty());
}

int main()
{
    testMacBook();
    testOverride();
    testUnknownHdr();
    testEdges();
    testPrimary();

    if (s_Failures) {
        std::printf("%d client display checks failed\n", s_Failures);
        return 1;
    }
    std::printf("All client display tests passed\n");
    return 0;
}
