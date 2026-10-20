// Unit tests for app/fork/macdriverules.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/macdriverules_test.cpp app/fork/macdriverules.cpp
#include "fork/macdriverules.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace MacDriveRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

using List = std::vector<std::string>;

static void testShares()
{
    // A share of the startup disk comes first, whoever the account is
    CHECK((shares("Macintosh HD", false, "Macintosh HD", "gonzalo") == List { "Macintosh HD", "gonzalo" }));
    CHECK((shares("Whole Mac", true, "Macintosh HD", "gonzalo") == List { "Whole Mac", "gonzalo" }));

    // Without one, an administrator gets macOS's share of the startup volume, by its name
    CHECK((shares("", true, "Macintosh HD", "gonzalo") == List { "Macintosh HD", "gonzalo" }));
    CHECK((shares("", true, "Disco", "gonzalo") == List { "Disco", "gonzalo" }));

    // Otherwise only the home folder
    CHECK((shares("", false, "Macintosh HD", "gonzalo") == List { "gonzalo" }));

    // Nothing empty, nothing twice
    CHECK((shares("", true, "", "gonzalo") == List { "gonzalo" }));
    CHECK((shares("gonzalo", false, "Macintosh HD", "gonzalo") == List { "gonzalo" }));
    CHECK(shares("", false, "", "").empty());
}

static void testHostSupport()
{
    CHECK(hostSupport("") == HostSupport::Missing);
    CHECK(hostSupport("0") == HostSupport::Off);
    CHECK(hostSupport("1") == HostSupport::On);
    CHECK(hostSupport("yes") == HostSupport::Off);
}

static Facts ready()
{
    Facts facts;
    facts.enabled = true;
    facts.viaLan = true;
    facts.host = HostSupport::On;
    facts.permissions = 0x077F1F00;
    facts.passwordSaved = true;
    facts.passwordValid = true;
    facts.sharingOn = true;
    return facts;
}

static void testSkip()
{
    CHECK(skip(ready()) == Skip::None);

    Facts facts = ready();
    facts.enabled = false;
    CHECK(skip(facts) == Skip::Off);

    // A stream over a VPN or the internet doesn't ask, and says nothing
    facts = ready();
    facts.viaLan = false;
    CHECK(skip(facts) == Skip::NotLan);
    CHECK(silent(Skip::NotLan));
    CHECK(silent(Skip::Off));
    CHECK(!silent(Skip::NoPassword));

    // A host that doesn't answer as Apollo, with no <Permission>, is another host or didn't answer:
    // not an Apollo to update
    facts = ready();
    facts.permissions = -1;
    facts.host = HostSupport::Missing;
    CHECK(skip(facts) == Skip::NotApollo);
    CHECK(silent(Skip::NotApollo));

    facts = ready();
    facts.host = HostSupport::Missing;
    CHECK(skip(facts) == Skip::HostTooOld);
    facts.host = HostSupport::Off;
    CHECK(skip(facts) == Skip::HostOff);

    // The Network Drive permission, 0x00400000; every other permission doesn't count
    facts = ready();
    facts.permissions = 0x073F1F00;
    CHECK(skip(facts) == Skip::NoPermission);
    facts.permissions = 0;
    CHECK(skip(facts) == Skip::NoPermission);
    facts.permissions = k_PermClientDrive;
    CHECK(skip(facts) == Skip::None);

    facts = ready();
    facts.passwordSaved = false;
    facts.passwordValid = false;
    CHECK(skip(facts) == Skip::NoPassword);
    facts = ready();
    facts.passwordValid = false;
    CHECK(skip(facts) == Skip::PasswordChanged);

    facts = ready();
    facts.sharingOn = false;
    CHECK(skip(facts) == Skip::SharingOff);
}

static Reply reply(int status, const char* state, const char* share = "", bool added = false, const char* error = "")
{
    Reply r;
    r.httpStatus = status;
    r.state = state;
    r.share = share;
    r.letter = r.state == "mapped" ? "M" : "";
    r.added = added;
    r.error = error;
    return r;
}

static void testOutcome()
{
    List sent { "Macintosh HD", "gonzalo" };
    CHECK(outcome(reply(202, "mapping"), sent) == Outcome::Pending);
    CHECK(outcome(reply(200, "mapped", "Macintosh HD", true), sent) == Outcome::Added);
    CHECK(outcome(reply(200, "mapped", "gonzalo", true), sent) == Outcome::AddedHome);
    CHECK(outcome(reply(200, "mapped", "Macintosh HD", false), sent) == Outcome::Kept);
    CHECK(outcome(reply(200, "mapped", "gonzalo", true), List { "gonzalo" }) == Outcome::Added);

    CHECK(outcome(reply(200, "failed", "", false, "logon"), sent) == Outcome::WrongPassword);
    CHECK(outcome(reply(200, "failed", "", false, "ntlm_blocked"), sent) == Outcome::NtlmBlocked);
    CHECK(outcome(reply(200, "failed", "", false, "denied"), sent) == Outcome::Denied);
    CHECK(outcome(reply(200, "failed", "", false, "no_share"), sent) == Outcome::NoShare);
    CHECK(outcome(reply(200, "failed", "", false, "unreachable"), sent) == Outcome::Unreachable);
    CHECK(outcome(reply(200, "failed", "", false, "conflict"), sent) == Outcome::Conflict);
    CHECK(outcome(reply(200, "failed", "", false, "no_letter"), sent) == Outcome::NoLetter);
    CHECK(outcome(reply(200, "failed", "", false, "no_user"), sent) == Outcome::NobodySignedIn);
    CHECK(outcome(reply(200, "failed", "", false, "helper"), sent) == Outcome::Failed);
    CHECK(outcome(reply(200, "none"), sent) == Outcome::Failed);

    CHECK(outcome(reply(401, ""), sent) == Outcome::Refused);
    CHECK(outcome(reply(403, ""), sent) == Outcome::Refused);
    CHECK(outcome(reply(404, ""), sent) == Outcome::Refused);
    CHECK(outcome(reply(400, ""), sent) == Outcome::Failed);
    CHECK(outcome(reply(0, ""), sent) == Outcome::Failed);

    CHECK(!worthTelling(Outcome::Pending));
    CHECK(!worthTelling(Outcome::Kept));
    CHECK(worthTelling(Outcome::Added));
    CHECK(worthTelling(Outcome::WrongPassword));
}

int main()
{
    testShares();
    testHostSupport();
    testSkip();
    testOutcome();

    if (s_Failures == 0) {
        std::printf("macdriverules: all tests passed\n");
        return 0;
    }
    std::printf("macdriverules: %d failure(s)\n", s_Failures);
    return 1;
}
