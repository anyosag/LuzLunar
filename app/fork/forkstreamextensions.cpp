#include "forkstreamextensions.h"

#include <QCoreApplication>
#include <QReadLocker>

#include "adaptivebitrate.h"
#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "clipboardsync.h"
#include "forkevents.h"
#include "forkhostpower.h"
#include "forknetworklink.h"
#include "forkpreferences.h"
#include "forksystemshortcuts.h"
#include "forktrackpadpassthrough.h"
#include "forkvideoscaling.h"
#include "hostpacing.h"
#include "mac/macintegration.h"
#include "mac/notchbar.h"
#include "macdrive.h"
#include "mac/pasteboard.h"
#include "powernotice.h"
#include "settings/streamingpreferences.h"
#include "streamdiagnostics.h"
#include "streamstats.h"
#include "streaming/input/input.h"
#include "streaming/session.h"

namespace
{
    ForkStreamExtensions* s_Active = nullptr;

    // The notch bar menus' actions reach the event loop as these; their own code, so they can't
    // pass for Moonlight's
    const Sint32 k_BarActionCode = 0x4e4241;

    Uint32 barActionEventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }

    void pushQuit()
    {
        SDL_Event event = {};
        event.type = SDL_QUIT;
        event.quit.timestamp = SDL_GetTicks();
        SDL_PushEvent(&event);
    }

    SdlInputHandler* inputHandler()
    {
        Session* session = Session::get();
        return session != nullptr ? session->forkInputHandler() : nullptr;
    }

    // For Stream Control Center's Clipboard Sync switch
    NotchBar::MenuState::Clipboard clipboardState(ClipboardSync::Availability availability)
    {
        using Clipboard = NotchBar::MenuState::Clipboard;
        switch (availability) {
        case ClipboardSync::Availability::Available:
            return Clipboard::Available;
        case ClipboardSync::Availability::NeedsApollo:
            return Clipboard::NeedsApollo;
        case ClipboardSync::Availability::NotAllowed:
            return Clipboard::NotAllowed;
        case ClipboardSync::Availability::Unknown:
            break;
        }
        return Clipboard::Unknown;
    }
}

ForkStreamExtensions::ForkStreamExtensions(NvComputer* computer, const NvApp& app, SDL_Window* window,
                                           const StreamingPreferences& prefs, int bitrateKbps)
    : m_AppName(app.name),
      m_Width(prefs.width),
      m_Height(prefs.height),
      m_OwnBitrateKbps(bitrateKbps),
      m_ShortcutGuard(false)
{
    ForkPreferences* forkPrefs = ForkPreferences::get();

    // A new stream's numbers, before anything (the notch bar's listener) starts publishing them
    ForkStreamStats::resetHistory();
    ForkHostPacing::reset();

    // When Command sends something other than the Windows key, Command shortcuts are meant
    // for the host, so keep the app menu from quitting or hiding Moonlight on Cmd+Q / Cmd+H.
    if (forkPrefs->commandKeyTarget() != ForkPreferences::MT_WIN) {
        MacIntegration::setStreamShortcutGuard(true);
        m_ShortcutGuard = true;
    }

    if (forkPrefs->clipboardSyncMode() != ForkPreferences::CSM_OFF) {
        m_Clipboard = std::make_unique<ClipboardSync>(computer, forkPrefs->clipboardSyncMode() == ForkPreferences::CSM_AUTOMATIC);
    }

    {
        QReadLocker lock(&computer->lock);
        m_HostUuid = computer->uuid;
        m_HostName = computer->name;
    }

    if (forkPrefs->notchBar()) {
        m_NotchBar = NotchBar::create(window, app.name, m_HostName, prefs.width, prefs.height);
    }

    if (m_NotchBar) {
        // Its menus' choices run in the event loop, between events
        barActionEventType();
        m_NotchBar->setActions(
            [](NotchMenus::Action action) {
                SDL_Event event = {};
                event.type = barActionEventType();
                event.user.code = k_BarActionCode;
                event.user.data1 = reinterpret_cast<void*>(static_cast<intptr_t>(action));
                SDL_PushEvent(&event);
            },
            [this]() {
                NotchBar::MenuState state;
                SdlInputHandler* input = inputHandler();
                if (input != nullptr) {
                    state.mouseCaptured = captureAfterMenus(input);
                    state.systemKeysToPc = input->isSystemKeyCaptureActive();
                }
                // Known once the PC's menu or the app's start asked; until then it's tried, and the
                // toast after the stream says how it went
                QVariantMap power = ForkHostPower::get()->status(m_HostUuid);
                if (power.value(QStringLiteral("known")).toBool()) {
                    state.canSleepPc = power.value(QStringLiteral("supported")).toBool() &&
                                       power.value(QStringLiteral("permitted")).toBool();
                }
                if (m_Clipboard) {
                    state.clipboard = clipboardState(m_Clipboard->availability());
                    state.clipboardAutomatic = m_Clipboard->automatic();
                }
                if (m_MacDrive) {
                    MacDrive::Mapping mapping = m_MacDrive->mapping();
                    state.driveMapped = mapping.mapped;
                    state.driveLetter = mapping.letter;
                    state.driveHomeFolder = mapping.homeFolder;
                }
                Session* session = Session::get();
                state.statsOverlayShown = session != nullptr && session->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug);
                return state;
            });
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

    // A lower bitrate while the network struggles, and the stream's own back when it recovers
    if (forkPrefs->adaptiveBitrate()) {
        m_AdaptiveBitrate = std::make_unique<AdaptiveBitrate>(computer, bitrateKbps, prefs.enableHdr);
    }

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

    // The notch bar goes away first: its menus ask about the clipboard sync and the Mac drive
    if (m_Clipboard) {
        m_Clipboard->setMessageSink(nullptr);
    }
    if (m_MacDrive) {
        m_MacDrive->setMessageSink(nullptr);
    }
    m_PowerNotice->setMessageSink(nullptr);
    m_NotchBar.reset();

    ForkHostPacing::logSummary();

    if (m_ShortcutGuard) {
        MacIntegration::setStreamShortcutGuard(false);
    }
}

