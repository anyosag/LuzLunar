// Unit tests for app/fork/pccardrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/pccardrules_test.cpp
#include "fork/pccardrules.h"

#include <cstdio>

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

using namespace PcCardRules;

static Inputs onlinePaired()
{
    Inputs in;
    in.online = true;
    in.paired = in.knownPaired = true;
    in.wakeable = true;
    return in;
}

static Inputs awayPaired()
{
    Inputs in;
    in.knownPaired = true;
    in.wakeable = true;
    return in;
}

static void testOnline()
{
    Inputs in = onlinePaired();
    CHECK(state(in) == "ready");
    in.running = true;
    CHECK(state(in) == "streaming");

    // Not paired wins over everything else, a running app included
    in.paired = false;
    CHECK(state(in) == "pair");
    in.paired = in.knownPaired = false;
    in.running = false;
    in.wakeable = false;
    CHECK(state(in) == "pair");

    // Online beats a stale waking flag
    in = onlinePaired();
    in.waking = true;
    in.wakeTimedOut = true;
    CHECK(state(in) == "ready");
}

static void testGoingDown()
{
    // Sleep PC was just accepted: the card already shows the result while the PC still answers
    Inputs in = onlinePaired();
    in.running = true;
    in.powerAction = "sleep";
    in.powerActionAgeSecs = 5;
    CHECK(state(in) == "asleep");

    in.powerAction = "off";
    in.wakeFromOff = "ready";
    CHECK(state(in) == "off");
    in.wakeFromOff = "fixable";
    CHECK(state(in) == "offNoWake");
    in.wakeFromOff = "";
    CHECK(state(in) == "offNoWake");

    // The PC didn't go: after k_GoingDownSecs it is ready again
    in.powerActionAgeSecs = k_GoingDownSecs - 1;
    CHECK(state(in) == "offNoWake");
    in.powerActionAgeSecs = k_GoingDownSecs;
    CHECK(state(in) == "streaming");

    // An unknown age doesn't count
    in.powerActionAgeSecs = -1;
    CHECK(state(in) == "streaming");
}

static void testAway()
{
    Inputs in = awayPaired();
    CHECK(state(in) == "asleep");                 // nothing known about how it went down
    in.powerAction = "sleep";
    CHECK(state(in) == "asleep");

    in.powerAction = "off";
    in.wakeFromOff = "ready";
    CHECK(state(in) == "off");
    for (const char* value : { "fixable", "blocked", "unknown", "", "unsupported" }) {
        in.wakeFromOff = value;
        CHECK(state(in) == "offNoWake");
    }

    // The wake-from-off answer doesn't matter for a PC that only sleeps
    in.powerAction = "";
    in.wakeFromOff = "blocked";
    CHECK(state(in) == "asleep");
}

static void testLost()
{
    Inputs in = awayPaired();
    in.wakeable = false;                          // no MAC: Wake PC can't reach it
    CHECK(state(in) == "lost");

    in = awayPaired();
    in.wakeTimedOut = true;
    CHECK(state(in) == "lost");

    in = awayPaired();
    in.atHome = false;
    CHECK(state(in) == "lost");

    // Never paired from this Mac and away
    in = awayPaired();
    in.knownPaired = false;
    CHECK(state(in) == "lost");

    // Off and can't be woken is still lost
    in = awayPaired();
    in.powerAction = "off";
    in.wakeFromOff = "ready";
    in.wakeable = false;
    CHECK(state(in) == "lost");
}

static void testWakingAndChecking()
{
    Inputs in = awayPaired();
    in.waking = true;
    CHECK(state(in) == "waking");

    // Waking shows even when the PC would otherwise be lost: it's what the person just did
    in.wakeable = false;
    CHECK(state(in) == "waking");
    in.wakeTimedOut = true;
    CHECK(state(in) == "waking");

    // Not polled yet
    in = awayPaired();
    in.unknown = true;
    CHECK(state(in) == "checking");
    in.waking = true;
    CHECK(state(in) == "waking");
    in = Inputs();
    in.unknown = true;
    CHECK(state(in) == "checking");

    // A PC that has been polled offline and never paired
    in = Inputs();
    CHECK(state(in) == "lost");
}

static void testNetworkAndNote()
{
    CHECK(network(true, true, true, false) == "home");
    CHECK(network(true, true, false, true) == "internet");
    CHECK(network(true, true, true, true) == "home");     // the LAN address wins
    CHECK(network(true, true, false, false) == "");        // IPv6 or a typed address
    CHECK(network(true, false, true, true) == "");         // no active address yet
    CHECK(network(false, true, true, true) == "");         // away

    CHECK(addressNote(false, true, "", false, true) == "lastAddress");
    CHECK(addressNote(false, false, "", false, false) == "lastAddress");
    CHECK(addressNote(true, false, "home", false, true) == "foundAutomatically");
    CHECK(addressNote(true, false, "home", false, false) == "addedByAddress");
    CHECK(addressNote(true, true, "internet", true, true) == "outsideAddress");
    CHECK(addressNote(true, true, "home", true, true) == "reachableOutside");
    CHECK(addressNote(true, true, "home", false, true) == "");
    CHECK(addressNote(true, true, "", true, true) == "");
}

