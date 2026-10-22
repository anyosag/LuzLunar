#include "forkstreamextensions.h"

#include <QReadLocker>

#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "clipboardsync.h"
#include "forknetworklink.h"
#include "forkpreferences.h"
#include "forksystemshortcuts.h"
#include "forktrackpadpassthrough.h"
#include "forkvideoscaling.h"
#include "hostpacing.h"
#include "mac/macintegration.h"
#include "mac/notchbar.h"
#include "macdrive.h"
#include "powernotice.h"
#include "settings/streamingpreferences.h"

namespace
{
    ForkStreamExtensions* s_Active = nullptr;
}

ForkStreamExtensions::ForkStreamExtensions(NvComputer* computer, const NvApp& app, SDL_Window* window,
                                           const StreamingPreferences& prefs)
    : m_ShortcutGuard(false)
{
    ForkPreferences* forkPrefs = ForkPreferences::get();

    // When Command sends something other than the Windows key, Command shortcuts are meant
    // for the host, so keep the app menu from quitting or hiding Moonlight on Cmd+Q / Cmd+H.
    if (forkPrefs->commandKeyTarget() != ForkPreferences::MT_WIN) {
        MacIntegration::setStreamShortcutGuard(true);
        m_ShortcutGuard = true;
    }

    if (forkPrefs->clipboardSyncMode() != ForkPreferences::CSM_OFF) {
        m_Clipboard = std::make_unique<ClipboardSync>(computer, forkPrefs->clipboardSyncMode() == ForkPreferences::CSM_AUTOMATIC);
    }

    if (forkPrefs->notchBar()) {
        QString hostName;
        {
            QReadLocker lock(&computer->lock);
            hostName = computer->name;
        }
        m_NotchBar = NotchBar::create(window, app.name + QString::fromUtf8(" · ") + hostName);
    }

    // This Mac as a drive on the PC, asked for once the link turns out to be the LAN
    if (forkPrefs->macDrive()) {
        m_MacDrive = std::make_unique<MacDrive>(computer);
        if (m_NotchBar) {
            // Its messages appear beside the notch too
            NotchBar* notchBar = m_NotchBar.get();
            m_MacDrive->setMessageSink([notchBar](const QString& text) {
                return notchBar->showToast(text);
            });
        }
    }

    // A stream above 60 fps while Low Power Mode holds the screen to 60: said beside the notch
    m_PowerNotice = std::make_unique<PowerNotice>(prefs.fps);
    if (m_NotchBar) {
        NotchBar* notchBar = m_NotchBar.get();
        m_PowerNotice->setMessageSink([notchBar](const QString& text) {
            return notchBar->showToast(text);
        });
    }

    // How evenly the PC sends this stream's frames, for the stats overlay and the log
    ForkHostPacing::reset();

    // Which connection the stream uses, for the notch bar; also remembers a network it goes over
    // the LAN on, so it's checked even without the bar
    ForkNetworkLink::start(m_NotchBar != nullptr, m_MacDrive ? m_MacDrive->linkListener() : std::function<void(bool)>());

    if (m_Clipboard && m_NotchBar) {
        // Clipboard messages appear beside the notch while the bar is on screen
        NotchBar* notchBar = m_NotchBar.get();
        m_Clipboard->setMessageSink([notchBar](const QString& text) {
            return notchBar->showToast(text);
        });
    }

    s_Active = this;

    // Renderers and the mouse mapping read this through StreamUtils::scaleSourceToDestinationSurface()
    ForkVideoScaling::activate(window, prefs.fullscreenStretch);

    // Which Mac shortcuts system key capture takes; SdlInputHandler asks it before grabbing
    ForkSystemShortcuts::activate(window);

    // The trackpad as a Windows touchpad, when the stream's setting is on; its messages appear
    // beside the notch too
    if (m_NotchBar) {
        NotchBar* notchBar = m_NotchBar.get();
        ForkTrackpadPassthrough::setMessageSink([notchBar](const QString& text) {
            return notchBar->showToast(text);
        });
    }
    ForkTrackpadPassthrough::activate(window, prefs);
}

ForkStreamExtensions::~ForkStreamExtensions()
{
    ForkNetworkLink::stop();
    ForkTrackpadPassthrough::deactivate();
    ForkTrackpadPassthrough::setMessageSink(nullptr);
    ForkSystemShortcuts::deactivate();
    ForkVideoScaling::deactivate();

    s_Active = nullptr;

    // The notch bar goes away before the clipboard sync
    if (m_Clipboard) {
        m_Clipboard->setMessageSink(nullptr);
    }
    if (m_MacDrive) {
        m_MacDrive->setMessageSink(nullptr);
    }
    m_PowerNotice->setMessageSink(nullptr);

    ForkHostPacing::logSummary();

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
    if (m_MacDrive) {
        m_MacDrive->handleEvent(event);
    }
    m_PowerNotice->handleEvent(event);

    ForkSystemShortcuts::handleEvent(event);
    ForkTrackpadPassthrough::handleEvent(event);
}