ForkStreamExtensions* ForkStreamExtensions::active()
{
    return s_Active;
}

void ForkStreamExtensions::toggleBarMenus()
{
    if (m_NotchBar) {
        m_NotchBar->toggleMenus();
    }
}

bool ForkStreamExtensions::handleBarMenuKey(const SDL_KeyboardEvent* event)
{
    // Also once a menu has closed: the release of a key it took is its own too
    return m_NotchBar && m_NotchBar->handleMenuKey(event->keysym.scancode, event->state == SDL_PRESSED,
                                                   (event->keysym.mod & KMOD_SHIFT) != 0);
}

bool ForkStreamExtensions::barMenuOpen() const
{
    return m_NotchBar && m_NotchBar->menuOpen();
}

bool ForkStreamExtensions::barOnScreen() const
{
    return m_NotchBar && m_NotchBar->onScreen();
}

bool ForkStreamExtensions::captureAfterMenus(SdlInputHandler* input) const
{
    // Before the menus' opening is handled, nothing has freed the pointer yet; and Control-Option-
    // Shift-Z pressed while a menu is open wins over what the bar would put back
    if (!m_BarMenusOpen || input->isCaptureActive() != m_CaptureLeftByBar) {
        return input->isCaptureActive();
    }
    return m_CaptureAfterMenus;
}

void ForkStreamExtensions::performBarAction(NotchMenus::Action action)
{
    Session* session = Session::get();
    SdlInputHandler* input = inputHandler();
    if (session == nullptr || input == nullptr) {
        return;
    }

    switch (action) {
    case NotchMenus::Action::Disconnect:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: disconnect");
        pushQuit();
        break;
    case NotchMenus::Action::DisconnectAndQuitLuzLunar:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: disconnect and quit LuzLunar");
        // Without asking the PC to quit the app, unlike Control-Option-Shift-E
        session->setShouldExit(false);
        pushQuit();
        break;
    case NotchMenus::Action::QuitAppOnPc:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: quit the app on the PC");
        session->forkQuitHostAppOnEnd();
        pushQuit();
        break;
    case NotchMenus::Action::QuitAndSleepPc:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: quit the app and sleep the PC");
        // Apollo quits the app itself before it sleeps, and only once the stream is gone
        session->forkSleepHostOnEnd();
        pushQuit();
        break;
    case NotchMenus::Action::ToggleMouseCapture:
        if (m_BarMenusOpen) {
            // The menus hold the pointer free while they're open: this chooses what happens after
            m_CaptureAfterMenus = !captureAfterMenus(input);
            m_CaptureLeftByBar = input->isCaptureActive();
        }
        else {
            input->forkToggleCapture();
        }
        break;
    case NotchMenus::Action::ToggleSystemKeys:
        input->forkToggleSystemKeys();
        break;
    case NotchMenus::Action::MenusOpened:
        // The pointer has to reach the menus: out of a game's hold, and out of the picture
        m_BarMenusOpen = true;
        m_CaptureOnFocus.reset();
        m_CaptureAfterMenus = input->isCaptureActive();
        if (input->isCaptureActive() && SDL_GetRelativeMouseMode()) {
            input->setCaptureActive(false);
            input->raiseAllKeys();
        }
        else if (input->isCaptureActive()) {
            input->forkSuspendRegionLock();
        }
        m_CaptureLeftByBar = input->isCaptureActive();
        break;
    case NotchMenus::Action::MenusClosed: {
        bool capture = captureAfterMenus(input);
        m_BarMenusOpen = false;
        if (capture == input->isCaptureActive()) {
            break;
        }
        if (SDL_GetKeyboardFocus() != nullptr) {
            input->setCaptureActive(capture);
            input->raiseAllKeys();
        }
        else {
            // They closed as another app came forward. SDL turns macOS's relative mouse mode on
            // at once, focus or not, which would hold the pointer in that app too: wait for the
            // stream to be in front again.
            m_CaptureOnFocus = capture;
        }
        break;
    }
    case NotchMenus::Action::BarShownOrHidden:
        // Moonlight holds the pointer to the picture in fullscreen on one display; not while the bar is
        // above the picture, where the pointer has to reach it
        input->updatePointerRegionLock();
        break;
    case NotchMenus::Action::ToggleStatsOverlay: {
        // As Control-Option-Shift-S does (SdlInputHandler::performSpecialKeyCombo())
        Overlay::OverlayManager& overlays = session->getOverlayManager();
        overlays.setOverlayState(Overlay::OverlayDebug, !overlays.isOverlayEnabled(Overlay::OverlayDebug));
        break;
    }
    case NotchMenus::Action::CopyDiagnostics:
        copyDiagnostics();
        break;
    case NotchMenus::Action::ToggleClipboardSync:
        if (m_Clipboard) {
            m_Clipboard->setAutomatic(!m_Clipboard->automatic());
        }
        break;
    case NotchMenus::Action::ToggleNotchStats:
        // The bar's own
    case NotchMenus::Action::None:
        break;
    }

    if (m_NotchBar) {
        m_NotchBar->refreshMenus();
    }
}

