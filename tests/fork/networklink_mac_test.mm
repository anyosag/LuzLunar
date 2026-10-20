// Tests for app/fork/mac/networklink_mac.mm on the Mac running them: routes are looked up without
// sending anything. A standalone program for the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/networklink_mac_test.mm app/fork/mac/networklink_mac.mm
//       app/fork/forklinkrules.cpp -framework Foundation -framework SystemConfiguration -framework CoreWLAN

#include "fork/mac/networklink.h"

#include <cstdio>
#include <string>

#include <net/if_media.h>

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

    // The route to a public address: an interface this Mac has, not on its LAN
    MacNetworkLink::Probe internet = MacNetworkLink::probe("1.1.1.1");
    show("1.1.1.1", internet);
    CHECK(!internet.interfaceName.empty());
    CHECK(internet.link.kind != Kind::Unknown);
    CHECK(!internet.onLink);

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
