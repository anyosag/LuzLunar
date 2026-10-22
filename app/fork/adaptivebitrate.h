#pragma once

#include <memory>

class NvComputer;

// [fork] Adaptive bitrate for one stream. ForkStreamExtensions owns it while Settings' "Adapt
// bitrate to the network" is on.
//
// Once a second the decoder's stats (ForkStreamStats) go to BitrateRules' controller, on the decode
// thread. When the controller wants another bitrate, a worker thread posts it to LuzLunar's Apollo
// (POST /actions/bitrate, serverinfo's LuzBitrate). The notch bar's stats then show the bitrate
// the stream is held to. A host that can't change it (404, 409, an older Apollo) ends it for the
// stream.
class AdaptiveBitrate
{
public:
    // chosenKbps: the stream's own bitrate, the most it ever asks for. hdr raises the floor.
    AdaptiveBitrate(NvComputer* computer, int chosenKbps, bool hdr);
    ~AdaptiveBitrate();

    AdaptiveBitrate(const AdaptiveBitrate&) = delete;
    AdaptiveBitrate& operator=(const AdaptiveBitrate&) = delete;

    struct Shared;

private:
    std::shared_ptr<Shared> m_Shared;
};
