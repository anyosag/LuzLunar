#pragma once

class NvComputer;

// [fork] Reconnecting a stream from the notch bar (Session::forkReconnect()). The stream ends without
// quitting its app on the PC, and StreamSegue starts the next one with what changed
// (StreamProfiles::createReconnectSession(), reconnectrules.h).
namespace ForkReconnect
{
    // On the new stream's connection thread, before it launches: waits until the PC's Apollo has let
    // the old stream go (GET /actions/bitrate answers 403, not streaming), at most 3 s. Apollo applies
    // a new resolution to its virtual display only while no stream is running. A PC that doesn't
    // answer it gets a second.
    void waitForHostToDrop(NvComputer* computer);
}
