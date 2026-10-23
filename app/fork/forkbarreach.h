#pragma once

#include <functional>
#include <memory>

#include "SDL_compat.h"
#include "barreach.h"

class NvComputer;

// [fork] Mac trackpad mode's pointer up into the notch bar (barreach.h has the rules): follows the
// PC's pointer by the moves the trackpad sends, asks the PC where it is (GET /actions/cursor) once
// it's pushed up against the top, and hands over to the Mac's pointer when the PC says it's there.
// ForkStreamExtensions owns it for a stream with the bar, on a PC whose Apollo says where its
// pointer is (NvComputer::apolloCursor), and moves the pointers. Main thread; the question runs on
// a worker of its own, so a bitrate change waiting on the PC doesn't hold it up.
class ForkBarReach
{
public:
    // handOver: the Mac's pointer goes into the bar above this fraction of the picture's width, from
    // the stream's event loop
    ForkBarReach(NvComputer* computer, std::function<void(double fraction)> handOver);
    ~ForkBarReach();

    ForkBarReach(const ForkBarReach&) = delete;
    ForkBarReach& operator=(const ForkBarReach&) = delete;

    // A move Mac trackpad mode sent the PC, and the Mac's motion it came from
    // (ForkTrackpadPassthrough's listener)
    void moved(int dx, int dy, double dxPoints, double dyPoints);

    // The PC's pointer was put where the Mac's came back down into the picture, as fractions of it
    void placed(double fx, double fy);

    // The answer, arriving as an SDL event; true when the event was it
    bool handleEvent(const SDL_Event& event);

    struct Shared;

private:
    std::shared_ptr<Shared> m_Shared;
    BarReach::Tracker m_Tracker;
    std::function<void(double)> m_HandOver;
};
