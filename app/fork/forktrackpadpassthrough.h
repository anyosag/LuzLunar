#pragma once

#include <functional>

#include <QString>

#include "SDL_compat.h"

class StreamingPreferences;

// Trackpad passthrough: while the stream is in front, the fingers on the Mac trackpad go to Apollo
// as frames (luztouchpad.h) for a synthetic Windows touchpad, with palms and resting thumbs left
// out (forktrackpad.*, forkmultitouch.*). macOS's trackpad gestures wait meanwhile
// (mac/gesturesuppressor_mac.*). Two modes:
// - Mac trackpad: macOS's own pointer motion, clicks and scrolling (with momentum) go to Windows
//   as a mouse, so they feel as they do on the Mac, and the touchpad, gestures only, gets the
//   fingers of a 3- or 4-finger gesture or a pinch. Needs an Apollo that offers it
//   (luztouchpad::k_host_mac_trackpad_flag); with an older one it's the Windows touchpad.
// - Windows touchpad: the touchpad gets every finger and Windows makes its own pointer, taps,
//   scrolling and gestures, while the trackpad's own mouse events are held back.
//
// It runs when the stream's setting is one of them (the app's Stream Settings can override the
// global one), the host offers it, the stream has the mouse in relative mode, and the stream
// window is the key window of the active app. ForkStreamExtensions starts and stops it with the
// stream.
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

    // For SdlInputHandler: true to drop a mouse event Windows gets otherwise (the fingers, or
    // macOS's own event in Mac trackpad mode). False for anything while passthrough isn't running.
    bool muteMotion(const SDL_MouseMotionEvent* event);
    bool muteWheel(const SDL_MouseWheelEvent* event);
    bool muteButton(const SDL_MouseButtonEvent* event);
}
