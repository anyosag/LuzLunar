#pragma once

#include <memory>

#include <QString>

#include "SDL_compat.h"
#include "notchmenus.h"

class AdaptiveBitrate;
class ClipboardSync;
class MacDrive;
class NotchBar;
class PowerNotice;
class NvComputer;
class NvApp;
class StreamingPreferences;

// Fork features that live for the length of one stream. Session::exec() creates one on
// the stack before its event loop and passes it every SDL event.
class ForkStreamExtensions
{
public:
    // prefs is the session's own copy, with the app's stream profile applied; bitrateKbps is the
    // bitrate the stream was started with
    ForkStreamExtensions(NvComputer* computer, const NvApp& app, SDL_Window* window,
                         const StreamingPreferences& prefs, int bitrateKbps);
    ~ForkStreamExtensions();

    ForkStreamExtensions(const ForkStreamExtensions&) = delete;
    ForkStreamExtensions& operator=(const ForkStreamExtensions&) = delete;

    // The current stream's extensions, or null when not streaming
    static ForkStreamExtensions* active();

    // Observes events only; never consumes upstream's events
    void handleEvent(const SDL_Event& event);

    // Null when clipboard sync is off
    ClipboardSync* clipboard() { return m_Clipboard.get(); }

    // The notch bar's menus: Control-Option-Shift-N opens or closes them; while one is open, the keys
    // that move through it are its own. Main thread.
    void toggleBarMenus();
    bool handleBarMenuKey(const SDL_KeyboardEvent* event);
    bool barMenuOpen() const;

private:
    // Does what a notch bar menu asked for, in the event loop
    void performBarAction(NotchMenus::Action action);

    QString m_HostUuid;
    // Whether the stream holds input once the open menus close: the menus free the pointer while
    // they're open, and Control Center's Mouse tile chooses what happens after
    bool m_CaptureAfterMenus = true;

    bool m_ShortcutGuard;
    std::unique_ptr<ClipboardSync> m_Clipboard;
    std::unique_ptr<NotchBar> m_NotchBar;
    std::unique_ptr<MacDrive> m_MacDrive;
    std::unique_ptr<PowerNotice> m_PowerNotice;
    std::unique_ptr<AdaptiveBitrate> m_AdaptiveBitrate;
};
