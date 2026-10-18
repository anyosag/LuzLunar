#pragma once

#include <QtGlobal>

// Holds back macOS's own trackpad gestures while trackpad passthrough sends the fingers to
// Windows (forktrackpadpassthrough.*), so a three- or four-finger swipe can't switch Spaces or
// open Mission Control on the Mac. The rules are in forktrackpadgestures.*.
//
// - An event tap drops the Dock's gesture events (CGEventType 30) while armed: Spaces and
//   fullscreen swipes, Mission Control, App Exposé, the Show Desktop and Apps pinches. It needs
//   Privacy & Security › Accessibility, and goes away with the process.
// - The two gestures it can't catch, Notification Center's edge swipe and three-finger drag, are
//   switched off through System Settings' own code (MTTGestureBackEnd, private, looked up at run
//   time) and back on afterwards. A crash record puts them back the next time LuzLunar opens.
//   See scripts/fork/trackpad-probe.mm.
namespace ForkGestureSuppressor
{
#ifdef Q_OS_DARWIN
    // For a stream: starts the event tap (it holds nothing back until armed) and, with
    // pauseSettings, gets ready to switch the two settings off
    void start(bool pauseSettings);
    void stop();

    // Whether gestures are held back now; on the main thread
    void setArmed(bool armed);

    // Whether the event tap is running (it needs the Accessibility permission)
    bool tapRunning();

    bool accessibilityTrusted();

    // Asks macOS for the permission and opens its page in System Settings
    void requestAccessibility();
#else
    inline void start(bool) {}
    inline void stop() {}
    inline void setArmed(bool) {}
    inline bool tapRunning() { return false; }
    inline bool accessibilityTrusted() { return false; }
    inline void requestAccessibility() {}
#endif
}
