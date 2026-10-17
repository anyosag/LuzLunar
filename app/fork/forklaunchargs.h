#pragma once

#include <QString>

class QWindow;

// The fork's additions to /launch and /resume: a description of the Mac screen the stream shows on
// (clientdisplay.*), for the host's virtual display. Apollo with anyosag/LuzVDA uses it; other hosts
// ignore arguments they don't know. Captured on the main thread before the stream starts, then
// taken on the thread that starts it, so every launch and resume describes the current screen.
namespace ForkLaunchArgs
{
    // Reads the screen qtWindow is on and logs what the host will be told. Does nothing when the
    // "Describe this Mac's screen" setting is off, or off macOS.
    void capture(QWindow* qtWindow);

    // The arguments from the last capture, once; empty for GeForce Experience, which predates them
    QString take(bool isNvidiaServerSoftware);
}
