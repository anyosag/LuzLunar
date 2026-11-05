#pragma once

#include <string>

// [fork] Update Apollo, seen from LuzLunar (forkhostupdates.*): once this Mac asked a PC to update,
// what each answer from its /actions/update means. Before, an update that ended any other way than
// a new version or a rollback ended silently, and an Apollo stuck at "checking" (anyosag/Apollo's
// updater before it put the state back after a check) kept LuzLunar waiting for 8 minutes, then
// brought Update Apollo back, so clicks seemed to do nothing. Free of Qt, so tests can build it
// alone (tests/fork/hostupdaterules_test.cpp).
namespace HostUpdateRules
{
    // A check takes seconds; past this, an Apollo still "checking" after Update was asked is stuck
    constexpr long long k_StuckCheckingSecs = 90;

    enum class Outcome {
        Continue,       // still updating: keep asking
        Updated,        // the PC runs another version now
        WentBack,       // the install ended and the PC is back on its version (Apollo's last result says why)
        Failed,         // Apollo says the install failed; its message says why
        UpToDate,       // Apollo has nothing newer to install
        Waiting,        // Apollo installs once nobody streams, however long that takes
        StuckChecking,  // an older Apollo stuck at "checking": it needs restarting
    };

    // One answer from the PC while it updates
    struct Answer {
        std::string versionBefore;      // the version when Update was asked
        std::string version;            // the version now
        std::string state;              // idle, checking, downloading, ready, waiting, installing, failed
        bool hasLastResult = false;     // Apollo reports how an install ended
        long long lastResultTime = 0;   // when, in seconds since 1970
        long long startedSecs = 0;      // when Update was asked (or the wait for a stream began)
        long long nowSecs = 0;
    };

    inline Outcome outcome(const Answer& a)
    {
        if (!a.versionBefore.empty() && !a.version.empty() && a.version != a.versionBefore) {
            return Outcome::Updated;
        }
        if (a.hasLastResult && a.lastResultTime >= a.startedSecs) {
            return Outcome::WentBack;
        }
        if (a.state == "failed") {
            return Outcome::Failed;
        }
        if (a.state == "idle") {
            return Outcome::UpToDate;
        }
        if (a.state == "waiting") {
            return Outcome::Waiting;
        }
        if (a.state == "checking" && a.nowSecs - a.startedSecs >= k_StuckCheckingSecs) {
            return Outcome::StuckChecking;
        }
        return Outcome::Continue;
    }

    // Whether the update is over, so Update Apollo comes back and a toast says how it went
    inline bool ends(Outcome o)
    {
        return o != Outcome::Continue && o != Outcome::Waiting;
    }
}
