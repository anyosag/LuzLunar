#pragma once

#include <QtGlobal>

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
#else
    inline void setStreamShortcutGuard(bool) {}
    inline bool clipboardHasConcealedContent() { return false; }
#endif
}
