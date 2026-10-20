#pragma once

#include <cstddef>
#include <string>
#include <vector>

// What the notch bar says about the Mac's connection to the PC (Ethernet or Wi-Fi, and its speed),
// and on which networks it says it: on a network that has carried a LAN stream of the PC. Kept free
// of Qt and macOS so it can be unit tested on its own (tests/fork/forklinkrules_test.cpp).
namespace ForkLinkRules
{
    enum class Kind {
        Unknown,
        Ethernet,           // USB and Thunderbolt Ethernet adapters too
        WiFi,
        ThunderboltBridge,  // a Thunderbolt cable to the other computer
        Vpn,
        Other,              // like "iPhone USB"; Link::name says which
    };

    // The interface a stream goes through (mac/networklink.h finds it)
    struct Link {
        Kind kind = Kind::Unknown;
        std::string name;               // Other: the interface's name, shown as is
        double mbps = 0;                // link speed; 0 if unknown
        double bandGHz = 0;             // Wi-Fi: 2.4, 5 or 6; 0 if unknown
        Kind underlying = Kind::Unknown;    // Vpn: the link it runs over
    };

    // Moonlight's reachability check at stream start (NvComputer::getActiveAddressReachability())
    enum class Reachability {
        NotChecked,     // skipped, as with a custom packet size
        Unknown,        // not on the LAN, or the check didn't finish
        Lan,
        Vpn,
    };

    // Whether the stream goes over the LAN. Moonlight's answer, except that one it couldn't give
    // (Unknown or NotChecked) comes from whether the PC's address is in the subnet of the interface
    // carrying the stream. A VPN interface is never the LAN.
    bool viaLan(Reachability reachability, bool onLink, Kind routeKind);

    // Whether the bar shows the link: the stream goes over the LAN, or this network carried a LAN
    // stream of this PC before
    bool shouldShow(bool viaLan, bool networkRemembered);

    // "Ethernet 1 Gb/s", "Wi-Fi 5 GHz 866 Mb/s", "VPN over Wi-Fi"; with " · not via LAN" when the
    // stream doesn't go over the LAN. Empty for an unknown link.
    std::string badge(const Link& link, bool notViaLan);

    // "866 Mb/s", "1 Gb/s", "2.5 Gb/s"; empty when unknown
    std::string speedText(double mbps);

    // The networks a PC was streamed over the LAN on, newest first. Ids are opaque (hashes of
    // macOS's identity for the network).
    constexpr std::size_t k_MaxRememberedNetworks = 32;

    // Puts id first, dropping its older place and anything past max
    std::vector<std::string> remember(std::vector<std::string> ids, const std::string& id,
                                      std::size_t max = k_MaxRememberedNetworks);
    bool remembered(const std::vector<std::string>& ids, const std::string& id);
}
