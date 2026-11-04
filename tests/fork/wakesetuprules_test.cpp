// Unit tests for app/fork/wakesetuprules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/wakesetuprules_test.cpp
#include "fork/wakesetuprules.h"

#include <cstdio>

using namespace WakeSetupRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static bool has(const std::string& text, const std::string& part)
{
    return text.find(part) != std::string::npos;
}

static Check check(std::string id, std::string state, std::string reason = {}, std::string setting = {},
                   std::string current = {}, std::string target = {})
{
    Check c;
    c.id = std::move(id);
    c.state = std::move(state);
    c.reason = std::move(reason);
    c.setting = std::move(setting);
    c.current = std::move(current);
    c.target = std::move(target);
    return c;
}

// A Realtek adapter with Shutdown Wake-On-Lan off and Fast Startup on, as Apollo answers
static Status realtek()
{
    Status s;
    s.known = true;
    s.fromOff = "fixable";
    s.adapterName = "Ethernet";
    s.adapterDescription = "Realtek PCIe 2.5GbE Family Controller";
    s.link = "ethernet";
    s.checks = {
        check("link", "ok"),
        check("magicPacket", "ok", "", "Wake on Magic Packet", "Enabled", "Enabled"),
        check("shutdownWake", "fix", "", "Shutdown Wake-On-Lan", "Disabled", "Enabled"),
        check("fastStartup", "fix"),
        check("macOverride", "ok"),
        check("bios", "manual"),
    };
    s.lastPowerOn = "powerSwitch";
    s.uptimeSeconds = 3600;
    s.canFix = true;
    s.reason = "none";
    return s;
}

static void testRows()
{
    Status s = realtek();
    auto list = rows(s, "Gaming PC");
    // The unchanged MAC has no row; the last power-on has one
    CHECK(list.size() == 6);
    CHECK(list[0].id == "link" && list[0].kind == "ok" && list[0].title == "Connected by Ethernet" &&
          list[0].detail == "Realtek PCIe 2.5GbE Family Controller");
    CHECK(list[1].kind == "ok" && list[1].title == "Wake on Magic Packet is on");
    CHECK(list[2].kind == "warn" && list[2].title == "Shutdown Wake-On-Lan is Disabled" && list[2].detail == "Fix on PC sets it to Enabled.");
    CHECK(list[3].kind == "warn" && list[3].title == "Fast Startup is on" && has(list[3].detail, "Fix on PC turns Fast Startup off"));
    CHECK(list[4].id == "bios" && list[4].kind == "info" && has(list[4].detail, "Gaming PC's BIOS") && has(list[4].detail, "ErP Ready") &&
          has(list[4].detail, "PXE"));
    CHECK(list[5].id == "lastPowerOn" && list[5].kind == "info" && list[5].title == "Last turned on with the power button");

    // Every kind of check has words
    Status other = s;
    other.checks = {
        check("link", "blocked", "wifi"),
        check("link", "unknown", "virtual"),
        check("link", "blocked", "none"),
        check("link", "unknown", "other"),
        check("magicPacket", "fix"),
        check("magicPacket", "unknown", "missing"),
        check("shutdownWake", "ok", "", "Enable PME", "Enabled"),
        check("shutdownWake", "unknown", "missing"),
        check("shutdownWake", "unknown", "ambiguous", "Wake from S5", "No"),
        check("eee", "fix"),
        check("eee", "ok"),
        check("fastStartup", "warn", "policy"),
        check("fastStartup", "ok", "policy"),
        check("fastStartup", "ok", "no_hibernation"),
        check("fastStartup", "ok"),
        check("macOverride", "warn"),
    };
    other.lastPowerOn = "lan";
    list = rows(other, "PC");
    CHECK(list[0].title == "Connected by Wi-Fi" && has(list[0].detail, "Connect PC by Ethernet"));
    CHECK(list[1].title == "Connected through a virtual adapter" && has(list[1].detail, "Realtek PCIe"));
    CHECK(list[2].title == "Network adapter not found");
    CHECK(has(list[3].title, "Connected through Realtek"));
    CHECK(list[4].title == "Wake on Magic Packet is off" && list[4].detail == "Fix on PC turns it on.");
    CHECK(list[5].title == "No Wake on Magic Packet setting");
    CHECK(list[6].title == "Enable PME is Enabled" && list[6].kind == "ok");
    CHECK(list[7].title == "No setting for waking from off" && has(list[7].detail, "Shutdown Wake-On-Lan"));
    CHECK(list[8].title == "Wake from S5 is No" && has(list[8].detail, "Device Manager"));
    CHECK(list[9].title == "Energy-Efficient Ethernet is on" && list[9].kind == "warn");
    CHECK(list[10].title == "Energy-Efficient Ethernet is off" && list[10].kind == "ok");
    CHECK(list[11].title == "Fast Startup is on (set by a policy)" && has(list[11].detail, "Shut Down PC"));
    CHECK(list[12].title == "Fast Startup is off (set by a policy)");
    CHECK(list[13].title == "Fast Startup is off" && has(list[13].detail, "Hibernation"));
    CHECK(list[14].title == "Fast Startup is off" && list[14].detail.empty());
    CHECK(list[15].title == "Windows uses a changed MAC address" && list[15].kind == "warn");
    CHECK(list[16].title == "Last turned on by Wake-on-LAN");

    // Nothing known about the last power-on: no row
    s.lastPowerOn = "unknown";
    CHECK(rows(s, "PC").size() == 5);
}

