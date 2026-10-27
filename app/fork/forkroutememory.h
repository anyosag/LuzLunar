#pragma once

#include <string>
#include <vector>

#include "forkdisplayroute.h"

// The iMac's route as a launch of "Desktop (multiple displays)" measured it, kept so that Resume
// doesn't measure it again (ForkMultiDisplay::checkRoute(), ForkGroupLaunch). A Resume uses the
// launch's connect times with DisplayExtend's state as it is then, so an iMac that left since still
// goes through this Mac. Qt-free, so the rules are tested (tests/fork/routememory_test.cpp).
namespace ForkRouteMemory
{
    // What a measurement was true for. Any of it different, and a Resume measures again.
    struct Key {
        std::string hostUuid;      // the PC
        std::string imacAddress;   // where DisplayExtend reaches the iMac
        std::string display;       // the Mac's DisplayExtend display, "1920x1080"
        std::string network;       // the network this Mac reaches the PC over, hashed; empty without one (a cable)
    };

    struct Memory {
        Key key;
        std::vector<ForkDisplayRoute::Probe> imacToPc;
        ForkDisplayRoute::Probe macToPc;
        long long measuredAt = 0;  // seconds since the epoch
    };

    // A check that timed the iMac's connection to the PC, so there's something to keep
    bool worthKeeping(const ForkDisplayRoute::Facts& facts);

    Memory remember(const Key& key, const ForkDisplayRoute::Facts& facts, long long measuredAt);

    // Whether memory was measured for exactly what now describes
    bool reusable(const Memory& memory, const Key& now);

    // The facts for a Resume: DisplayExtend's state now, the launch's connect times
    ForkDisplayRoute::Facts recall(const Memory& memory, const ForkDisplayRoute::Facts& now);

    // As the settings keep it, one "name=value" per line. decode() is false for anything it can't read.
    std::string encode(const Memory& memory);
    bool decode(const std::string& text, Memory* memory);
}
