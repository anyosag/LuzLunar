#include "localnetworkrules.h"

namespace LocalNetworkRules
{
Access combine(const std::vector<Check>& checks)
{
    bool anyLocal = false;
    for (const Check& check : checks) {
        if (!check.local) {
            continue;
        }
        if (!check.connected) {
            return Access::Blocked;
        }
        anyLocal = true;
    }
    return anyLocal ? Access::Allowed : Access::Unknown;
}

int recheckSeconds(Access access)
{
    return access == Access::Allowed ? 60 : 5;
}

Notice notice(Access before, Access now, bool blockedToldThisRun, bool justUpdated)
{
    if (now == Access::Blocked) {
        if (blockedToldThisRun || before == Access::Blocked) {
            return Notice::None;
        }
        return justUpdated ? Notice::BlockedAfterUpdate : Notice::Blocked;
    }
    if (now == Access::Allowed && before == Access::Blocked) {
        return Notice::Restored;
    }
    return Notice::None;
}

bool moveToLan(Access before, Access now, bool lanAddressLocal, bool online, bool activeIsLan)
{
    return before == Access::Blocked && now == Access::Allowed && lanAddressLocal && online && !activeIsLan;
}

std::string logLine(Access access, const std::string& refusedAddress, int error)
{
    switch (access) {
    case Access::Blocked: {
        std::string line = "[fork] Local Network: blocked";
        if (!refusedAddress.empty()) {
            line += " (macOS refused " + refusedAddress + ", errno " + std::to_string(error) + ")";
        }
        return line + ", so PCs on this network are reached through the router, if at all. "
                      "Turn LuzLunar on in System Settings › Privacy & Security › Local Network.";
    }
    case Access::Allowed:
        return "[fork] Local Network: allowed";
    case Access::Unknown:
        break;
    }
    return "[fork] Local Network: nothing local to check";
}
}
