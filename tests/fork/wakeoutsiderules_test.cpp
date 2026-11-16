// Unit tests for app/fork/wakeoutsiderules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/wakeoutsiderules_test.cpp
#include "fork/wakeoutsiderules.h"

#include <cstdio>

using namespace WakeOutsideRules;

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

static void testAddresses()
{
    CHECK(isIPv4("10.0.0.77") && isIPv4("0.0.0.0") && isIPv4("255.255.255.255"));
    CHECK(!isIPv4("256.1.1.1") && !isIPv4("1.2.3") && !isIPv4("1.2.3.4.5") && !isIPv4("1.2.3.") && !isIPv4("a.b.c.d") &&
          !isIPv4("1234.1.1.1") && !isIPv4("") && !isIPv4("gonzalo.example.net") && !isIPv4("2601::1"));

    // The home's address from outside, as Moonlight learned it (an Xfinity one here)
    CHECK(isPublicIPv4("73.100.235.17") && isPublicIPv4("8.8.8.8") && isPublicIPv4("172.32.0.1") && isPublicIPv4("100.128.0.1"));
    // Addresses no one outside can send to
    CHECK(!isPublicIPv4("10.0.0.77") && !isPublicIPv4("172.16.0.1") && !isPublicIPv4("172.31.255.255") &&
          !isPublicIPv4("192.168.1.20") && !isPublicIPv4("100.64.0.1") && !isPublicIPv4("100.127.255.255") &&
          !isPublicIPv4("127.0.0.1") && !isPublicIPv4("169.254.3.4") && !isPublicIPv4("0.1.2.3") &&
          !isPublicIPv4("224.0.0.251") && !isPublicIPv4("255.255.255.255"));
    // macOS's 464XLAT address on an IPv6-only network (seen as a broadcast address in Wake PC's log)
    CHECK(!isPublicIPv4("192.0.0.2"));

    CHECK(isGlobalIPv6("2601:18a:817f:663b::5c43") && isGlobalIPv6("[2601:18a:817f:663b::5c43]") && isGlobalIPv6("3fff::1"));
    CHECK(!isGlobalIPv6("fe80::1") && !isGlobalIPv6("fd00::1") && !isGlobalIPv6("::1") && !isGlobalIPv6("10.0.0.77") && !isGlobalIPv6(""));

    // The remote address when it's public; else the one the PC was added by, unless that's a LAN one
    CHECK(outsideAddress("73.100.235.17", "") == "73.100.235.17");
    CHECK(outsideAddress("73.100.235.17", "73.100.235.17") == "73.100.235.17");
    CHECK(outsideAddress("", "73.100.235.17") == "73.100.235.17");
    CHECK(outsideAddress("10.0.0.1", "home.example.net") == "home.example.net");
    CHECK(outsideAddress("", "10.0.0.77").empty());
    CHECK(outsideAddress("", "2601::5c43").empty());
    CHECK(outsideAddress("", "").empty());
}

static void testRoute()
{
    Where w;
    w.outsideAddress = "73.100.235.17";
    w.ipv6Address = "2601:18a:817f:663b::5c43";

    // At home: on the PC's link, on a network that carried a LAN stream of it
    w.onLink = true;
    w.networkRemembered = true;
    w.anyRemembered = true;
    CHECK(route(w) == "home");

    // Another network with the same kind of addresses (another Xfinity home's 10.0.0.x): away
    w.networkRemembered = false;
    CHECK(route(w) == "outside");

    // No network remembered yet: being on the link has to do
    w.anyRemembered = false;
    CHECK(route(w) == "home");

    // Away: the home's address, or the PC's IPv6 one alone
    w.onLink = false;
    CHECK(route(w) == "outside" && shownAddress(w) == "73.100.235.17");
    w.outsideAddress.clear();
    CHECK(route(w) == "outside" && shownAddress(w) == "2601:18a:817f:663b::5c43");
    w.ipv6Address.clear();
    CHECK(route(w) == "none");

    CHECK(hintSecs(false) == k_HintSecs && hintSecs(true) == k_HintSecsFromOff && k_HintSecs < k_HintSecsFromOff);
}

