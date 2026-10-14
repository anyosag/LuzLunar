#include "forkstreamextensions.h"

#include <QReadLocker>

#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "clipboardsync.h"
#include "forkpreferences.h"
#include "mac/macintegration.h"
#include "mac/notchbar.h"

namespace
{
    ForkStreamExtensions* s_Active = nullptr;
}

ForkStreamExtensions::ForkStreamExtensions(NvComputer* computer, const NvApp& app, SDL_Window* window)
    : m_ShortcutGuard(false)
{
    ForkPreferences* prefs = ForkPreferences::get();

    // When Command sends something other than the Windows key, Command shortcuts are meant
    // for the host, so keep the app menu from quitting or hiding Moonlight on Cmd+Q / Cmd+H.
    if (prefs->commandKeyTarget() != ForkPreferences::MT_WIN) {
        MacIntegration::setStreamShortcutGuard(true);
        m_ShortcutGuard = true;
    }

    if (prefs->clipboardSyncMode() != ForkPreferences::CSM_OFF) {
        m_Clipboard = std::make_unique<ClipboardSync>(computer, prefs->clipboardSyncMode() == ForkPreferences::CSM_AUTOMATIC);
    }

    if (prefs->notchBar()) {
        QString hostName;
        {
            QReadLocker lock(&computer->lock);
            hostName = computer->name;
        }
        m_NotchBar = NotchBar::create(window, app.name + QString::fromUtf8(" · ") + hostName);
    }

    if (m_Clipboard && m_NotchBar) {
        // Clipboard messages appear beside the notch while the bar is on screen
        NotchBar* notchBar = m_NotchBar.get();
        m_Clipboard->setMessageSink([notchBar](const QString& text) {
            return notchBar->showToast(text);
        });
    }

    s_Active = this;
}

ForkStreamExtensions::~ForkStreamExtensions()
{
    s_Active = nullptr;

    // The notch bar goes away before the clipboard sync
    if (m_Clipboard) {
        m_Clipboard->setMessageSink(nullptr);
    }

    if (m_ShortcutGuard) {
        MacIntegration::setStreamShortcutGuard(false);
    }
}

ForkStreamExtensions* ForkStreamExtensions::active()
{
    return s_Active;
}

void ForkStreamExtensions::handleEvent(const SDL_Event& event)
{
    if (m_Clipboard) {
        m_Clipboard->handleEvent(event);
    }
}
