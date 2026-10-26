// Unit tests for app/fork/forkdisplaygroup.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/displaygroup_test.cpp app/fork/forkdisplaygroup.cpp app/fork/clientdisplay.cpp
#include "fork/forkdisplaygroup.h"

#include <cstdio>
#include <string>

using namespace ForkDisplayGroup;

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

// A 14" MacBook Pro's built-in screen, streamed below the notch
static MacDisplay builtin()
{
    MacDisplay d;
    d.id = 1;
    d.x = 0;
    d.y = 0;
    d.pointWidth = 1512;
    d.pointHeight = 982;
    d.width = 3024;
    d.height = 1890;
    d.maxRefresh = 120;
    d.isMain = true;
    d.isBuiltin = true;
    d.hdr = true;
    d.name = "Built-in Liquid Retina XDR Display";
    d.screen.panelWidth = 3024;
    d.screen.panelHeight = 1964;
    d.screen.safeWidth = 3024;
    d.screen.safeHeight = 1890;
    d.screen.maxRefresh = 120;
    d.screen.hdr = true;
    d.screen.p3 = true;
    d.screen.name = d.name;
    return d;
}

// DisplayExtend's virtual display for the iMac, to the right of the built-in one and 98 points higher
static MacDisplay displayExtend()
{
    MacDisplay d;
    d.id = 7;
    d.x = 1512;
    d.y = -98;
    d.pointWidth = 1920;
    d.pointHeight = 1080;
    d.width = 1920;
    d.height = 1080;
    d.maxRefresh = 60;
    d.isDisplayExtend = true;
    d.vendor = 0x444D;
    d.model = 1;
    d.serial = 0x444445;
    d.name = "DisplayExtend (iMac)";
    d.screen.widthMm = 476;
    d.screen.heightMm = 268;
    d.screen.panelWidth = 1920;
    d.screen.panelHeight = 1080;
    d.screen.safeWidth = 1920;
    d.screen.safeHeight = 1080;
    d.screen.maxRefresh = 60;
    d.screen.name = d.name;
    return d;
}

static Stream stream0()
{
    Stream s;
    s.width = 3024;
    s.height = 1890;
    s.fps = 120;
    s.bitrateKbps = 80000;
    s.hdr = true;
    return s;
}

static void testTwoDisplays()
{
    Plan p = plan({ displayExtend(), builtin() }, stream0(), 4, "0123456789abcdef");
    CHECK(p.id == "0123456789abcdef");
    CHECK(p.slotList.size() == 2);
    if (p.slotList.size() != 2) {
        return;
    }

    // The built-in display is slot 0, with the stream's own settings
    const Slot& s0 = p.slotList[0];
    CHECK(s0.slot == 0 && s0.displayId == 1);
    CHECK(s0.width == 3024 && s0.height == 1890 && s0.fps == 120 && s0.bitrateKbps == 80000 && s0.hdr);
    CHECK(s0.x == 0 && s0.y == 0 && !s0.external);

    // DisplayExtend's display streams its own size at its refresh rate, without HDR, and is external
    const Slot& s1 = p.slotList[1];
    CHECK(s1.slot == 1 && s1.displayId == 7 && s1.external);
    CHECK(s1.width == 1920 && s1.height == 1080 && s1.fps == 60 && !s1.hdr);
    // 1920x1080x60 is about 18% of 3024x1890x120's pixel rate
    CHECK(s1.bitrateKbps > 14000 && s1.bitrateKbps < 15000);

    // To the right, 98 of 982 points higher: about 10% of slot 0's 1890 pixels
    CHECK(s1.x == 3024);
    CHECK(s1.y == -189);
}

static void testMainDisplay()
{
    MacDisplay dx = displayExtend();
    MacDisplay mac = builtin();
    CHECK(mainIndex({ mac, dx }) == 0);

    // DisplayExtend's display as the main one: slot 0 goes to the built-in display
    dx.isMain = true;
    mac.isMain = false;
    CHECK(mainIndex({ dx, mac }) == 1);

    // An external monitor as the main one keeps slot 0
    MacDisplay monitor = displayExtend();
    monitor.isDisplayExtend = false;
    monitor.isMain = true;
    CHECK(mainIndex({ mac, monitor }) == 1);

    CHECK(mainIndex({}) == -1);
}

