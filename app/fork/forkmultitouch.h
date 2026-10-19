#pragma once

// Contact sizes for palm rejection (forktrackpad.*), from Apple's private MultitouchSupport
// framework: AppKit's NSTouch carries no size, but the framework that feeds it reports each
// contact's ellipse and the hand part Apple's driver gave it (fingerID 1 thumb, 2-5 fingers,
// 6-7 palm). Gestures apps like BetterTouchTool read it the same way. It's loaded at run time, so
// nothing links against it: without it (or if its contacts stop making sense), palm rejection
// goes by macOS's resting touches, typing and position alone.
//
// Plain C++ without AppKit, so tests/fork/multitouch_test.cpp can check the matching on any
// system; start() only finds the framework on a Mac.

#include <cstdint>
#include <string>
#include <vector>

#include "forktrackpad.h"

namespace ForkMultitouch
{
    // One contact on a pad, as MultitouchSupport reports it
    struct Contact {
        float x = 0;  // 0 at the pad's left, 1 at its right
        float y = 0;  // 0 at its bottom, 1 at its top, like NSTouch
        int state = 0;  // 3 make touch, 4 touching, 5 break touch, 6 linger
        int fingerId = 0;  // 1 thumb, 2-5 fingers, 6-7 palm, 0 unknown
        float minorAxisMm = 0;
        float majorAxisMm = 0;
    };

    // How far apart (on a 0-1 pad) an NSTouch and a contact may be and still be the same finger
    constexpr float k_MatchDistance = 0.06f;

    // Whether a contact is on the pad (not hovering, not gone)
    bool touchingState(int state);

    // Whether a contact's values are plausible: off, it means the framework's layout changed
    bool plausible(const Contact& c);

    // Gives each touch the contact nearest to it, closest pairs first, each contact at most once.
    // Read upside down too, in case the framework's y counts down the pad: the reading that pairs
    // more touches wins.
    void annotate(std::vector<ForkTrackpad::Touch>& touches, const std::vector<Contact>& contacts);

    // Loads the framework and listens to every pad. False when it can't; why() says why.
    bool start();
    void stop();

    // What every pad reports right now: none while it isn't running
    std::vector<Contact> contactsNow();

    // Adds what the pads report right now to AppKit's touches
    void annotateNow(std::vector<ForkTrackpad::Touch>& touches);

    // Why it isn't running, or stopped: for the log
    std::string why();
}