static void testCard()
{
    // At home the card keeps its own words
    CHECK(wakingChip("home").empty() && wakingChip("").empty() && wakingLine("home", "", false).empty());
    CHECK(wakingChip("outside") == "Away from home" && wakingChip("none") == "Away from home");

    const std::string sent = wakingLine("outside", "73.100.235.17", false);
    CHECK(sent == "Sent to 73.100.235.17, for your router to pass on");
    CHECK(has(wakingLine("outside", "", false), "your home's address"));
    const std::string quiet = wakingLine("outside", "73.100.235.17", true);
    CHECK(has(quiet, "No answer yet") && has(quiet, "router"));
    CHECK(has(wakingLine("none", "", false), "No address"));
    // No answer: the asleep card and a toast say so, away from home only
    CHECK(missedLine("outside") == "Wake PC from outside got no answer");
    CHECK(has(missedLine("none"), "No address"));
    CHECK(missedLine("home").empty() && missedLine("").empty());
    CHECK(missedToast("outside", "GonzaloPC") == "GonzaloPC didn't answer Wake PC from outside your home network");
    CHECK(has(missedToast("none", "GonzaloPC"), "GonzaloPC didn't answer: LuzLunar has no address"));
    CHECK(missedToast("home", "GonzaloPC").empty());
    CHECK(missable("outside") && missable("none") && !missable("home") && !missable(""));
    CHECK(k_MissedKeepSecs > 0);

    // The big card has one line of about 58 characters for these
    for (const std::string& line : { sent, quiet, wakingLine("none", "", false), missedLine("outside"), missedLine("none"),
                                     wakingLine("outside", "255.255.255.255", false) }) {
        CHECK(line.size() <= 58);
    }
}

static void testCheckParts()
{
    const std::string xml =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><root status_code=\"200\"><hostname>GonzaloPC</hostname>"
        "<appversion>7.1.431.-1</appversion><uniqueid>524156B0-8A1F-A223-B894-12639EF5ADB7</uniqueid>"
        "<HttpsPort>47984</HttpsPort><ExternalPort>47989</ExternalPort><mac>00:00:00:00:00:00</mac>"
        "<LocalIP>10.0.0.77</LocalIP><PairStatus>0</PairStatus></root>";
    CHECK(xmlValue(xml, "LocalIP") == "10.0.0.77");
    CHECK(xmlValue(xml, "hostname") == "GonzaloPC");
    CHECK(xmlValue(xml, "ExternalIP").empty() && xmlValue("", "LocalIP").empty() && xmlValue("<LocalIP>10.0", "LocalIP").empty());

    // The answer is the PC's own, whatever the case of its uuid
    CHECK(samePc(xml, "524156b0-8a1f-a223-b894-12639ef5adb7"));
    CHECK(!samePc(xml, "33FB31D2-0FCA-0D09-3C8D-C634B69A9765") && !samePc(xml, "") && !samePc("", "524156B0"));

    Check last;
    CHECK(checkDue(last, 1000000, "10.0.0.77", ""));
    last.atSecs = 1000000;
    last.reached = true;
    CHECK(!checkDue(last, 1000000 + 3600, "10.0.0.77", "10.0.0.77"));
    CHECK(checkDue(last, 1000000 + k_CheckEverySecs, "10.0.0.77", "10.0.0.77"));
    CHECK(checkDue(last, 1000000 + 60, "10.0.0.15", "10.0.0.77"));
    // A check the home's address didn't answer may have been passing: again in half an hour
    last.reached = false;
    CHECK(!checkDue(last, 1000000 + 60, "10.0.0.77", "10.0.0.77"));
    CHECK(checkDue(last, 1000000 + k_RecheckMissSecs, "10.0.0.77", "10.0.0.77"));
    CHECK(k_RecheckMissSecs < k_CheckEverySecs);
}

static Facts gonzaloPc()
{
    Facts f;
    f.pcName = "GonzaloPC";
    f.lanAddress = "10.0.0.77";
    f.mac = "74:56:3c:c9:76:6d";
    f.adapter = "Realtek Gaming 2.5GbE Family Controller";
    f.link = "ethernet";
    f.outsideAddress = "73.100.235.17";
    return f;
}

static const Row* find(const std::vector<Row>& rows, const std::string& id)
{
    for (const Row& r : rows) {
        if (r.id == id) {
            return &r;
        }
    }
    return nullptr;
}

