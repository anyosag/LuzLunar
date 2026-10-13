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

    s_Active = this;
}

ForkStreamExtensions::~ForkStreamExtensions()
{
    s_Active = nullptr;

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