static void testColors()
{
    CHECK(nextColor({}) == "indigo");
    CHECK(nextColor({ "indigo" }) == "teal");
    CHECK(nextColor({ "teal" }) == "indigo");
    CHECK(nextColor({ "indigo", "teal", "blue" }) == "pink");
    CHECK(nextColor({ "indigo", "teal", "blue", "pink" }) == "purple");
    CHECK(nextColor({ "unknown-color" }) == "indigo");

    // All ten taken: start again, by how many have one
    std::vector<std::string> all = assignOrder();
    CHECK(all.size() == 10);
    CHECK(nextColor(all) == "indigo");
    all.push_back("indigo");
    CHECK(nextColor(all) == "teal");

    CHECK(isColor("graphite"));
    CHECK(!isColor("gray"));                    // gray isn't a choice
    CHECK(!isColor(""));

    CHECK(hue(false, "teal") == "gray");        // not paired: always gray
    CHECK(hue(false, "") == "gray");
    CHECK(hue(true, "teal") == "teal");
    CHECK(hue(true, "") == "indigo");
    CHECK(hue(true, "gray") == "indigo");
    CHECK(hue(true, "nonsense") == "indigo");
}

static std::vector<App> apps(std::initializer_list<const char*> names)
{
    std::vector<App> list;
    int id = 100;
    for (const char* name : names) {
        App app;
        app.id = id++;
        app.name = name;
        list.push_back(app);
    }
    return list;
}

static std::vector<std::string> names(const std::vector<App>& list, const std::vector<int>& picked)
{
    std::vector<std::string> out;
    for (int i : picked) {
        out.push_back(list[i].name);
    }
    return out;
}

typedef std::vector<std::string> Names;

static void testPreview()
{
    // GonzaloPC: Desktop runs
    std::vector<App> list = apps({ "Steam Big Picture", "Desktop (multiple displays)", "Desktop", "Notepad" });
    CHECK(names(list, previewOrder(list, 102, {})) == Names({ "Desktop", "Desktop (multiple displays)", "Steam Big Picture" }));

    // Living Room: the last streamed app first, then the built-ins
    CHECK(names(list, previewOrder(list, 0, { "Steam Big Picture" })) ==
          Names({ "Steam Big Picture", "Desktop", "Desktop (multiple displays)" }));

    // Case doesn't matter for recents
    CHECK(names(list, previewOrder(list, 0, { "notepad" }))[0] == "Notepad");

    // Nothing recent, nothing built-in: by name
    std::vector<App> plain = apps({ "Zed", "Alpha", "Mid", "Beta" });
    CHECK(names(plain, previewOrder(plain, 0, {})) == Names({ "Alpha", "Beta", "Mid" }));

    // Fewer than three
    std::vector<App> two = apps({ "B", "A" });
    CHECK(names(two, previewOrder(two, 0, {})) == Names({ "A", "B" }));
    CHECK(previewOrder({}, 0, {}).empty());

    // A hidden app is left out, unless it runs
    std::vector<App> hid = apps({ "Desktop", "Secret", "Game" });
    hid[0].hidden = true;
    CHECK(names(hid, previewOrder(hid, 0, {})) == Names({ "Game", "Secret" }));
    CHECK(names(hid, previewOrder(hid, 100, {}))[0] == "Desktop");

    // A running app outside the first three goes first
    std::vector<App> many = apps({ "A", "B", "C", "D" });
    CHECK(names(many, previewOrder(many, 103, {}))[0] == "D");
    CHECK(previewOrder(many, 103, {}).size() == 3);

    // The limit
    CHECK(previewOrder(many, 0, {}, 1).size() == 1);
    CHECK(previewOrder(many, 0, {}, 10).size() == 4);

    // An id that isn't in the list changes nothing
    CHECK(names(many, previewOrder(many, 999, {}))[0] == "A");
}

static void testMainApp()
{
    std::vector<App> list = apps({ "Steam Big Picture", "Desktop", "Notepad" });
    std::vector<bool> direct = { false, false, false };

    CHECK(mainApp(list, direct, 102, {}) == 2);                 // the running app
    CHECK(mainApp(list, direct, 0, {}) == 1);                   // Desktop
    direct[2] = true;
    CHECK(mainApp(list, direct, 0, {}) == 2);                   // direct launch before Desktop
    CHECK(mainApp(list, direct, 100, {}) == 0);                 // running before direct launch
    list[2].hidden = true;
    CHECK(mainApp(list, direct, 0, {}) == 1);                   // hidden ones don't count
    std::vector<App> noDesktop = apps({ "Zed", "Alpha" });
    CHECK(mainApp(noDesktop, { false, false }, 0, {}) == 1);    // the first of the preview
    CHECK(mainApp({}, {}, 0, {}) == -1);
    CHECK(mainApp(noDesktop, { false, false }, 555, {}) == 1);  // running id not in the list
}

static void testMedian()
{
    CHECK(median({}) == -1);
    CHECK(median({ 4 }) == 4);
    CHECK(median({ 9, 1, 2 }) == 2);
    CHECK(median({ 3, 100, 2, 4, 3 }) == 3);
}

int main()
{
    testOnline();
    testGoingDown();
    testAway();
    testLost();
    testWakingAndChecking();
    testNetworkAndNote();
    testColors();
    testPreview();
    testMainApp();
    testMedian();

    if (s_Failures == 0) {
        std::printf("pccardrules: all tests passed\n");
        return 0;
    }
    std::printf("pccardrules: %d failure(s)\n", s_Failures);
    return 1;
}
