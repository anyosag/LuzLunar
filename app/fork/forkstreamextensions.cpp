#include "forkstreamextensions.h"

#include <QCoreApplication>
#include <QReadLocker>

#include "adaptivebitrate.h"
#include "bitrateclient.h"
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
      m_Hdr(prefs.enableHdr),
      m_ShortcutGuard(false)
{
    ForkPreferences* forkPrefs = ForkPreferences::get();

    // A new stream's numbers, before anything (the notch bar's listener) starts publishing them
    ForkStreamStats::resetHistory();
    ForkHostPacing::reset();
    // The last stream may have ended on a poor connection, which moonlight-common-c doesn't take back
    ForkStreamStats::resetConnectionStatus();

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
            [](NotchMenus::Action action, int value) {
                SDL_Event event = {};
                event.type = barActionEventType();
                event.user.code = k_BarActionCode;
                event.user.data1 = reinterpret_cast<void*>(static_cast<intptr_t>(action));
                event.user.data2 = reinterpret_cast<void*>(static_cast<intptr_t>(value));
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
                state.bitrate = bitrateState();
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

    // The stream's bitrate changed on the PC while it runs: by adaptive bitrate, which lowers it while
    // the network struggles and gives the stream's own back when it recovers, and by the notch bar's
    // Quality menu
    if (forkPrefs->adaptiveBitrate() || m_NotchBar) {
        m_BitrateClient = std::make_shared<BitrateClient>(computer, bitrateKbps);
    }
    if (forkPrefs->adaptiveBitrate()) {
        m_AdaptiveBitrate = std::make_unique<AdaptiveBitrate>(m_BitrateClient, bitrateKbps, prefs.enableHdr, bitrateKbps);
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

NotchQuality::State ForkStreamExtensions::bitrateState() const
{
    NotchQuality::State state;
    state.ownKbps = m_OwnBitrateKbps;
    if (!m_BitrateClient) {
        state.known = true;
        state.live = false;
        state.why = NotchQuality::Why::Apollo;
        return state;
    }
    BitrateState::State client = m_BitrateClient->state();
    state.known = client.known;
    state.live = client.live;
    state.why = client.live ? NotchQuality::Why::None :
                client.why == BitrateState::Why::Encoder   ? NotchQuality::Why::Encoder :
                client.why == BitrateState::Why::NotApollo ? NotchQuality::Why::NotApollo : NotchQuality::Why::Apollo;
    state.targetKbps = client.targetKbps;
    state.minKbps = client.minKbps;
    state.maxKbps = client.maxKbps;
    state.adapting = m_AdaptiveBitrate != nullptr && client.live;
    if (state.adapting) {
        AdaptiveBitrate::State adaptive = m_AdaptiveBitrate->state();
        state.changeReason = adaptive.lastChange.reason;
        state.changeAgoSeconds = adaptive.changeAgoSeconds;
        state.changeRttMs = adaptive.lastChange.rttMs;
        state.changeBaseRttMs = adaptive.lastChange.baseRttMs;
        state.changeDropPercent = adaptive.lastChange.dropPercent;
        state.changePoor = adaptive.lastChange.poor;
    }
    return state;
}

void ForkStreamExtensions::performBarAction(NotchMenus::Action action, int value)
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
    case NotchMenus::Action::ToggleAdaptiveBitrate:
        if (m_AdaptiveBitrate) {
            // The bitrate stays where it got to
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: adaptive bitrate off, holding %d kbps",
                        m_BitrateClient->latestKbps());
            m_AdaptiveBitrate.reset();
        }
        else if (m_BitrateClient && m_BitrateClient->state().live) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: adaptive bitrate on");
            // From where the stream is going, a slider's request still on its way included
            m_AdaptiveBitrate = std::make_unique<AdaptiveBitrate>(m_BitrateClient, m_OwnBitrateKbps, m_Hdr, m_BitrateClient->latestKbps());
        }
        break;
    case NotchMenus::Action::SetBitrate:
        // By hand only while adaptive bitrate is off; the slider is greyed otherwise
        if (m_BitrateClient && !m_AdaptiveBitrate && value > 0) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: bitrate set to %d kbps", value);
            m_BitrateClient->request(value);
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
    {
        NotchQuality::State bitrate = bitrateState();
        QString target = QStringLiteral("target %1 of %2 Mb/s")
                             .arg(QString::fromStdString(NotchQuality::mbps(NotchQuality::shownKbps(bitrate))),
                                  QString::fromStdString(NotchQuality::mbps(bitrate.ownKbps)));
        if (!bitrate.live) {
            static const char* why[] = { "", "its encoder can't", "its Apollo can't", "it isn't Apollo" };
            context.bitrate = QStringLiteral("fixed, %1; the PC can't change it during the stream (%2)")
                                  .arg(target, QString::fromLatin1(why[static_cast<int>(bitrate.why)]));
        }
        else if (bitrate.adapting) {
            static const char* reasons[] = { "no change yet", "frames lost", "round trip", "climbing" };
            context.bitrate = QStringLiteral("adaptive, %1, last change %2 s ago (%3; round trip %4 ms, usually %5 ms, %6% of frames lost)")
                                  .arg(target)
                                  .arg(static_cast<int>(bitrate.changeAgoSeconds))
                                  .arg(QString::fromLatin1(reasons[static_cast<int>(bitrate.changeReason)]))
                                  .arg(bitrate.changeRttMs)
                                  .arg(bitrate.changeBaseRttMs)
                                  .arg(bitrate.changeDropPercent, 0, 'f', 1);
        }
        else {
            context.bitrate = QStringLiteral("fixed, %1%2").arg(target, bitrate.known ? QString() : QStringLiteral(", not known yet whether the PC can change it"));
        }
    }
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
        if (m_NotchBar) {
            m_NotchBar->showToast(QCoreApplication::translate("NotchBar", "Couldn't copy the diagnostics"));
        }
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
        performBarAction(static_cast<NotchMenus::Action>(reinterpret_cast<intptr_t>(event.user.data1)),
                         static_cast<int>(reinterpret_cast<intptr_t>(event.user.data2)));
        return;
    }
    if (BitrateClient::isStateEvent(event)) {
        // What the PC can do with the bitrate, or what it runs at, changed
        if (m_NotchBar) {
            m_NotchBar->bitrateChanged();
        }
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
