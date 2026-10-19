#pragma once

#include <QString>

class QWindow;

// The fork's additions to /launch and /resume: a description of the Mac screen the stream shows on
// (clientdisplay.*), for the host's virtual display, and the trackpad's mode. Apollo with
// anyosag/LuzVDA uses them; other hosts ignore arguments they don't know. Captured on the main
// thread before the stream starts, then taken on the thread that starts it, so every launch and
// resume describes the current screen.
namespace ForkLaunchArgs
{
    // Reads the screen qtWindow is on and logs what the host will be told; the screen is left out
    // when the "Describe this Mac's screen" setting is off, or off macOS. macTrackpad asks for Mac
    // trackpad mode (luzTrackpad=mac, forktrackpadpassthrough.*): the host keeps its touchpad to
    // gestures and its pointer speed out of the way while the stream runs, if it can.
    void capture(QWindow* qtWindow, bool macTrackpad);

    // The arguments from the last capture, once; empty for GeForce Experience, which predates them
    QString take(bool isNvidiaServerSoftware);
}
