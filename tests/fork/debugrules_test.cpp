// Unit tests for app/fork/forkdebugrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/debugrules_test.cpp
#include "fork/forkdebugrules.h"

#include <cstdio>
#include <string>

using namespace ForkDebugRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

// SDL2's priorities
constexpr int k_Info = 3;
constexpr int k_Warn = 4;
constexpr int k_Critical = 6;

static void testLevels()
{
    CHECK(parseLevel("info") == Level::Info);
    CHECK(parseLevel("configured") == Level::Info);
    CHECK(parseLevel("debug") == Level::Debug);
    CHECK(parseLevel("verbose") == Level::Verbose);
    CHECK(!parseLevel("Debug"));
    CHECK(!parseLevel("warning"));
    CHECK(std::string(levelName(Level::Debug)) == "debug");
    CHECK(std::string(levelName(Level::Info)) == "info");
}

static void testPriorities()
{
    // Info is each category's own; more detail never hides anything that showed
    CHECK(sdlPriority(Level::Info, k_Critical) == k_Critical);
    CHECK(sdlPriority(Level::Info, k_Info) == k_Info);
    CHECK(sdlPriority(Level::Debug, k_Critical) == k_SdlDebug);
    CHECK(sdlPriority(Level::Debug, k_Warn) == k_SdlDebug);
    CHECK(sdlPriority(Level::Debug, k_SdlVerbose) == k_SdlVerbose); // SDL's test category
    CHECK(sdlPriority(Level::Verbose, k_Info) == k_SdlVerbose);
}

static void testMinutes()
{
    CHECK(minutes(false, 0) == k_DefaultMinutes);
    CHECK(minutes(true, 5) == 5);
    CHECK(minutes(true, k_MaxMinutes) == k_MaxMinutes);
    CHECK(!minutes(true, 0));
    CHECK(!minutes(true, k_MaxMinutes + 1));
    CHECK(!minutes(true, 2.5));
    CHECK(!minutes(true, -1));
}

static void testMarks()
{
    CHECK(cleanMark("copy test\n1\t2") == "copy test 1 2");
    std::string longMark(k_MaxMark - 1, 'a');
    longMark += "\xC3\xA9"; // é across the limit
    CHECK(cleanMark(longMark) == std::string(k_MaxMark - 1, 'a'));
    CHECK(cleanMark(std::string(500, 'b')).size() == k_MaxMark);
}

int main()
{
    testLevels();
    testPriorities();
    testMinutes();
    testMarks();
    if (s_Failures > 0) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("All debugrules checks passed\n");
    return 0;
}