static void testSummary()
{
    Status s = realtek();
    CHECK(summary(s, "PC") == "PC needs a few changes to turn on from off.");
    s.reason = "streaming";
    CHECK(has(summary(s, "PC"), "waits until PC stops streaming"));
    s.reason = "none";
    s.applying = true;
    CHECK(has(summary(s, "PC"), "PC is changing its settings now"));

    s = realtek();
    s.fromOff = "ready";
    CHECK(has(summary(s, "PC"), "PC is ready to turn on from off"));
    s.fromOff = "blocked";
    s.checks[0] = check("link", "blocked", "wifi");
    CHECK(summary(s, "PC") == "PC can't turn on from off: Connected by Wi-Fi.");
    s.fromOff = "unknown";
    CHECK(has(summary(s, "PC"), "can't tell"));
    CHECK(summary(Status {}, "PC") == "Asking PC…");
}

static void testFixConfirmation()
{
    Status s = realtek();
    auto text = fixConfirmation(s, "PC");
    CHECK(has(text, "Shutdown Wake-On-Lan on, Fast Startup off."));
    CHECK(has(text, "PC's network adapter restarts"));
    CHECK(has(text, "shuts PC down fully"));
    CHECK(has(text, "Undo Changes"));

    // Only Fast Startup: the adapter doesn't restart
    s.checks[2].state = "ok";
    text = fixConfirmation(s, "PC");
    CHECK(!has(text, "adapter restarts") && has(text, "Fast Startup off."));

    // Only the adapter, with Intel's EEE
    s = realtek();
    s.checks[3].state = "ok";
    s.checks.push_back(check("eee", "fix", "", "Energy-Efficient Ethernet", "On", "Off"));
    text = fixConfirmation(s, "PC");
    CHECK(has(text, "Shutdown Wake-On-Lan on, Energy-Efficient Ethernet off.") && !has(text, "shuts PC down fully"));
}

static void testShutDownWarning()
{
    Status s = realtek();
    auto text = shutDownWarning(s, "PC");
    CHECK(has(text, "Wake PC may not turn PC on again: Shutdown Wake-On-Lan is Disabled.") && has(text, "Set Up Wake from Off"));

    // Shut Down PC does a full shutdown: Fast Startup alone doesn't matter to it
    s.checks[2].state = "ok";
    CHECK(shutDownWarning(s, "PC").empty());

    s.checks[0] = check("link", "blocked", "wifi");
    CHECK(has(shutDownWarning(s, "PC"), "PC is on Wi-Fi"));

    s = realtek();
    s.checks[2] = check("shutdownWake", "unknown", "missing");
    CHECK(has(shutDownWarning(s, "PC"), "No setting for waking from off"));

    // Nothing known yet, or an Apollo without /actions/wake: nothing to say
    CHECK(shutDownWarning(Status {}, "PC").empty());
}