static void testNoGroup()
{
    // One display, a host offering one slot, or no stream size: no group
    CHECK(plan({ builtin() }, stream0(), 4, "x").slotList.empty());
    CHECK(plan({ builtin(), displayExtend() }, stream0(), 1, "x").slotList.empty());
    Stream none;
    CHECK(plan({ builtin(), displayExtend() }, none, 4, "x").slotList.empty());

    // A display whose size can't be read is left out, which can leave too few
    MacDisplay unknown = displayExtend();
    unknown.width = unknown.height = 0;
    CHECK(plan({ builtin(), unknown }, stream0(), 4, "x").slotList.empty());
}

static void testSlotOrderAndLimit()
{
    MacDisplay left = displayExtend();
    left.isDisplayExtend = false;
    left.id = 3;
    left.vendor = 0x10AC;
    left.x = -1920;
    left.y = 0;
    left.name = "Left";

    MacDisplay above = left;
    above.id = 4;
    above.vendor = 0x05E3;
    above.x = 0;
    above.y = -1080;
    above.pointWidth = 1920;
    above.name = "Above";

    // Monitors before DisplayExtend's display, in vendor order, whatever order macOS lists them in
    Plan p = plan({ displayExtend(), left, builtin(), above }, stream0(), 8, "x");
    CHECK(p.slotList.size() == 4);
    if (p.slotList.size() == 4) {
        CHECK(p.slotList[0].displayId == 1);
        CHECK(p.slotList[1].displayId == 4);
        CHECK(p.slotList[2].displayId == 3);
        CHECK(p.slotList[3].displayId == 7);

        // Above: below-left aligned with slot 0's top-left; left: ends where slot 0 starts
        CHECK(p.slotList[1].x == 0 && p.slotList[1].y == -1080);
        CHECK(p.slotList[2].x == -1920 && p.slotList[2].y == 0);
    }

    // At most what the host offers, DisplayExtend's display dropped first
    p = plan({ displayExtend(), left, builtin(), above }, stream0(), 3, "x");
    CHECK(p.slotList.size() == 3);
    if (p.slotList.size() == 3) {
        CHECK(p.slotList[2].displayId == 3);
    }
}

static void testLayout()
{
    // A display below another, scaled: the fraction along the edge is kept
    std::vector<Rect> mac = { { 0, 0, 1000, 500 }, { 500, 500, 1000, 500 } };
    std::vector<Rect> pixels = { { 0, 0, 2000, 1000 }, { 0, 0, 1000, 500 } };
    std::vector<Rect> layout = windowsLayout(mac, pixels, 0);
    CHECK(layout[0].x == 0 && layout[0].y == 0);
    CHECK(layout[1].x == 1000 && layout[1].y == 1000);

    // A display offset so far it would no longer touch after scaling still touches
    mac = { { 0, 0, 1000, 500 }, { 1000, 490, 300, 300 } };
    pixels = { { 0, 0, 500, 250 }, { 0, 0, 3000, 3000 } };
    layout = windowsLayout(mac, pixels, 0);
    CHECK(layout[1].x == 500);
    CHECK(layout[1].y >= -2999 && layout[1].y <= 249);

    // Two displays on the right of the first, stacked: placed without overlapping
    mac = { { 0, 0, 1000, 1000 }, { 1000, 0, 1000, 500 }, { 1000, 500, 1000, 500 } };
    pixels = { { 0, 0, 1000, 1000 }, { 0, 0, 1000, 600 }, { 0, 0, 1000, 600 } };
    layout = windowsLayout(mac, pixels, 0);
    CHECK(layout[1].x == 1000 && layout[1].y == 0);
    CHECK(layout[2].y >= 600 || layout[2].x >= 2000);

    // A display touching nothing goes at the end of the row
    mac = { { 0, 0, 1000, 1000 }, { 5000, 5000, 100, 100 } };
    pixels = { { 0, 0, 1000, 1000 }, { 0, 0, 100, 100 } };
    layout = windowsLayout(mac, pixels, 0);
    CHECK(layout[1].x == 1000 && layout[1].y == 0);

    // The first display is the origin even when it isn't listed first
    mac = { { -1000, 0, 1000, 1000 }, { 0, 0, 1000, 1000 } };
    pixels = { { 0, 0, 1000, 1000 }, { 0, 0, 1000, 1000 } };
    layout = windowsLayout(mac, pixels, 1);
    CHECK(layout[1].x == 0 && layout[1].y == 0);
    CHECK(layout[0].x == -1000 && layout[0].y == 0);
}

