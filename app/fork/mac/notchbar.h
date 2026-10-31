#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <utility>

#include <QString>
#include <QtGlobal>

#include "fork/micrules.h"
#include "fork/notchmenus.h"
#include "fork/notchquality.h"
#include "fork/powerrules.h"
#include "fork/streamsettings.h"

struct SDL_Window;

// A bar beside the camera notch that shows the streamed app and live stream stats while the
// stream is fullscreen on a MacBook display with a notch. macOS draws a fullscreen app's window
// below the notch, so the bar is a separate non-activating panel over that strip.
//
// Messages appear beside the notch too, growing out of a blinking red dot: Moonlight's poor
// connection warning (through ForkStreamStats::reportConnectionStatus()) and clipboard messages
// (through showToast()). While the stream is windowed, they appear in a pill in the window's
// bottom-left corner instead. Otherwise they stay in Moonlight's status overlay.
//
// The bar's items open menus under it, like macOS's menu bar: the app's name opens the Session menu
// (disconnect, quit the app on the PC, sleep the PC), the stats open Stream status (latency, its
// last two minutes, the connection), the bitrate opens Quality (adaptive bitrate, a slider for the
// bitrate), the battery opens Battery (what the stream draws, Stream Battery Saver), and the Control
// Center icon opens Stream Control Center (clipboard sync, the pointer, Mac shortcuts). Their panels
// never take focus from the stream (notchmenus_mac.mm).
class NotchBar
{
public:
    // Null where there's no bar to show, e.g. on other platforms. width and height: the stream's
    // resolution, for Stream status.
    static std::unique_ptr<NotchBar> create(SDL_Window* window, const QString& appName, const QString& hostName,
                                            int width, int height);

    virtual ~NotchBar() = default;

    // Shows a message beside the notch, or in the corner of a windowed stream, for a few seconds.
    // Returns false, showing nothing, while neither is on screen. Call on the main thread.
    virtual bool showToast(const QString& text) = 0;

    // The same for a Low Power Mode message: a yellow dot before it, as on the canvas, and 6 seconds.
    // With an actionTitle, a button after it does the action, and it stays 10 seconds; the corner
    // pill of a windowed stream shows the message alone, as it takes no clicks.
    virtual bool showNotice(const QString& text, const QString& actionTitle, NotchMenus::Action action, int value) = 0;

    // What the menus show, asked whenever one opens or refreshes
    struct MenuState {
        bool mouseCaptured = true;      // input held by the stream; while a menu is open, whether it will be once it closes
        bool mouseAbsolute = false;     // the remote desktop's mouse: the Mac's own pointer, which reaches the bar
        bool pointerReachesBar = false; // Mac trackpad mode's pointer comes up into the bar past the top (ForkBarReach)
        bool systemKeysToPc = false;    // Mac shortcuts (Command-Tab, ...) go to the PC
        bool canSleepPc = true;         // the PC's Apollo can sleep, and this Mac may ask it to

        // Clipboard sync with the PC (ClipboardSync::Availability), and whether it's automatic now
        enum class Clipboard { OffInSettings, Unknown, Available, NeedsApollo, NotAllowed };
        Clipboard clipboard = Clipboard::OffInSettings;
        bool clipboardAutomatic = false;

        // This Mac's microphone on the PC (ForkMic::status()): Control Center's Microphone switch
        MicRules::Status mic = MicRules::Status::Off;

        // This Mac as a drive on the PC (MacDrive::mapping())
        bool driveMapped = false;
        QString driveLetter;
        bool driveHomeFolder = false;

        bool statsOverlayShown = false; // Moonlight's stats overlay, Control-Option-Shift-S
        bool notchStatsShown = true;    // the bar's stats text; the bar fills this in itself

        // The bitrate: what the PC can change, adaptive bitrate, the Quality slider's range
        NotchQuality::State bitrate;

        // The stream's frame rate and resolution, for Quality's reconnects
        int streamFps = 0;
        int streamWidth = 0;
        int streamHeight = 0;

