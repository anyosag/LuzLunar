#pragma once

#include <QtGlobal>

#include <cstdint>
#include <functional>
#include <vector>

#include "SDL_compat.h"
#include "fork/forktrackpad.h"

// Reads the fingers on the trackpad in the stream window, for trackpad passthrough
// (forktrackpadpassthrough.*). AppKit reports them in its touch events, which SDL drops for
// trackpads (it only passes on touchscreens). Resting touches (a thumb or palm macOS flags) are
// asked for too, so a touch that starts or stops resting shows up as such rather than as an end
// and a new touch. macOS only.
namespace ForkTrackpadCapture
{
    // Gets every touch an event in the stream window carries, at timeMs on SDL's clock (ms).
    // Called on the main thread, from AppKit's event dispatch.
    using Handler = std::function<void(const std::vector<ForkTrackpad::Touch>& touches, std::uint32_t timeMs)>;

    // Mac trackpad mode: what macOS itself makes of the trackpad (and any mouse) in the stream
    // window, before SDL sees it. Each is optional.
    struct MacInput {
        // Pointer motion in points, after macOS's acceleration; x right, y down
        std::function<void(double dx, double dy, std::uint32_t timeMs)> pointer;

        // A scroll with precise (trackpad) deltas in points, momentum included, already in the
        // user's scrolling direction; dy > 0 scrolls up, dx > 0 right. True when it was sent,
        // so SDL doesn't get it too.
        std::function<bool(double dx, double dy, std::uint32_t timeMs)> scroll;

        // macOS started a pinch
        std::function<void(std::uint32_t timeMs)> pinchBegan;
    };

#ifdef Q_OS_DARWIN
    bool start(SDL_Window* window, Handler handler, MacInput mac = MacInput());
    void stop();

    // Whether LuzLunar is the active app and the stream window its key window
    bool streamWindowIsKey();
#else
    inline bool start(SDL_Window*, Handler, MacInput = MacInput()) { return false; }
    inline void stop() {}
    inline bool streamWindowIsKey() { return false; }
#endif
}
