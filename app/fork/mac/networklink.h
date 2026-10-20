#pragma once

#include <string>

#include "fork/forklinkrules.h"

// The Mac side of the notch bar's link badge (forknetworklink.h): which interface carries traffic to
// the PC, what kind it is and how fast, and macOS's identity for the network it's on. Nothing here
// sends a packet or needs a permission. Without Location access macOS hides Wi-Fi network names, so
// none are read. Thread-safe; meant for a thread of its own.
namespace MacNetworkLink
{
    struct Probe {
        ForkLinkRules::Link link;
        std::string interfaceName;  // BSD name, like "en7"; empty when there's no route
        bool onLink = false;        // the PC's address is in that interface's subnet
        std::string networkId;      // macOS's signature for the network (its router); empty without one, as on a direct cable
    };

#ifdef __APPLE__
    // The first address host resolves to, as text; empty if it doesn't. May look it up in DNS.
    std::string numericAddress(const std::string& host);

    // Looks up the route to address (from numericAddress()) without sending anything
    Probe probe(const std::string& address);

    // An Ethernet link's speed from SIOCGIFMEDIA's active media word; 0 if unknown
    double mediaMbps(int activeMedia);
#else
    inline std::string numericAddress(const std::string& host) { return host; }
    inline Probe probe(const std::string&) { return Probe(); }
    inline double mediaMbps(int) { return 0; }
#endif
}
