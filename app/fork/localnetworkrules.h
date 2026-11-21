#pragma once

#include <string>
#include <vector>

// Whether macOS lets LuzLunar use the local network (Privacy & Security › Local Network, macOS 15
// and later), from checks that send nothing, and what LuzLunar says and does about it. Kept free of
// Qt and macOS so it can be unit tested on its own (tests/fork/localnetworkrules_test.cpp);
// forklocalnetwork.cpp does the checking.
//
// macOS keeps a separate Local Network decision for builds it can't tell apart reliably (Apple's
// TN3179 asks for an Apple-issued signing identity), so after an update the new LuzLunar may be
// turned off while an older one is on. It then can't reach a PC's LAN address or Bonjour, but still
// reaches the PC through the router's public address, so streams quietly go through the router.
namespace LocalNetworkRules
{
    enum class Access {
        Unknown,    // nothing local to check: offline, or no local network
        Allowed,
        Blocked,
    };

    // One check: connecting a UDP socket to an address picks a route without sending anything, and
    // macOS's local network privacy refuses it for an address on a local network
    struct Check {
        bool local = false;     // the address is on a network this Mac is on (or multicast, like Bonjour's)
        bool connected = false; // macOS let LuzLunar connect a UDP socket to it
    };

    // Blocked when any local address was refused, Allowed when local ones went through, else Unknown.
    // Anything that isn't local says nothing: a VPN or the internet route those.
    Access combine(const std::vector<Check>& checks);

    // Seconds until the next check while LuzLunar is the active app: soon while it's blocked or
    // unknown, so turning it on in System Settings shows at once, else seldom
    int recheckSeconds(Access access);

    // What LuzLunar tells you as access changes. Each at most once per run, except Restored.
    enum class Notice {
        None,
        Blocked,             // found blocked (once per run)
        BlockedAfterUpdate,  // found blocked on the first check after an update installed
        Restored,            // blocked before, allowed now
    };
    Notice notice(Access before, Access now, bool blockedToldThisRun, bool justUpdated);

    // Whether a PC moves to its LAN address now, as when Bonjour finds it there: access just came
    // back, the PC's LAN address is on this network, and the PC is online somewhere else (the
    // router's public address, say)
    bool moveToLan(Access before, Access now, bool lanAddressLocal, bool online, bool activeIsLan);

    // The log line for a change: "[fork] Local Network: blocked (macOS refused 10.0.0.77, errno
    // 65), so PCs here are reached through the router, if at all"
    std::string logLine(Access access, const std::string& refusedAddress, int error);
}
