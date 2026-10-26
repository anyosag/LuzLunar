#pragma once

#include <QString>

#include <functional>
#include <memory>

#include "forkmultidisplay.h"
#include "SDL_compat.h"

// Brings up the other slots of a multi-display stream once slot 0, this process's stream, is
// connected (forkmultidisplay.*), and takes them down when it ends. One slot at a time, since
// Apollo has one pending launch: each Mac display gets a helper process (forkhelper.*), and
// DisplayExtend's display goes last, straight from the PC or through this Mac as ForkDisplayRoute
// decides. A helper that drops is started again once, and a direct stream that stops falls back to
// a helper. Created by ForkStreamExtensions; the work runs on a thread of its own, since the
// stream holds the main thread.
class ForkDisplayCoordinator
{
public:
    // window is slot 0's stream window
    ForkDisplayCoordinator(std::shared_ptr<const ForkMultiDisplay::Group> group, SDL_Window* window);

    // Tells the helpers to end and hands the iMac back to DisplayExtend. Doesn't wait: the thread
    // finishes that on its own (and helpers end with their stdin anyway if this process goes).
    ~ForkDisplayCoordinator();

    ForkDisplayCoordinator(const ForkDisplayCoordinator&) = delete;
    ForkDisplayCoordinator& operator=(const ForkDisplayCoordinator&) = delete;

    // Main thread: keeps the keyboard on slot 0's window and passes messages on
    void handleEvent(const SDL_Event& event);

    // Where messages for the user go (the notch bar), on the main thread; returns whether shown
    void setMessageSink(std::function<bool(const QString&)> sink);

    struct State;

private:
    std::shared_ptr<State> m_State;
    SDL_Window* m_Window;
    std::function<bool(const QString&)> m_MessageSink;
};
