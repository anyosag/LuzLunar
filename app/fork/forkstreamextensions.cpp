#include "forkstreamextensions.h"

#include "forkpreferences.h"
#include "mac/macintegration.h"

ForkStreamExtensions::ForkStreamExtensions(NvComputer*, const NvApp&)
    : m_ShortcutGuard(false)
{
    // When Command sends something other than the Windows key, Command shortcuts are meant
    // for the host, so keep the app menu from quitting or hiding Moonlight on Cmd+Q / Cmd+H.
    if (ForkPreferences::get()->commandKeyTarget() != ForkPreferences::MT_WIN) {
        MacIntegration::setStreamShortcutGuard(true);
        m_ShortcutGuard = true;
    }
}

ForkStreamExtensions::~ForkStreamExtensions()
{
    if (m_ShortcutGuard) {
        MacIntegration::setStreamShortcutGuard(false);
    }
}

void ForkStreamExtensions::handleEvent(const SDL_Event&)
{
}
