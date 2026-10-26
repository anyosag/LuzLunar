#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "clientdisplay.h"

// "Desktop (multiple displays)", an app anyosag/Apollo offers: Windows gets one virtual display per
// Mac display, arranged like the Mac's, and each display streams in its own session. Slot 0 is
// LuzLunar's main stream, with the input and the audio; every other slot is a video-only helper
// process, or for DisplayExtend's display possibly the iMac's own Moonlight (an "external" slot).
// Slot 0's launch declares the whole group with luzGroup=, so Apollo can make and arrange every
// display at once; the other slots join with luzGroupId= and luzSlot=.
//
// Kept free of Qt, SDL and AppKit so it can be unit tested on its own
// (tests/fork/displaygroup_test.cpp); forkmultidisplay.* fills in the Mac's displays.
namespace ForkDisplayGroup
{
    // One Mac display, as the plan needs it
    struct MacDisplay {
        uint32_t id = 0;                         // CGDirectDisplayID
        int x = 0, y = 0;                        // top-left corner in global points (y down, the main display at 0,0)
        int pointWidth = 0, pointHeight = 0;
        int width = 0, height = 0;               // the pixels a stream fills: the panel, or below the notch
        int maxRefresh = 0;                      // Hz; 0 if unknown
        bool isMain = false;                     // has the menu bar
        bool isBuiltin = false;
        bool isDisplayExtend = false;            // DisplayExtend's virtual display, shown on the iMac
        bool hdr = false;
        uint32_t vendor = 0, model = 0, serial = 0;   // for a slot order that stays the same between launches
        std::string name;
        ClientDisplay::Description screen;       // what the host's virtual display is told about this screen
    };

    // Slot 0's stream: the settings, with the app's stream profile applied
    struct Stream {
        int width = 0, height = 0, fps = 0, bitrateKbps = 0;
        bool hdr = false;
    };

    struct Slot {
        int slot = 0;
        uint32_t displayId = 0;
        std::string name;
        int width = 0, height = 0, fps = 0, bitrateKbps = 0;
        bool hdr = false;
        bool external = false;                   // the iMac's Moonlight may stream it instead of a helper
        int x = 0, y = 0;                        // its place in the Windows desktop, in pixels (slot 0 at 0,0)
        ClientDisplay::Description screen;
    };

    struct Plan {
        std::string id;                          // 16 hex digits, new for each launch
        std::vector<Slot> slotList;                 // slot 0 first; empty when there's no group to make
    };

    // Which display streams slot 0: the main display, or the built-in one when the main display is
    // DisplayExtend's (whose picture may come from the iMac's own Moonlight, which has no input).
    // -1 for an empty list.
    int mainIndex(const std::vector<MacDisplay>& displays);

    // The group for these displays, at most maxSlots of them (what the host offers). Slot 0 streams
    // `stream`; each other display streams its own size at the same frame rate (capped at its
    // refresh rate) and a bitrate scaled by its pixel rate. Empty with fewer than two displays.
    Plan plan(const std::vector<MacDisplay>& displays, const Stream& stream, int maxSlots, const std::string& id);

    struct Rect {
        int x = 0, y = 0, width = 0, height = 0;
    };

    // Origins in the Windows desktop for displays arranged like the Mac's. mac holds each display's
    // rectangle in points, pixels each one's size in Windows. Displays are placed outward from
    // `first` (at 0,0): each on the same side of a neighbour it touches on the Mac, at the same
    // fraction along the shared edge. One that would overlap, or touches nothing, goes at the end
    // of a row to the right. The result touches without overlapping, as Windows requires.
    std::vector<Rect> windowsLayout(const std::vector<Rect>& mac, const std::vector<Rect>& pixels, size_t first);

    // The JSON slot 0's launch declares the group with (Apollo's contract, "v":1)
    std::string declarationJson(const Plan& plan);

    // The /launch and /resume arguments, each starting with "&": slot 0's declaration, and a join
    std::string launchArgs(const Plan& plan);
    std::string joinArgs(const std::string& id, int slot);

    // RFC 4648 base64url without padding
    std::string base64Url(const std::string& bytes);

    // A JSON string literal, quoted and escaped
    std::string jsonString(const std::string& text);

    // The screen as the declaration describes it: mm, panel, safe, hz, gamut, hdr and name, with the
    // same values as the luzMm, luzPanel, luzSafe, luzHz, luzGamut, luzHdr and luzName arguments
    std::string screenJson(const ClientDisplay::Description& screen);
}
