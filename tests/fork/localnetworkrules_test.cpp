// Unit tests for app/fork/localnetworkrules.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/localnetworkrules_test.cpp app/fork/localnetworkrules.cpp
#include "fork/localnetworkrules.h"

#include <cstdio>
#include <string>

using namespace LocalNetworkRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Check check(bool local, bool connected)
{
    Check c;
    c.local = local;
    c.connected = connected;
    return c;
}

static void testCombine()
{
    // Nothing to go on: offline, or only addresses a VPN or the internet carries
    CHECK(combine({}) == Access::Unknown);
    CHECK(combine({ check(false, false) }) == Access::Unknown);
    CHECK(combine({ check(false, true), check(false, false) }) == Access::Unknown);

    // Bonjour's group and the PC's LAN address both went through
    CHECK(combine({ check(true, true) }) == Access::Allowed);
    CHECK(combine({ check(true, true), check(true, true) }) == Access::Allowed);
    // A remote address that failed says nothing about the local network
    CHECK(combine({ check(true, true), check(false, false) }) == Access::Allowed);

    // macOS refused a local address: blocked, whatever else went through
    CHECK(combine({ check(true, false) }) == Access::Blocked);
    CHECK(combine({ check(true, true), check(true, false) }) == Access::Blocked);
    CHECK(combine({ check(true, false), check(true, true) }) == Access::Blocked);
    CHECK(combine({ check(false, true), check(true, false) }) == Access::Blocked);
}

static void testRecheck()
{
    // Soon while it matters, so turning it on in System Settings shows at once
    CHECK(recheckSeconds(Access::Blocked) == 5);
    CHECK(recheckSeconds(Access::Unknown) == 5);
    CHECK(recheckSeconds(Access::Allowed) == 60);
}

static void testNotice()
{
    // Found blocked: told once per run
    CHECK(notice(Access::Unknown, Access::Blocked, false, false) == Notice::Blocked);
    CHECK(notice(Access::Allowed, Access::Blocked, false, false) == Notice::Blocked);
    CHECK(notice(Access::Unknown, Access::Blocked, true, false) == Notice::None);
    CHECK(notice(Access::Allowed, Access::Blocked, true, false) == Notice::None);
    // Still blocked: nothing more
    CHECK(notice(Access::Blocked, Access::Blocked, false, false) == Notice::None);
    CHECK(notice(Access::Blocked, Access::Blocked, true, true) == Notice::None);

    // Right after an update: the update's own wording
    CHECK(notice(Access::Unknown, Access::Blocked, false, true) == Notice::BlockedAfterUpdate);
    CHECK(notice(Access::Unknown, Access::Blocked, true, true) == Notice::None);

    // Turned on again
    CHECK(notice(Access::Blocked, Access::Allowed, true, false) == Notice::Restored);
    CHECK(notice(Access::Blocked, Access::Allowed, true, true) == Notice::Restored);
    // Allowed from the start, or going offline: nothing to say
    CHECK(notice(Access::Unknown, Access::Allowed, false, false) == Notice::None);
    CHECK(notice(Access::Allowed, Access::Allowed, false, true) == Notice::None);
    CHECK(notice(Access::Blocked, Access::Unknown, true, false) == Notice::None);
    CHECK(notice(Access::Allowed, Access::Unknown, false, false) == Notice::None);
}

static void testMoveToLan()
{
    // Access came back while the PC answered through the router: try its LAN address now
    CHECK(moveToLan(Access::Blocked, Access::Allowed, true, true, false));

    // Already on the LAN, offline, or its LAN address isn't on this network
    CHECK(!moveToLan(Access::Blocked, Access::Allowed, true, true, true));
    CHECK(!moveToLan(Access::Blocked, Access::Allowed, true, false, false));
    CHECK(!moveToLan(Access::Blocked, Access::Allowed, false, true, false));

    // Only when access just came back; Bonjour does the rest
    CHECK(!moveToLan(Access::Allowed, Access::Allowed, true, true, false));
    CHECK(!moveToLan(Access::Unknown, Access::Allowed, true, true, false));
    CHECK(!moveToLan(Access::Blocked, Access::Blocked, true, true, false));
    CHECK(!moveToLan(Access::Blocked, Access::Unknown, true, true, false));
}

static void testLog()
{
    CHECK(logLine(Access::Allowed, "", 0) == "[fork] Local Network: allowed");
    CHECK(logLine(Access::Unknown, "", 0) == "[fork] Local Network: nothing local to check");

    std::string blocked = logLine(Access::Blocked, "10.0.0.77", 65);
    CHECK(blocked.rfind("[fork] Local Network: blocked (macOS refused 10.0.0.77, errno 65), so PCs", 0) == 0);
    CHECK(blocked.find("Privacy & Security › Local Network") != std::string::npos);
    CHECK(logLine(Access::Blocked, "", 0).rfind("[fork] Local Network: blocked, so PCs", 0) == 0);
}

int main()
{
    testCombine();
    testRecheck();
    testNotice();
    testMoveToLan();
    testLog();

    if (s_Failures == 0) {
        std::printf("localnetworkrules: all tests passed\n");
        return 0;
    }
    std::printf("localnetworkrules: %d failure(s)\n", s_Failures);
    return 1;
}
