// Unit tests for app/fork/forklinkrules.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/forklinkrules_test.cpp app/fork/forklinkrules.cpp
#include "fork/forklinkrules.h"

#include <cstdio>
#include <string>

using namespace ForkLinkRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Link link(Kind kind, double mbps = 0, double bandGHz = 0, Kind underlying = Kind::Unknown, const char* name = "")
{
    Link l;
    l.kind = kind;
    l.mbps = mbps;
    l.bandGHz = bandGHz;
    l.underlying = underlying;
    l.name = name;
    return l;
}

static void testSpeed()
{
    CHECK(speedText(0).empty());
    CHECK(speedText(-5).empty());
    CHECK(speedText(10) == "10 Mb/s");
    CHECK(speedText(100) == "100 Mb/s");
    CHECK(speedText(866.7) == "867 Mb/s");
    CHECK(speedText(0.4) == "1 Mb/s");
    CHECK(speedText(1000) == "1 Gb/s");
    CHECK(speedText(1200) == "1.2 Gb/s");
    CHECK(speedText(2500) == "2.5 Gb/s");
    CHECK(speedText(5000) == "5 Gb/s");
    CHECK(speedText(10000) == "10 Gb/s");
}

static void testBadge()
{
    CHECK(badge(link(Kind::Ethernet, 1000), false) == "Ethernet 1 Gb/s");
    CHECK(badge(link(Kind::Ethernet, 100), false) == "Ethernet 100 Mb/s");
    CHECK(badge(link(Kind::Ethernet), false) == "Ethernet");
    CHECK(badge(link(Kind::WiFi, 866.7, 5), false) == "Wi-Fi 5 GHz 867 Mb/s");
    CHECK(badge(link(Kind::WiFi, 286, 2.4), false) == "Wi-Fi 2.4 GHz 286 Mb/s");
    CHECK(badge(link(Kind::WiFi, 0, 6), false) == "Wi-Fi 6 GHz");
    CHECK(badge(link(Kind::WiFi), false) == "Wi-Fi");   // what macOS hides without Location access
    CHECK(badge(link(Kind::ThunderboltBridge, 10000), false) == "Thunderbolt Bridge 10 Gb/s");
    CHECK(badge(link(Kind::ThunderboltBridge), false) == "Thunderbolt Bridge");
    CHECK(badge(link(Kind::Vpn, 0, 0, Kind::WiFi), true) == "VPN over Wi-Fi · not via LAN");
    CHECK(badge(link(Kind::Vpn, 0, 0, Kind::Ethernet), true) == "VPN over Ethernet · not via LAN");
    CHECK(badge(link(Kind::Vpn), true) == "VPN · not via LAN");
    CHECK(badge(link(Kind::Vpn, 0, 0, Kind::Vpn), false) == "VPN");
    CHECK(badge(link(Kind::Other, 0, 0, Kind::Unknown, "iPhone USB"), false) == "iPhone USB");
    CHECK(badge(link(Kind::Other), false) == "Network");
    CHECK(badge(link(Kind::Ethernet, 1000), true) == "Ethernet 1 Gb/s · not via LAN");
    CHECK(badge(link(Kind::Unknown, 1000), false).empty());
    CHECK(badge(link(Kind::Unknown), true).empty());
}

static void testConnection()
{
    CHECK(bandText(5) == "5 GHz");
    CHECK(bandText(2.4) == "2.4 GHz");
    CHECK(bandText(0).empty());

    CHECK(connectionText(link(Kind::WiFi, 866, 5), true) == "Wi-Fi 5 GHz · LAN");
    CHECK(connectionText(link(Kind::WiFi), true) == "Wi-Fi · LAN");     // no band without Location access
    CHECK(connectionText(link(Kind::Ethernet, 1000), false) == "Ethernet · not via LAN");
    CHECK(connectionText(link(Kind::ThunderboltBridge, 10000), true) == "Thunderbolt Bridge · LAN");
    CHECK(connectionText(link(Kind::Vpn, 0, 0, Kind::WiFi), false) == "VPN over Wi-Fi · not via LAN");
    CHECK(connectionText(link(Kind::Other, 0, 0, Kind::Unknown, "iPhone USB"), false) == "iPhone USB · not via LAN");
    CHECK(connectionText(link(Kind::Unknown), true).empty());
}

static void testWhenShown()
{
    // Moonlight's answer stands when it has one
    CHECK(viaLan(Reachability::Lan, false, Kind::Ethernet));
    CHECK(!viaLan(Reachability::Vpn, true, Kind::Ethernet));
    // Otherwise the subnet check decides
    CHECK(viaLan(Reachability::Unknown, true, Kind::WiFi));
    CHECK(!viaLan(Reachability::Unknown, false, Kind::WiFi));
    CHECK(viaLan(Reachability::NotChecked, true, Kind::Ethernet));
    CHECK(!viaLan(Reachability::NotChecked, false, Kind::Ethernet));
    // A VPN interface is never the LAN, even with a subnet that looks local
    CHECK(!viaLan(Reachability::Lan, true, Kind::Vpn));
    CHECK(!viaLan(Reachability::Unknown, true, Kind::Vpn));

    CHECK(shouldShow(true, false));     // the first LAN stream on a network counts
    CHECK(shouldShow(true, true));
    CHECK(shouldShow(false, true));     // a network that carried one before
    CHECK(!shouldShow(false, false));   // anywhere else, like over the internet
}

static void testRemembered()
{
    std::vector<std::string> ids;
    CHECK(!remembered(ids, "a"));
    ids = remember(ids, "a");
    ids = remember(ids, "b");
    CHECK(remembered(ids, "a") && remembered(ids, "b"));
    CHECK(ids.size() == 2 && ids[0] == "b" && ids[1] == "a");

    // Seen again: first, once
    ids = remember(ids, "a");
    CHECK(ids.size() == 2 && ids[0] == "a" && ids[1] == "b");

    // An empty id (no router) is never remembered or matched
    ids = remember(ids, "");
    CHECK(ids.size() == 2);
    CHECK(!remembered(ids, ""));

    // Past the limit, the oldest go
    std::vector<std::string> many;
    for (int i = 0; i < 40; i++) {
        many = remember(many, "n" + std::to_string(i));
    }
    CHECK(many.size() == k_MaxRememberedNetworks);
    CHECK(many.front() == "n39");
    CHECK(remembered(many, "n8") && !remembered(many, "n7"));
    CHECK(remember(many, "x", 3).size() == 3);
    CHECK(remember(ids, "c", 0) == ids);
}

int main()
{
    testSpeed();
    testBadge();
    testConnection();
    testWhenShown();
    testRemembered();

    if (s_Failures == 0) {
        std::printf("forklinkrules: all tests passed\n");
        return 0;
    }
    std::printf("forklinkrules: %d failure(s)\n", s_Failures);
    return 1;
}
