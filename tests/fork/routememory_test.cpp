// Unit tests for app/fork/forkroutememory.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/routememory_test.cpp app/fork/forkroutememory.cpp app/fork/forkdisplayroute.cpp
#include "fork/forkroutememory.h"

#include <clocale>
#include <locale>
#include <stdexcept>
#include <cstdio>
#include <string>

using namespace ForkRouteMemory;
using ForkDisplayRoute::Facts;
using ForkDisplayRoute::Probe;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Probe probe(const char* address, double median, double worst, int failures = 0)
{
    Probe p;
    p.address = address;
    p.count = 30;
    p.failures = failures;
    p.medianMs = median;
    p.maxMs = worst;
    return p;
}

static Key key()
{
    Key k;
    k.hostUuid = "7B79D259-0C61-4D36-BCF9-C3A6FB79C2FC";
    k.imacAddress = "10.79.5.83";
    k.display = "1920x1080";
    k.network = "3f2a9c";
    return k;
}

// What a launch measured: the iMac reaches the PC over the internet, not at its home address
static Facts measured()
{
    Facts f;
    f.bridge = f.imacConnected = f.directSupported = f.moonlightVerified = f.paired = true;
    f.imacToPc = { probe("73.100.235.17", 12.5, 23.25), probe("10.0.0.77", -1, -1, 3),
                   probe("2601:18a:817f:663b::190f", -1, -1, 3) };
    f.macToPc = probe("73.100.235.17", 18, 23);
    f.displayExtendP50Ms = 27;
    f.displayExtendP95Ms = 29;
    f.displayExtendFrames = 600;
    return f;
}

static bool sameProbe(const Probe& a, const Probe& b)
{
    return a.address == b.address && a.count == b.count && a.failures == b.failures &&
           a.medianMs == b.medianMs && a.maxMs == b.maxMs;
}

static void testWorthKeeping()
{
    CHECK(worthKeeping(measured()));
    Facts ineligible = measured();
    ineligible.imacToPc.clear();   // the iMac couldn't go straight from the PC, so nothing was timed
    CHECK(!worthKeeping(ineligible));
}

static void testReusableOnlyForTheSameEverything()
{
    Memory memory = remember(key(), measured(), 1793120157);
    CHECK(reusable(memory, key()));

    Key other = key();
    other.hostUuid = "another PC";
    CHECK(!reusable(memory, other));
    other = key();
    other.imacAddress = "192.168.1.31";   // the iMac moved
    CHECK(!reusable(memory, other));
    other = key();
    other.display = "2560x1440";           // DisplayExtend's display changed
    CHECK(!reusable(memory, other));
    other = key();
    other.network = "b71e0d";              // this Mac is on another network
    CHECK(!reusable(memory, other));

    Key unknown = key();
    unknown.imacAddress.clear();          // DisplayExtend didn't say where the iMac is
    CHECK(!reusable(memory, unknown));
    unknown = key();
    unknown.hostUuid.clear();
    CHECK(!reusable(memory, unknown));

    // Nothing timed, nothing to reuse
    Facts untimed = measured();
    untimed.imacToPc.clear();
    CHECK(!reusable(remember(key(), untimed, 1), key()));

    // On a cable (no network identity) both times: the same place
    Key cable = key();
    cable.network.clear();
    CHECK(reusable(remember(cable, measured(), 1), cable));
    CHECK(!reusable(remember(cable, measured(), 1), key()));
}

static void testRecallTakesTheStateNowAndTheTimesThen()
{
    Memory memory = remember(key(), measured(), 1);
    Facts now;
    now.bridge = true;
    now.imacConnected = false;   // the iMac left since the launch
    now.displayExtendP50Ms = 31;
    Facts facts = recall(memory, now);
    CHECK(facts.bridge && !facts.imacConnected && !facts.directSupported);
    CHECK(facts.displayExtendP50Ms == 31);
    CHECK(facts.imacToPc.size() == 3 && sameProbe(facts.imacToPc[0], measured().imacToPc[0]));
    CHECK(sameProbe(facts.macToPc, measured().macToPc));
}

static void testRoundTrip()
{
    Memory memory = remember(key(), measured(), 1793120157);
    Memory read;
    CHECK(decode(encode(memory), &read));
    CHECK(read.key.hostUuid == memory.key.hostUuid && read.key.imacAddress == memory.key.imacAddress &&
          read.key.display == memory.key.display && read.key.network == memory.key.network);
    CHECK(read.measuredAt == 1793120157);
    CHECK(read.imacToPc.size() == 3);
    for (size_t i = 0; i < read.imacToPc.size() && i < 3; i++) {
        CHECK(sameProbe(read.imacToPc[i], memory.imacToPc[i]));
    }
    CHECK(sameProbe(read.macToPc, memory.macToPc));
    CHECK(reusable(read, key()));
}

// Qt sets the user's locale; a decimal comma must not change what's written or read
static void testRoundTripUnderADecimalCommaLocale()
{
    std::locale before;
    try {
        std::locale::global(std::locale("es_ES.UTF-8"));
    }
    catch (const std::exception&) {
        std::printf("note: no es_ES.UTF-8 locale here, so the decimal comma case isn't exercised\n");
    }
    std::setlocale(LC_ALL, "es_ES.UTF-8");
    std::string text = encode(remember(key(), measured(), 1));
    Memory read;
    CHECK(text.find("12.5") != std::string::npos);
    CHECK(decode(text, &read));
    CHECK(read.imacToPc.size() == 3 && read.imacToPc[0].medianMs == 12.5 && read.imacToPc[0].maxMs == 23.25);
    std::locale::global(before);
    std::setlocale(LC_ALL, "C");
}

static void testDecodeRefusesWhatItCantRead()
{
    Memory read;
    CHECK(!decode("", &read));
    CHECK(!decode("v=2\nhost=x\nmac=a,1,0,1,1\nprobe=a,1,0,1,1\n", &read));         // another version
    CHECK(!decode("v=1\nmac=a,1,0,1,1\nprobe=a,1,0,1,1\n", &read));                 // no PC
    CHECK(!decode("v=1\nhost=x\nprobe=a,1,0,1,1\n", &read));                        // no Mac probe
    CHECK(!decode("v=1\nhost=x\nmac=a,1,0,1,1\n", &read));                          // no iMac probe
    CHECK(!decode("v=1\nhost=x\nmac=a,1,0,1,1\nprobe=a,1,zero,1,1\n", &read));      // a bad number
    CHECK(!decode("v=1\nhost=x\nmac=a,1,0,1,1\nprobe=a,1,0,1\n", &read));           // a field short
    CHECK(decode("v=1\nhost=x\nmac=a,1,0,1,1\nprobe=a,1,0,-1,-1\n", &read));        // -1 is "none connected"
}

int main()
{
    testWorthKeeping();
    testReusableOnlyForTheSameEverything();
    testRecallTakesTheStateNowAndTheTimesThen();
    testRoundTrip();
    testRoundTripUnderADecimalCommaLocale();
    testDecodeRefusesWhatItCantRead();

    if (s_Failures > 0) {
        std::printf("%d check(s) failed\n", s_Failures);
        return 1;
    }
    std::printf("All route memory tests passed\n");
    return 0;
}
