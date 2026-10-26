#pragma once

#include <memory>

#include "bitraterules.h"

class BitrateClient;

// [fork] Adaptive bitrate for one stream. ForkStreamExtensions owns it while it's on: from the
// stream's start while Settings' "Adapt bitrate to the network" is on, and whenever the notch bar's
// Quality menu turns it on during the stream.
//
// Once a second the decoder's stats (ForkStreamStats) go to BitrateRules' controller, on the decode
// thread. When the controller wants another bitrate, BitrateClient asks LuzLunar's Apollo for it.
// Once the PC turns out unable to change the bitrate (BitrateClient::state()), it stops asking.
class AdaptiveBitrate
{
public:
    // chosenKbps: the most it ever asks for, the stream's own bitrate or Stream Battery Saver's cap.
    // hdr raises the floor.
    // startKbps: the bitrate the stream runs at now, where it starts from (below chosenKbps after a
    // change by hand).
    AdaptiveBitrate(std::shared_ptr<BitrateClient> client, int chosenKbps, bool hdr, int startKbps);
    ~AdaptiveBitrate();

    AdaptiveBitrate(const AdaptiveBitrate&) = delete;
    AdaptiveBitrate& operator=(const AdaptiveBitrate&) = delete;

    // What it did last, for the notch bar's Quality menu. Any thread.
    struct State {
        int chosenKbps = 0;
        int currentKbps = 0;
        BitrateRules::Change lastChange;
        double changeAgoSeconds = 0;    // how long ago lastChange was
    };
    State state() const;

    struct Shared;

private:
    std::shared_ptr<Shared> m_Shared;
};
