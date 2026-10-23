#pragma once

#include <functional>
#include <memory>

#include <QString>
#include <QtGlobal>

#include "fork/notchmenus.h"
#include "fork/notchquality.h"
#include "fork/powerrules.h"

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

    // The same for a Low Power Mode message: a yellow dot before it, as on the canvas, and 6 seconds
    virtual bool showNotice(const QString& text) = 0;

    // What the menus show, asked whenever one opens or refreshes
    struct MenuState {
        bool mouseCaptured = true;      // input held by the stream; while a menu is open, whether it will be once it closes
        bool systemKeysToPc = false;    // Mac shortcuts (Command-Tab, ...) go to the PC
        bool canSleepPc = true;         // the PC's Apollo can sleep, and this Mac may ask it to

        // Clipboard sync with the PC (ClipboardSync::Availability), and whether it's automatic now
        enum class Clipboard { OffInSettings, Unknown, Available, NeedsApollo, NotAllowed };
        Clipboard clipboard = Clipboard::OffInSettings;
        bool clipboardAutomatic = false;

        // This Mac as a drive on the PC (MacDrive::mapping())
        bool driveMapped = false;
        QString driveLetter;
        bool driveHomeFolder = false;

        bool statsOverlayShown = false; // Moonlight's stats overlay, Control-Option-Shift-S
        bool notchStatsShown = true;    // the bar's stats text; the bar fills this in itself

        // The bitrate: what the PC can change, adaptive bitrate, the Quality slider's range
        NotchQuality::State bitrate;

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

    // An open menu and the Quality item show MenuState again, after an action changed it
    virtual void refreshMenus() = 0;

    // The bitrate, or what the PC can do with it, changed: the Quality item, and Quality or Control
    // Center if open, show it in place
    virtual void bitrateChanged() = 0;

    // The battery, Low Power Mode or Stream Battery Saver changed: the Battery item, and Battery if
    // open, show it
    virtual void powerChanged() = 0;

protected:
    NotchBar() = default;
};

#ifndef Q_OS_DARWIN
inline std::unique_ptr<NotchBar> NotchBar::create(SDL_Window*, const QString&, const QString&, int, int)
{
    return nullptr;
}
#endif
