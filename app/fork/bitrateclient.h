#pragma once

#include <memory>

#include "SDL_compat.h"
#include "bitratestate.h"

class NvComputer;

// [fork] Changes the stream's bitrate on LuzLunar's Apollo while it streams (POST /actions/bitrate),
// for adaptive bitrate (adaptivebitrate.*) and the notch bar's Quality slider. One worker thread for
// all of them, and the newest request replaces one still waiting. ForkStreamExtensions owns it for
// the stream.
//
// When the stream starts it asks serverinfo whether the PC changes bitrates live (LuzBitrate), then
// GET /actions/bitrate what it can do now, again each second for up to 10 s while an Apollo that says
// so ("known") hasn't created its encoder yet. A request the PC doesn't answer is sent again until it
// does or a newer one replaces it. A change the PC takes (202) is asked about again until it's
// applied, for up to 10 s, which also catches an older Apollo's encoder refusing it only then. What it learns
// goes to the stats (ForkStreamStats::setBitrate()) and reaches the main thread as an SDL event, as
// the Qt event loop is paused while streaming.
class BitrateClient
{
public:
    // ownKbps: the user's bitrate, which the stream starts at
    BitrateClient(NvComputer* computer, int ownKbps);
    ~BitrateClient();

    BitrateClient(const BitrateClient&) = delete;
    BitrateClient& operator=(const BitrateClient&) = delete;

    // Any thread. Dropped once the PC can't change the bitrate.
    void request(int kbps);

    // Any thread
    BitrateState::State state() const;
    int ownKbps() const;

    // What the PC runs the stream at, as far as known: the confirmed target, else the user's own
    int targetKbps() const;

    // What it will run at once the newest request the PC hasn't answered yet goes through, if one
    // waits; targetKbps() otherwise
    int latestKbps() const;

    // The event state() changed with, on the main thread
    static bool isStateEvent(const SDL_Event& event);

    struct Shared;

private:
    std::shared_ptr<Shared> m_Shared;
};
