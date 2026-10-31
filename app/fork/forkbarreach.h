#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <utility>

#include "SDL_compat.h"
#include "barreach.h"

class NvComputer;

// [fork] Mac trackpad mode's pointer up into the notch bar (barreach.h has the rules): follows the
// PC's pointer by the moves the trackpad sends, and as a push up against the top begins, asks the PC
// where it is and to pulse it twice (POST /actions/cursor); when the PC says it's at the top, the
// Mac's pointer goes up into the bar as the second pulse ends. Coming back down, the PC pulses its
// pointer once. A PC that can't pulse its pointer (Windows Graphics Capture, or an Apollo before the
// pulse, which answers GET only) gets its pulses drawn over the picture instead.
//
// ForkStreamExtensions owns it for a stream with the bar, on a PC whose Apollo says where its
// pointer is (NvComputer::apolloCursor), and moves the pointers. Main thread; the questions run on a
// worker of their own, so a bitrate change waiting on the PC doesn't hold them up.
class ForkBarReach
{
public:
    struct Callbacks {
        // The Mac's pointer goes into the bar above this fraction of the picture's width
        std::function<void(double fraction)> handOver;
        // The PC can't pulse its pointer: pulse it over the picture, this many times
        std::function<void(int pulses)> pulseHere;
        // The push stopped short: those pulses settle back
        std::function<void()> settleHere;
        // macOS's Reduce Motion, asked as each push begins: the PC's pulses change color only
        std::function<bool()> reduceMotion;
    };

    ForkBarReach(NvComputer* computer, Callbacks callbacks);
    ~ForkBarReach();

    ForkBarReach(const ForkBarReach&) = delete;
    ForkBarReach& operator=(const ForkBarReach&) = delete;

    // A move Mac trackpad mode sent the PC, and the Mac's motion it came from
    // (ForkTrackpadPassthrough's listener)
    void moved(int dx, int dy, double dxPoints, double dyPoints);

    // Where the PC has its pointer now, in its pixels, while this Mac draws it (ForkCursor)
    void follow(int x, int y, int width, int height) { m_Tracker.follow(x, y, width, height); }

    // Coming back down: the PC pulses its pointer once. False when it can't, to pulse it over the
    // picture instead.
    bool pulseOnce();

    // Where the PC's pointer is, as fractions of the picture's width and height, while it's known
    std::optional<std::pair<double, double>> pointer() const;
    // The PC's display's height in pixels, 0 until known
    int displayHeight() const;

    // Its answers and ticks, arriving as SDL events; true when the event was one
    bool handleEvent(const SDL_Event& event);

    struct Shared;

private:
    void apply(const BarReach::Step& step);
    void send(int pulses, bool ifAtTop, bool answer);
    void updateTicks();

    std::shared_ptr<Shared> m_Shared;
    BarReach::Tracker m_Tracker;
    Callbacks m_Callbacks;
    SDL_TimerID m_TickTimer = 0;
};
