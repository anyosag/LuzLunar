#pragma once

#include <QString>
#include <QtGlobal>

#include <string>

class QWindow;

// AppKit integration used by the fork. No-ops on other platforms.
namespace MacIntegration
{
#ifdef Q_OS_DARWIN
    // While enabled, Command key shortcuts don't reach the app menu, so Cmd+Q / Cmd+H / Cmd+, go to
    // the host instead of quitting, hiding or opening settings. SDL has already read each key
    // event by the time AppKit dispatches it, so the host still receives the keys.
    void setStreamShortcutGuard(bool enabled);

    // True if the clipboard holds something marked as concealed or transient, like a password copied
    // from a password manager (nspasteboard.org conventions), which shouldn't be synced automatically.
    bool clipboardHasConcealedContent();

    // The window server's number for a window, as screencapture -l takes it. 0 if there's none yet.
    long windowNumber(QWindow* window);

    // macOS's system shortcuts ("symbolic hot keys", like Spotlight's Cmd+Space), through private
    // SkyLight calls looked up at run time, so a macOS without them doesn't stop LuzLunar launching.
    // See scripts/fork/hotkey-probe.mm.
    bool symbolicHotKeysAvailable();

    // Whether the hot key is on in System Settings, for every app
    bool isSymbolicHotKeyEnabled(int id);

    // forApp: only for this app's windows, and macOS drops it when the app exits. Otherwise for every
    // app until turned back on. False if macOS refused (some hot keys can't be set per app).
    bool setSymbolicHotKeyEnabled(int id, bool enabled, bool forApp);

    // macOS's name for a hot key, like "Spotlight", or empty
    std::string symbolicHotKeyName(int id);

    // True while macOS's screenshot tools are on screen (⇧⌘4's crosshair, ⇧⌘5's toolbar): the
    // screencapture process puts a window over the whole screen until it's done
    bool screenshotOverlayVisible();

    // True if pid is a running copy of this program, for crash records another copy left
    bool isRunningCopy(long pid);

    // The text on the app's Dock icon, like a transfer's progress; empty removes it. Main thread.
    void setDockBadge(const QString& text);
#else
    inline void setStreamShortcutGuard(bool) {}
    inline bool clipboardHasConcealedContent() { return false; }
    inline long windowNumber(QWindow*) { return 0; }
    inline bool symbolicHotKeysAvailable() { return false; }
    inline bool isSymbolicHotKeyEnabled(int) { return false; }
    inline bool setSymbolicHotKeyEnabled(int, bool, bool) { return false; }
    inline std::string symbolicHotKeyName(int) { return std::string(); }
    inline bool screenshotOverlayVisible() { return false; }
    inline bool isRunningCopy(long) { return false; }
    inline void setDockBadge(const QString&) {}
#endif
}
