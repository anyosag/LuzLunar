#pragma once

#include <functional>

#include <QString>

#include "SDL_compat.h"

class StreamingPreferences;

// Trackpad passthrough: while the stream is in front, the fingers on the Mac trackpad go to Apollo
// as frames (luztouchpad.h) for a synthetic Windows touchpad, so Windows makes its own pointer,
// taps, scrolling and gestures. Meanwhile the trackpad's own mouse events are held back
// (forktrackpad.*) and macOS's trackpad gestures wait (mac/gesturesuppressor_mac.*).
//
// It runs when the stream's setting is on (the app's Stream Settings can override the global
// one), the host offers it, the stream has the mouse in relative mode, and the stream window is
// the key window of the active app. ForkStreamExtensions starts and stops it with the stream.
namespace ForkTrackpadPassthrough
{
    // prefs is the session's own copy, with the app's stream profile applied
    void activate(SDL_Window* window, const StreamingPreferences& prefs);
    void deactivate();
    void handleEvent(const SDL_Event& event);

    // Looks again at whether it should run, when the mouse capture changes
    // (SdlInputHandler::setCaptureActive)
    void update();

    // Where to show its messages (the notch bar); set before activate()
    void setMessageSink(std::function<bool(const QString&)> sink);

    // For SdlInputHandler: true to drop a mouse event the trackpad made, since Windows gets the
    // fingers instead. False for anything while passthrough isn't running.
    bool muteMotion(const SDL_MouseMotionEvent* event);
    bool muteWheel(const SDL_MouseWheelEvent* event);
    bool muteButton(const SDL_MouseButtonEvent* event);
}