static void testSteps()
{
    // Never checked: the three steps, with the PC's address and card
    Facts f = gonzaloPc();
    auto list = rows(f);
    CHECK(list.size() == 3);
    const Row* forward = find(list, "forward");
    const Row* answer = find(list, "answer");
    const Row* sleep = find(list, "sleep");
    CHECK(forward && answer && sleep);
    CHECK(forward->kind == "info" && has(forward->detail, "forward UDP port 9 to 10.0.0.77") && has(forward->detail, "47998 to 48010") &&
          has(forward->detail, "GonzaloPC on"));
    CHECK(answer->kind == "info" && has(answer->title, "10.0.0.77") &&
          has(answer->detail, "Realtek Gaming 2.5GbE Family Controller's Advanced tab") && has(answer->detail, "ARP Offload"));
    CHECK(sleep->kind == "info" && has(sleep->detail, "binds 10.0.0.77 to 74:56:3c:c9:76:6d") && has(sleep->detail, "static ARP") &&
          has(sleep->detail, "always on"));
    CHECK(has(intro(f), "73.100.235.17") && has(intro(f), "pass it on to GonzaloPC"));

    // 2026-11-15, checked from home: the router passes the home's address on to 10.0.0.77, where
    // LuzLunar finds the PC at home too
    f.check.atSecs = 1794797000;
    f.check.address = "73.100.235.17";
    f.check.reached = true;
    f.check.forwardedTo = "10.0.0.77";
    f.checkedWhen = "today at 21:52";
    list = rows(f);
    forward = find(list, "forward");
    answer = find(list, "answer");
    CHECK(forward->kind == "ok" && forward->title == "Your router passes 73.100.235.17 on to 10.0.0.77" &&
          has(forward->detail, "today at 21:52") && has(forward->detail, "UDP port 9 to 10.0.0.77"));
    CHECK(answer->kind == "info" && has(answer->title, "10.0.0.77") && has(answer->detail, "just that one IPv4 address") &&
          has(answer->detail, "only one or two"));

    // The router passes it on to another of the PC's addresses than the one LuzLunar finds it at:
    // the card has two, and the router's has to answer while it sleeps
    f.check.forwardedTo = "10.0.0.15";
    list = rows(f);
    answer = find(list, "answer");
    CHECK(answer->kind == "warn" && answer->title == "GonzaloPC's network card has more than one address" &&
          has(answer->detail, "passes Wake PC on to 10.0.0.15") && has(answer->detail, "finds GonzaloPC at home at 10.0.0.77") &&
          has(answer->detail, "Give Realtek Gaming 2.5GbE Family Controller just 10.0.0.15"));
    CHECK(has(find(list, "forward")->detail, "UDP port 9 to 10.0.0.15") && has(find(list, "sleep")->detail, "binds 10.0.0.15"));

    // The home's address didn't reach the PC
    f.check.reached = false;
    f.check.forwardedTo.clear();
    list = rows(f);
    forward = find(list, "forward");
    CHECK(forward->kind == "warn" && forward->title == "73.100.235.17 didn't reach GonzaloPC" &&
          has(forward->detail, "UDP port 9") && has(forward->detail, "TCP 47984, 47989 and 48010") && has(forward->detail, "to 10.0.0.77"));

    // On Wi-Fi, nothing wakes it while it sleeps
    f = gonzaloPc();
    f.link = "wifi";
    answer = nullptr;
    list = rows(f);
    answer = find(list, "answer");
    CHECK(answer->kind == "warn" && answer->title == "GonzaloPC is on Wi-Fi" && has(answer->detail, "Connect GonzaloPC by Ethernet"));

    // Nothing known: still words, never a %1
    Facts bare;
    bare.pcName = "PC";
    list = rows(bare);
    CHECK(list.size() == 3);
    CHECK(has(find(list, "answer")->detail, "the network card's Advanced tab") && has(find(list, "sleep")->detail, "its MAC address"));
    CHECK(has(intro(bare), "doesn't know that address yet"));
    for (const Facts& facts : { gonzaloPc(), bare, f }) {
        for (const Row& r : rows(facts)) {
            CHECK(!has(r.title, "%1") && !has(r.detail, "%1"));
        }
        CHECK(!has(intro(facts), "%1"));
    }
}

static void testCheckAndShutDown()
{
    Facts f = gonzaloPc();
    CHECK(has(checkBlocker(f), "from home"));
    f.atHome = true;
    CHECK(has(checkBlocker(f), "with GonzaloPC on"));
    f.online = true;
    CHECK(checkBlocker(f).empty());
    f.outsideAddress.clear();
    CHECK(has(checkBlocker(f), "home's address first"));

    CHECK(shutDownWarning("home", "GonzaloPC").empty());
    const std::string away = shutDownWarning("outside", "GonzaloPC");
    CHECK(has(away, "away from GonzaloPC's home network") && has(away, "can't turn it on again") && has(away, "Sleep PC"));
    CHECK(!shutDownWarning("none", "GonzaloPC").empty());

    Where w;
    w.outsideAddress = "73.100.235.17";
    w.ipv6Address = "2601:18a:817f:663b::5c43";
    CHECK(logLine("home", w, "GonzaloPC") == "Wake PC to GonzaloPC: on its home network, a broadcast there");
    CHECK(logLine("outside", w, "GonzaloPC") ==
          "Wake PC to GonzaloPC: away from its home network, so through 73.100.235.17 and 2601:18a:817f:663b::5c43 for the router to pass on");
    w.outsideAddress.clear();
    CHECK(has(logLine("outside", w, "GonzaloPC"), "through 2601:18a:817f:663b::5c43 for"));
    CHECK(has(logLine("none", Where {}, "GonzaloPC"), "no address for it from outside"));

    // Every %1 is the PC's name, even one that looks like a mark itself
    CHECK(fill("%1 and %1", "A%1") == "A%1 and A%1");
}

int main()
{
    testAddresses();
    testRoute();
    testCard();
    testCheckParts();
    testSteps();
    testCheckAndShutDown();

    if (s_Failures == 0) {
        std::printf("wakeoutsiderules: all tests passed\n");
        return 0;
    }
    std::printf("wakeoutsiderules: %d failure(s)\n", s_Failures);
    return 1;
}
