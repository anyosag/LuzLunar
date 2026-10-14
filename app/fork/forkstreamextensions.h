#pragma once

#include "SDL_compat.h"

class NvComputer;
class NvApp;

// Fork features that live for the length of one stream. Session::exec() creates one on
// the stack before its event loop and passes it every SDL event.
class ForkStreamExtensions
{
public:
    ForkStreamExtensions(NvComputer* computer, const NvApp& app);
    ~ForkStreamExtensions();

    ForkStreamExtensions(const ForkStreamExtensions&) = delete;
    ForkStreamExtensions& operator=(const ForkStreamExtensions&) = delete;

    // Observes events only; never consumes upstream's events
    void handleEvent(const SDL_Event& event);

private:
    bool m_ShortcutGuard;
};
