#pragma once

#include <string>

#include "fork/forklinkrules.h"

// The Mac side of the notch bar's link badge (forknetworklink.h): which interface carries traffic to
// the PC, what kind it is and how fast, and macOS's identity for the network it's on. Nothing here
// sends a packet. Without Location access macOS hides Wi-Fi network names, so none are read.
// Thread-safe; meant for a thread of its own.
//
// Finding the route connects a UDP socket, which macOS's local network privacy (Privacy & Security ›
// Local Network) refuses for an address on a local network when LuzLunar isn't allowed there
// (TN3179); Probe::localNetworkBlocked and checkLocal() say when that happened.
namespace MacNetworkLink
{
    struct Probe {
        ForkLinkRules::Link link;
        std::string interfaceName;  // BSD name, like "en7"; empty when there's no route
        bool onLink = false;        // the PC's address is in that interface's subnet
        std::string networkId;      // macOS's signature for the network (its router); empty without one, as on a direct cable
        bool localNetworkBlocked = false;   // the address is on a network this Mac is on, but macOS refused a route to it
        int error = 0;                      // errno of that refusal
    };

    // Whether macOS lets LuzLunar reach an address on the local network
    struct LocalCheck {
        bool local = false;         // on a network this Mac is on (a broadcast-capable interface's subnet), or multicast
        bool connected = false;     // macOS let a UDP socket connect to it
        int error = 0;              // errno when it didn't
    };

#ifdef __APPLE__
    // The first address host resolves to, as text; empty if it doesn't. May look it up in DNS.
    std::string numericAddress(const std::string& host);

    // Looks up the route to address (from numericAddress()) without sending anything
    Probe probe(const std::string& address);

    // Connects a UDP socket to address (numeric; a multicast group like Bonjour's 224.0.0.251
    // counts as local), which sends nothing
    LocalCheck checkLocal(const std::string& address);

    // An Ethernet link's speed from SIOCGIFMEDIA's active media word; 0 if unknown
    double mediaMbps(int activeMedia);
#else
    inline std::string numericAddress(const std::string& host) { return host; }
    inline Probe probe(const std::string&) { return Probe(); }
    inline LocalCheck checkLocal(const std::string&) { return LocalCheck(); }
    inline double mediaMbps(int) { return 0; }
#endif
}