static void testPoweredOn()
{
    Status s = realtek();
    // Up an hour, Wake PC sent 40 s ago: it was asleep
    CHECK(poweredOnText(s, 40, "PC") == "PC is awake");
    // Started after Wake PC was sent, and SMBIOS says LAN: Wake-on-LAN turned it on
    s.uptimeSeconds = 25;
    s.lastPowerOn = "lan";
    CHECK(poweredOnText(s, 40, "PC") == "PC turned on by Wake-on-LAN");
    s.lastPowerOn = "pme";
    CHECK(poweredOnText(s, 40, "PC") == "PC turned on by Wake-on-LAN");
    // Some firmware always says the power switch
    s.lastPowerOn = "powerSwitch";
    CHECK(poweredOnText(s, 40, "PC") == "PC is on");
    // A little slack for clocks and polling
    s.lastPowerOn = "lan";
    s.uptimeSeconds = 65;
    CHECK(poweredOnText(s, 40, "PC") == "PC turned on by Wake-on-LAN");
    s.uptimeSeconds = 75;
    CHECK(poweredOnText(s, 40, "PC") == "PC is awake");
    CHECK(poweredOnText(Status {}, 40, "PC") == "PC is awake");
    CHECK(poweredOnText(s, -1, "PC") == "PC is awake");
}

static void testResults()
{
    Result r;
    r.present = true;
    r.action = "fix";
    r.ok = true;
    r.changed = 2;
    CHECK(resultText(r, "PC") == "Changed PC's wake settings");
    r.restartNeeded = true;
    CHECK(resultText(r, "PC") == "Changed PC's wake settings. Restart PC for them to apply.");
    r.restartNeeded = false;
    r.changed = 0;
    CHECK(resultText(r, "PC") == "PC's wake settings were already right");
    r.action = "undo";
    r.changed = 2;
    CHECK(resultText(r, "PC") == "Put PC's wake settings back");

    r = Result {};
    r.action = "fix";
    r.error = "access_denied";
    CHECK(has(resultText(r, "PC"), "run as its service"));
    r.error = "journal";
    CHECK(has(resultText(r, "PC"), "changed nothing"));
    r.error = "streaming";
    CHECK(resultText(r, "PC") == "PC started streaming, so nothing changed");
    r.error = "error 5";
    r.failed = {"S5WakeOnLan", "HiberbootEnabled"};
    CHECK(resultText(r, "PC") == "Couldn't change S5WakeOnLan, HiberbootEnabled on PC");
    r.failed.clear();
    CHECK(has(resultText(r, "PC"), "Try again"));

    CHECK(has(refusalText(401, "permission", "PC"), "Sleep and Shut Down PC permission on PC"));
    CHECK(refusalText(404, "unsupported", "PC") == "PC's Apollo can't set up wake from off");
    CHECK(has(refusalText(403, "token", "PC"), "Try again"));
    CHECK(refusalText(409, "streaming", "PC") == "PC is streaming, so its settings stay as they are");
    CHECK(refusalText(409, "nothing", "PC") == "Nothing to change on PC");
    CHECK(refusalText(409, "applying", "PC") == "PC is already changing its settings");
    CHECK(refusalText(0, "", "PC") == "PC didn't answer");
}

static void testTexts()
{
    auto away = awayText("PC", "192.168.1.20", "aa:bb:cc:dd:ee:ff");
    CHECK(has(away, "When PC is off") && has(away, "bind 192.168.1.20 to aa:bb:cc:dd:ee:ff") && has(away, "static ARP"));
    away = awayText("PC", "", "");
    CHECK(has(away, "bind its address to its MAC address"));
    // Every %1 is the PC's name, even one that looks like a mark itself
    CHECK(fill("%1 and %1", "A%1") == "A%1 and A%1");
}

int main()
{
    testRows();
    testSummary();
    testFixConfirmation();
    testShutDownWarning();
    testPoweredOn();
    testResults();
    testTexts();

    if (s_Failures == 0) {
        std::printf("wakesetuprules: all tests passed\n");
        return 0;
    }
    std::printf("wakesetuprules: %d failure(s)\n", s_Failures);
    return 1;
}