        // The trackpad's mode now and the one the stream started in, as StreamingPreferences numbers
        // them (ReconnectRules::trackpadNeedsReconnect())
        int trackpadMode = 0;
        int trackpadStartedMode = 0;
        bool trackpadTouchpad = false;  // the PC's Apollo takes the trackpad as a touchpad
        bool trackpadMac = false;       // and in Mac trackpad mode

        // The Mac's battery (ForkPower) and Stream Battery Saver
        bool powerKnown = false;        // the stream reads the battery
        PowerRules::Reading power;
        bool lowPowerMode = false;
        int powerStartLevel = -1;       // the battery's level when the stream started
        double powerMinutes = 0;        // since then
        bool saverOn = false;
    };

    // actions: what the user chose in a menu, with a value for those that take one (SetBitrate's
    // kbps), on the main thread inside AppKit's event handling; hand it to the stream's event loop.
    // state: MenuState now. Call on the main thread.
    virtual void setActions(std::function<void(NotchMenus::Action, int value)> actions, std::function<MenuState()> state) = 0;

    // Control-Option-Shift-N: opens the Session menu for the keyboard, or closes the open menu. False
    // while the bar isn't on screen. Call on the main thread.
    virtual bool toggleMenus() = 0;

    // A key (SDL scancode) while a menu is open: true when the menu took it, so the PC shouldn't.
    // shift: Shift is held, for Shift-Tab.
    virtual bool handleMenuKey(int scancode, bool pressed, bool shift) = 0;

    virtual bool menuOpen() const = 0;

    // The bar is beside the notch now, where the pointer must be able to reach it
    virtual bool onScreen() const = 0;

    // Mac trackpad mode's pointer up into the bar and back (ForkBarReach), drawn on a panel over the
    // stream (notchreach_mac.mm). Points are in the stream window's points, from its top left.
    //
    // projectUp: the PC's pointer, at this point at the top of the picture, came up past it. The
    // Mac's pointer goes into the strip above it, and a ghost of it floats up there. The stream has
    // let the pointer go first.
    virtual void projectUp(double windowX, double windowY) = 0;
    // pullHome: the Mac's pointer, at this point, came back down into the picture. Its ghost is
    // sucked back into the PC's pointer, chasing it to wherever pcPoint says the stream has put it
    // (none: where it left), as the picture shows it lagMs later (the stream's latency); arriving
    // is called just before it gets there.
    virtual void pullHome(double windowX, double windowY, std::function<std::optional<std::pair<double, double>>()> pcPoint,
                          double lagMs, std::function<void()> arriving) = 0;
    // Pulses over the PC's pointer at this point, for a PC that can't pulse its own; size: its
    // arrow's height in points. settlePulse: they stop short, settling back.
    virtual void pulseAt(double windowX, double windowY, int pulses, double size) = 0;
    virtual void settlePulse() = 0;

    // macOS's Reduce Motion
    static bool reduceMotion();

    // An open menu and the Quality item show MenuState again, after an action changed it
    virtual void refreshMenus() = 0;

    // This Mac's microphone records for the PC: an orange dot beside the notch, as macOS's own
    // would be in the menu bar the stream hides
    virtual void setMicLive(bool live) = 0;

    // The bitrate, or what the PC can do with it, changed: the Quality item, and Quality or Control
    // Center if open, show it in place
    virtual void bitrateChanged() = 0;

    // The battery, Low Power Mode or Stream Battery Saver changed: the Battery item, and Battery if
    // open, show it
    virtual void powerChanged() = 0;

    // Stream Settings' panel (ForkStreamSettings): its contents, open starting the draft again from
    // what the stream applied, and the draft's edits. On the main thread inside AppKit's event
    // handling: they change the draft alone, so they needn't wait for the event loop.
    struct StreamSettingsSource {
        std::function<ForkStreamSettings::View(bool open)> view;
        std::function<void(int row, int choice)> pick;
        std::function<void(int preset)> preset;
        std::function<void()> reset;
    };
    virtual void setStreamSettings(StreamSettingsSource source) = 0;

protected:
    NotchBar() = default;
};

#ifndef Q_OS_DARWIN
inline std::unique_ptr<NotchBar> NotchBar::create(SDL_Window*, const QString&, const QString&, int, int)
{
    return nullptr;
}
#endif