static void testDeclaration()
{
    Plan p = plan({ builtin(), displayExtend() }, stream0(), 4, "00ff00ff00ff00ff");
    std::string json = declarationJson(p);
    CHECK(json.rfind("{\"v\":1,\"id\":\"00ff00ff00ff00ff\",\"slots\":[{\"slot\":0,\"x\":0,\"y\":0},", 0) == 0);
    CHECK(contains(json, "{\"slot\":1,\"w\":1920,\"h\":1080,\"fps\":60,\"x\":3024,\"y\":-189,\"external\":true,\"hdr\":false,\"screen\":"));
    CHECK(contains(json, "\"screen\":{\"mm\":\"476x268\",\"panel\":\"1920x1080\",\"safe\":\"1920x1080\",\"hz\":\"60\",\"gamut\":\"srgb\",\"hdr\":\"none\",\"name\":\"DisplayExtend (iMac)\"}"));
    CHECK(json.size() > 2 && json.compare(json.size() - 2, 2, "]}") == 0);

    std::string args = launchArgs(p);
    CHECK(args.rfind("&luzGroup=", 0) == 0);
    CHECK(args.find_first_of("+/=", 10) == std::string::npos);
    CHECK(args.substr(10) == base64Url(json));

    CHECK(launchArgs(Plan()).empty());
    CHECK(joinArgs("00ff00ff00ff00ff", 2) == "&luzGroupId=00ff00ff00ff00ff&luzSlot=2");
}

static void testScreenJson()
{
    ClientDisplay::Description d;
    d.panelWidth = 3024;
    d.panelHeight = 1964;
    d.safeWidth = 3024;
    d.safeHeight = 1890;
    d.hdr = true;
    d.peakNits = 1600;
    d.fullFrameNits = 1000;
    d.minLuminance = 50;
    d.p3 = true;
    CHECK(screenJson(d) == "{\"panel\":\"3024x1964\",\"safe\":\"3024x1890\",\"gamut\":\"p3\",\"hdr\":\"1600,1000,50\"}");

    d.peakNits = 0;
    CHECK(contains(screenJson(d), "\"hdr\":\"unknown\""));
}

static void testEncoding()
{
    CHECK(base64Url("") == "");
    CHECK(base64Url("f") == "Zg");
    CHECK(base64Url("fo") == "Zm8");
    CHECK(base64Url("foo") == "Zm9v");
    CHECK(base64Url("foob") == "Zm9vYg");
    CHECK(base64Url(std::string("\xfb\xff\xbf", 3)) == "-_-_");

    CHECK(jsonString("plain") == "\"plain\"");
    CHECK(jsonString("a \"b\" \\ c") == "\"a \\\"b\\\" \\\\ c\"");
    CHECK(jsonString(std::string("\n\x01", 2)) == "\"\\n\\u0001\"");
    CHECK(jsonString("Écran") == "\"Écran\"");
}

int main()
{
    testTwoDisplays();
    testMainDisplay();
    testNoGroup();
    testSlotOrderAndLimit();
    testLayout();
    testDeclaration();
    testScreenJson();
    testEncoding();

    if (s_Failures > 0) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("All display group tests passed\n");
    return 0;
}
