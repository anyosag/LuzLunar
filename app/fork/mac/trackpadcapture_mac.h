#pragma once

#include <QtGlobal>

#include <cstdint>
#include <functional>
#include <vector>

#include "SDL_compat.h"
#include "fork/forktrackpad.h"

// Reads the fingers on the trackpad in the stream window, for trackpad passthrough
// (forktrackpadpassthrough.*). AppKit reports them in its touch events, which SDL drops for
// trackpads (it only passes on touchscreens). macOS only.
namespace ForkTrackpadCapture
{
    // Gets every touch an event in the stream window carries, at timeMs on SDL's clock (ms).
    // Called on the main thread, from AppKit's event dispatch.
    using Handler = std::function<void(const std::vector<ForkTrackpad::Touch>& touches, std::uint32_t timeMs)>;

#ifdef Q_OS_DARWIN
    bool start(SDL_Window* window, Handler handler);
    void stop();

    // Whether LuzLunar is the active app and the stream window its key window
    bool streamWindowIsKey();
#else
    inline bool start(SDL_Window*, Handler) { return false; }
    inline void stop() {}
    inline bool streamWindowIsKey() { return false; }
#endif
}