void ForkStreamExtensions::copyDiagnostics()
{
    ForkStreamDiagnostics::Context context;
    context.appName = m_AppName;
    context.hostName = m_HostName;
    context.width = m_Width;
    context.height = m_Height;
    context.ownBitrateKbps = m_OwnBitrateKbps;
    if (!m_Clipboard) {
        context.clipboard = QStringLiteral("off in Settings");
    }
    else {
        static const char* availability[] = { "permissions not known yet", "allowed", "the PC isn't Apollo", "not allowed in Apollo" };
        context.clipboard = QStringLiteral("%1, %2").arg(m_Clipboard->automatic() ? QStringLiteral("automatic") : QStringLiteral("by shortcut"),
                                                         QString::fromLatin1(availability[static_cast<int>(m_Clipboard->availability())]));
    }
    if (m_MacDrive && m_MacDrive->mapping().mapped) {
        MacDrive::Mapping mapping = m_MacDrive->mapping();
        context.drive = QStringLiteral("%1: (%2)").arg(mapping.letter, mapping.homeFolder ? QStringLiteral("the home folder") : QStringLiteral("the whole disk"));
    }

    QByteArray text = ForkStreamDiagnostics::text(context).toUtf8();
    // Plain text, not concealed: it's meant to be pasted, on the Mac or the PC
    long count = MacPasteboard::write({ clipbundle::item { "text/plain", std::string(text.constData(), static_cast<size_t>(text.size())) } }, false);
    if (count == 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: couldn't copy the diagnostics");
        return;
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: diagnostics copied");
    if (m_Clipboard) {
        // Automatic sync sends it now, so fetching on focus loss can't replace it with the PC's
        m_Clipboard->localClipboardChanged();
    }
    if (m_NotchBar) {
        m_NotchBar->showToast(QCoreApplication::translate("NotchBar", "Diagnostics copied"));
    }
}

void ForkStreamExtensions::handleEvent(const SDL_Event& event)
{
    if (event.type == barActionEventType() && event.user.code == k_BarActionCode) {
        performBarAction(static_cast<NotchMenus::Action>(reinterpret_cast<intptr_t>(event.user.data1)));
        return;
    }
    if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED && m_CaptureOnFocus) {
        SdlInputHandler* input = inputHandler();
        if (input != nullptr && *m_CaptureOnFocus != input->isCaptureActive()) {
            input->setCaptureActive(*m_CaptureOnFocus);
        }
        m_CaptureOnFocus.reset();
    }

    if (m_Clipboard) {
        m_Clipboard->handleEvent(event);
    }
    if (m_MacDrive && m_MacDrive->handleEvent(event) && m_NotchBar) {
        // The drive tile appears in an open Control Center
        m_NotchBar->refreshMenus();
    }
    m_PowerNotice->handleEvent(event);

    ForkSystemShortcuts::handleEvent(event);
    ForkTrackpadPassthrough::handleEvent(event);
}
