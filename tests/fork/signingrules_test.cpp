// Unit tests for app/fork/signingrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/signingrules_test.cpp
#include "fork/signingrules.h"

#include <cstdio>
#include <string>

using namespace SigningRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static void testTeamId()
{
    CHECK(validTeamId("ABCDE12345"));
    CHECK(validTeamId("0123456789"));
    CHECK(!validTeamId(""));
    CHECK(!validTeamId("ABCDE1234"));       // too short
    CHECK(!validTeamId("ABCDE123456"));     // too long
    CHECK(!validTeamId("abcde12345"));      // Team IDs are upper case
    CHECK(!validTeamId("ABCDE 2345"));
    CHECK(!validTeamId("ABCDE\"2345"));     // would end the quoted string
}

static void testIdentifier()
{
    CHECK(validIdentifier("com.moonlight-stream.Moonlight"));
    CHECK(validIdentifier("a_b.c-d"));
    CHECK(!validIdentifier(""));
    CHECK(!validIdentifier("com.example\" or anchor apple"));
    CHECK(!validIdentifier("com.example app"));
    CHECK(!validIdentifier(std::string(256, 'a')));
}

static void testRequirement()
{
    CHECK(teamRequirement("com.moonlight-stream.Moonlight", "ABCDE12345") ==
          "anchor apple generic and identifier \"com.moonlight-stream.Moonlight\" and certificate leaf[subject.OU] = \"ABCDE12345\"");

    // No Team ID given (the build's default): nothing more is accepted
    CHECK(teamRequirement("com.moonlight-stream.Moonlight", "").empty());
    // Anything that could change the requirement's meaning is refused
    CHECK(teamRequirement("com.moonlight-stream.Moonlight", "ABCDE1234\"").empty());
    CHECK(teamRequirement("x\" or anchor apple generic or identifier \"y", "ABCDE12345").empty());
    CHECK(teamRequirement("", "ABCDE12345").empty());
}

int main()
{
    testTeamId();
    testIdentifier();
    testRequirement();

    if (s_Failures == 0) {
        std::printf("signingrules: all tests passed\n");
        return 0;
    }
    std::printf("signingrules: %d failure(s)\n", s_Failures);
    return 1;
}
