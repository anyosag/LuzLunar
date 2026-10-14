#pragma once

#include <memory>

#include "SDL_compat.h"

class ClipboardSync;
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

    // The current stream's extensions, or null when not streaming
    static ForkStreamExtensions* active();

    // Observes events only; never consumes upstream's events
    void handleEvent(const SDL_Event& event);

    // Null when clipboard sync is off
    ClipboardSync* clipboard() { return m_Clipboard.get(); }

private:
    bool m_ShortcutGuard;
    std::unique_ptr<ClipboardSync> m_Clipboard;
};
