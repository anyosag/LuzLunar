// Tests for app/fork/mac/networklink_mac.mm on the Mac running them: routes are looked up without
// sending anything. A standalone program for the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/networklink_mac_test.mm app/fork/mac/networklink_mac.mm
//       app/fork/forklinkrules.cpp -framework Foundation -framework SystemConfiguration -framework CoreWLAN

#include "fork/mac/networklink.h"

#include <cstdio>
#include <cstring>
#include <string>

#include <net/if_media.h>
#include <unistd.h>

using ForkLinkRules::Kind;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static void show(const char* what, const MacNetworkLink::Probe& probe)
{
    std::printf("%s: interface %s, badge \"%s\", on-link %s, network %s\n", what,
                probe.interfaceName.empty() ? "(none)" : probe.interfaceName.c_str(),
                ForkLinkRules::badge(probe.link, false).c_str(), probe.onLink ? "yes" : "no",
                probe.networkId.empty() ? "(none)" : "known");
}

// The route macOS itself has to an address, as route(8) reads it from the routing table: like the
// probe, it sends nothing
struct SystemRoute {
    bool read = false;          // route answered: an interface, or "not in table"
    std::string interfaceName;  // empty when there's no route
    std::string output;         // what route printed

    bool operator==(const SystemRoute& other) const { return read == other.read && interfaceName == other.interfaceName; }
};

static SystemRoute systemRoute(const char* address)
{
    SystemRoute route;
    FILE* pipe = popen((std::string("/sbin/route -n get ") + address + " 2>&1").c_str(), "r");
    if (pipe == nullptr) {
        return route;
    }
    bool notInTable = false;
    char line[256];
    while (std::fgets(line, sizeof(line), pipe) != nullptr) {
        route.output += line;
        char name[64];
        if (std::sscanf(line, " interface: %63s", name) == 1) {
            route.interfaceName = name;
        }
        notInTable = notInTable || std::strstr(line, "not in table") != nullptr;
    }
    // route get exits 0 with or without a route
    route.read = pclose(pipe) == 0 && (route.interfaceName.empty() ? notInTable : !notInTable);
    return route;
}

static std::string describe(const SystemRoute& route)
{
    return !route.read ? std::string("unreadable") : route.interfaceName.empty() ? std::string("no route") : route.interfaceName;
}

int main()
{
    // Ethernet speeds from the media word, as ifconfig shows them
    CHECK(MacNetworkLink::mediaMbps(IFM_ETHER | IFM_1000_T | IFM_FDX) == 1000);
    CHECK(MacNetworkLink::mediaMbps(IFM_ETHER | IFM_100_TX | IFM_FDX) == 100);
    CHECK(MacNetworkLink::mediaMbps(IFM_ETHER | IFM_10_T) == 10);
#ifdef IFM_2500_T
    CHECK(MacNetworkLink::mediaMbps(IFM_ETHER | IFM_2500_T | IFM_FDX) == 2500);
#endif
#ifdef IFM_10G_T
    CHECK(MacNetworkLink::mediaMbps(IFM_ETHER | IFM_10G_T | IFM_FDX) == 10000);
#endif
    CHECK(MacNetworkLink::mediaMbps(IFM_ETHER | IFM_AUTO) == 0);
#ifdef IFM_IEEE80211
    CHECK(MacNetworkLink::mediaMbps(IFM_IEEE80211 | IFM_AUTO) == 0);
#endif

    // Addresses
    CHECK(MacNetworkLink::numericAddress("192.168.1.20") == "192.168.1.20");
    CHECK(MacNetworkLink::numericAddress("::1") == "::1");
    CHECK(MacNetworkLink::numericAddress("[::1]") == "::1");
    std::string localhost = MacNetworkLink::numericAddress("localhost");
    CHECK(localhost == "127.0.0.1" || localhost == "::1");
    CHECK(MacNetworkLink::numericAddress("").empty());
    CHECK(MacNetworkLink::numericAddress("no-such-host.invalid").empty());

    // The route to a public address: the interface macOS routes it through, not on its LAN. The CI
    // Mac can be briefly offline, with no IPv4 route to the internet; then the probe finds none
    // either. macOS's own route (route -n get) is read before and after the probe, which runs again
    // if the network changed in between.
    SystemRoute route, routeAfter;
    MacNetworkLink::Probe internet;
    for (int attempt = 1;; attempt++) {
        route = systemRoute("1.1.1.1");
        internet = MacNetworkLink::probe("1.1.1.1");
        routeAfter = systemRoute("1.1.1.1");
        if (routeAfter == route || attempt == 5) {
            break;
        }
        std::printf("1.1.1.1: the route changed during the probe (%s, then %s); probing again\n",
                    describe(route).c_str(), describe(routeAfter).c_str());
        sleep(1);
    }
    show("1.1.1.1", internet);
    CHECK(routeAfter == route);     // the network held still for one of five probes
    CHECK(route.read);
    if (!route.read) {
        std::printf("route -n get 1.1.1.1 printed:\n%s", route.output.c_str());
    }
    else if (!route.interfaceName.empty()) {
        std::printf("1.1.1.1: macOS routes it through %s (route -n get)\n", route.interfaceName.c_str());
        CHECK(internet.interfaceName == route.interfaceName);
        CHECK(internet.link.kind != Kind::Unknown);
        CHECK(!internet.onLink);
    }
    else {
        std::printf("1.1.1.1: this Mac has no IPv4 route to the internet (route -n get: not in table), so the "
                    "online-only checks ran in their offline form\n");
        CHECK(internet.interfaceName.empty());
        CHECK(internet.link.kind == Kind::Unknown);
        CHECK(!internet.onLink);
    }

    // Loopback is on-link, with no router
    MacNetworkLink::Probe loopback = MacNetworkLink::probe("127.0.0.1");
    show("127.0.0.1", loopback);
    CHECK(loopback.interfaceName == "lo0");
    CHECK(loopback.onLink);
    CHECK(loopback.networkId.empty());

    // Not an address: nothing
    CHECK(MacNetworkLink::probe("").interfaceName.empty());
    CHECK(MacNetworkLink::probe("not an address").interfaceName.empty());
    CHECK(MacNetworkLink::probe("example.com").interfaceName.empty());     // names go through numericAddress() first

    if (s_Failures == 0) {
        std::printf("networklink_mac: all tests passed\n");
        return 0;
    }
    std::printf("networklink_mac: %d failure(s)\n", s_Failures);
    return 1;
}
