#pragma once

#include <memory>
#include <optional>

#include <QString>

#include "SDL_compat.h"
#include "notchmenus.h"
#include "notchquality.h"
#include "powernotice.h"
#include "powerrules.h"
#include "reconnectrules.h"

class AdaptiveBitrate;
class BitrateClient;
class ClipboardSync;
class ForkPower;
class MacDrive;
class NotchBar;
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
    // bitrate the stream was started with; choices, what the notch bar chose for the stream before a
    // reconnect
    ForkStreamExtensions(NvComputer* computer, const NvApp& app, SDL_Window* window,
                         const StreamingPreferences& prefs, int bitrateKbps, const ReconnectRules::Choices& choices);
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
    void performBarAction(NotchMenus::Action action, int value);

    // The Quality item and menu's state
    NotchQuality::State bitrateState() const;

    // Stream Battery Saver's cap while it holds the stream down (on, with the user's bitrate above
    // it); 0 otherwise
    int saverCapKbps() const;

    // The most adaptive bitrate asks for: the user's own, or the saver's cap
    int adaptiveCeiling() const;

    // Puts Stream Battery Saver's cap into effect, or takes it away: adaptive bitrate starts again
    // under the new ceiling, or the bitrate set by hand is asked for under it. Waits for the PC to have
    // said what it can do (BitrateState::State::settled).
    void applySaver();

    // The Low Power Mode message beside the notch now (PowerRules::pill()), with "Reconnect at 60 fps"
    // above 60 fps; empty text for none, nullopt while the PC hasn't said yet whether the saver can
    // cap the bitrate
    std::optional<PowerNotice::Notice> powerNotice() const;

    // Whether the stream will hold input once the open menus close
    bool captureAfterMenus(SdlInputHandler* input) const;

    // Stream status's Copy Diagnostics
    void copyDiagnostics();

    // Ends the stream to start it again with these changes, keeping what the bar chose for it
    void reconnect(const ReconnectRules::Overrides& overrides, const char* why);

    // Control Center's Trackpad: switches the mode in place when Apollo's side allows, or reconnects
    void setTrackpadMode(int mode);

    QString m_AppName;
    int m_Width;
    int m_Height;
    int m_OwnBitrateKbps;
    bool m_Hdr;
    int m_Fps;
    SDL_Window* m_Window;
    int m_TrackpadMode;             // as StreamingPreferences::TrackpadMode
    int m_TrackpadStartedMode;      // Apollo set its side up for this one (ReconnectRules::trackpadNeedsReconnect())
    bool m_AbsoluteBeforeTouchpad;  // the remote desktop's mouse a touchpad mode took away, for Mac mouse to give back
    bool m_TouchpadSupported;       // the PC's Apollo takes the trackpad as a touchpad (luztouchpad.h)
    bool m_MacTrackpadSupported;    // and in Mac trackpad mode
    int m_ManualKbps = 0;           // the bitrate set by hand last, which the saver gives back; 0 for the user's own
    int m_AppliedCeiling = 0;       // the ceiling applySaver() put into effect last
    bool m_SaverPending = false;    // applySaver() waits for the PC's answers
    bool m_ManualPending = false;   // and asks for m_ManualKbps, kept across a reconnect
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
    // The battery and Stream Battery Saver, with the bar only
    std::unique_ptr<ForkPower> m_Power;
    std::unique_ptr<PowerRules::Saver> m_Saver;
    // Shared with adaptive bitrate, which goes first
    std::shared_ptr<BitrateClient> m_BitrateClient;
    std::unique_ptr<AdaptiveBitrate> m_AdaptiveBitrate;
};
