#pragma once

#include <functional>

#include <QString>

#include "forklinkrules.h"

class NvComputer;

// The Mac's connection to the PC for the notch bar: which interface carries the stream (Ethernet,
// Wi-Fi, ...) and how fast it is, shown on networks that have carried a LAN stream of that PC
// (forklinkrules.h). Moonlight's reachability check at stream start says whether a stream goes
// over the LAN. The networks where it did are remembered per PC in the settings, as hashes.
namespace ForkNetworkLink
{
    constexpr int k_NotChecked = -1;

    // From Session::startConnectionAsync() on its connection thread, before the stream's fork
    // extensions exist. reachability is NvComputer::getActiveAddressReachability()'s result, or
    // k_NotChecked when a custom packet size skips the check.
    void noteStreamStart(NvComputer* computer, int reachability = k_NotChecked);

    // From ForkStreamExtensions, on the main thread. Probes the link on a thread of its own,
    // remembers the network when the stream goes over the LAN, and logs it. With refresh (the notch
    // bar is up) it probes again every 5 seconds, so the bar follows a stream that moves to
    // another interface, until stop(). onFirstProbe, when given, hears once, on the probing thread,
    // whether the stream goes over the LAN (the Mac drive asks the PC only then).
    void start(bool refresh, std::function<void(bool viaLan)> onFirstProbe = {});
    void stop();

    // The last probe, for the notch bar: its stats item and Stream status. Any thread.
    struct Current {
        bool known = false;             // probed during this stream
        ForkLinkRules::Link link;
        bool viaLan = false;
        bool shown = false;             // on a network the bar shows the link on (ForkLinkRules::shouldShow())
    };
    Current current();
}
