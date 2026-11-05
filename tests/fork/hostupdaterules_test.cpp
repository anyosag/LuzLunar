// Unit tests for app/fork/hostupdaterules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/hostupdaterules_test.cpp
#include "fork/hostupdaterules.h"

#include <cstdio>

using namespace HostUpdateRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Answer answer(const char* state, long long elapsed = 5)
{
    Answer a;
    a.versionBefore = "0.4.8.179";
    a.version = "0.4.8.179";
    a.state = state;
    a.startedSecs = 1000;
    a.nowSecs = 1000 + elapsed;
    return a;
}

static void testOutcomes()
{
    // Right after the request: still on its way
    CHECK(outcome(answer("ready")) == Outcome::Continue);
    CHECK(outcome(answer("installing")) == Outcome::Continue);
    CHECK(outcome(answer("downloading", 300)) == Outcome::Continue);

    // A new version: done
    Answer updated = answer("idle");
    updated.version = "0.4.8.184";
    CHECK(outcome(updated) == Outcome::Updated);

    // Back on the same version, with a result from after the request: it went back
    Answer back = answer("idle");
    back.hasLastResult = true;
    back.lastResultTime = 1100;
    CHECK(outcome(back) == Outcome::WentBack);
    // A result from an earlier install doesn't count
    back.lastResultTime = 900;
    CHECK(outcome(back) == Outcome::UpToDate);

    // Apollo says why it didn't
    CHECK(outcome(answer("failed")) == Outcome::Failed);
    CHECK(outcome(answer("idle")) == Outcome::UpToDate);

    // It waits for the stream to end, however long
    CHECK(outcome(answer("waiting", 3600)) == Outcome::Waiting);

    // Checking: fine for a moment, stuck after 90 s (an Apollo from before the fix)
    CHECK(outcome(answer("checking", 10)) == Outcome::Continue);
    CHECK(outcome(answer("checking", 89)) == Outcome::Continue);
    CHECK(outcome(answer("checking", 90)) == Outcome::StuckChecking);

    // No version known before: only Apollo's own states decide
    Answer unknown = answer("installing");
    unknown.versionBefore.clear();
    unknown.version = "0.4.8.184";
    CHECK(outcome(unknown) == Outcome::Continue);
}

static void testEnds()
{
    CHECK(!ends(Outcome::Continue));
    CHECK(!ends(Outcome::Waiting));
    for (Outcome o : {Outcome::Updated, Outcome::WentBack, Outcome::Failed, Outcome::UpToDate, Outcome::StuckChecking}) {
        CHECK(ends(o));
    }
}

int main()
{
    testOutcomes();
    testEnds();

    if (s_Failures == 0) {
        std::printf("hostupdaterules: all tests passed\n");
        return 0;
    }
    std::printf("hostupdaterules: %d failure(s)\n", s_Failures);
    return 1;
}
