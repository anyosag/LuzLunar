#pragma once

#include <memory>
#include <optional>

#include <QString>

#include "SDL_compat.h"
#include "notchmenus.h"

class AdaptiveBitrate;
class ClipboardSync;
class MacDrive;
class NotchBar;
class PowerNotice;
class SdlInputHandler;
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

    // The bar is beside the notch, above the picture: Moonlight's pointer region lock stays off then,
    // so the pointer can reach it (SdlInputHandler::updatePointerRegionLock())
    bool barOnScreen() const;

private:
    // Does what a notch bar menu asked for, in the event loop
    void performBarAction(NotchMenus::Action action);

    // Whether the stream will hold input once the open menus close
    bool captureAfterMenus(SdlInputHandler* input) const;

    // Stream status's Copy Diagnostics
    void copyDiagnostics();

    QString m_AppName;
    int m_Width;
    int m_Height;
    int m_OwnBitrateKbps;
    QString m_HostName;
    QString m_HostUuid;
    // The menus free the pointer while they're open, from MenusOpened to MenusClosed. Control
    // Center's Mouse tile chooses whether the stream holds input after (m_CaptureAfterMenus);
    // m_CaptureLeftByBar is what the bar left it as, so a change by other means can be told apart.
    bool m_BarMenusOpen = false;
    bool m_CaptureAfterMenus = true;
    bool m_CaptureLeftByBar = false;
    // Held back while the stream isn't in front (MenusClosed)
    std::optional<bool> m_CaptureOnFocus;

    bool m_ShortcutGuard;
    std::unique_ptr<ClipboardSync> m_Clipboard;
    std::unique_ptr<NotchBar> m_NotchBar;
    std::unique_ptr<MacDrive> m_MacDrive;
    std::unique_ptr<PowerNotice> m_PowerNotice;
    std::unique_ptr<AdaptiveBitrate> m_AdaptiveBitrate;
};
