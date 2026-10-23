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
#include "forkpower.h"
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
                                           const StreamingPreferences& prefs, int bitrateKbps,
                                           const ReconnectRules::Choices& choices)
    : m_AppName(app.name),
      m_Width(prefs.width),
      m_Height(prefs.height),
      m_OwnBitrateKbps(bitrateKbps),
      m_Hdr(prefs.enableHdr),
      m_Fps(prefs.fps),
      m_Window(window),
      m_TrackpadMode(prefs.trackpadMode),
      m_TrackpadStartedMode(prefs.trackpadMode),
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
                state.streamFps = m_Fps;
                state.streamWidth = m_Width;
                state.streamHeight = m_Height;
                state.trackpadMode = m_TrackpadMode;
                state.trackpadStartedMode = m_TrackpadStartedMode;
                if (m_Power) {
                    state.powerKnown = true;
                    state.power = m_Power->reading();
                    state.lowPowerMode = m_Power->lowPowerMode();
                    state.powerStartLevel = m_Power->startLevel();
                    state.powerMinutes = m_Power->minutesSinceStart();
                    state.saverOn = m_Saver && m_Saver->on();
                }
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

    // Low Power Mode holds the screen to about 60 fps
    if (prefs.fps > 60 && MacIntegration::lowPowerModeEnabled()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Low Power Mode is on: macOS shows about 60 fps of this %d fps stream", prefs.fps);
    }

    // The battery for the bar's Battery menu, and Stream Battery Saver, which follows Low Power Mode
    // and caps the bitrate (PowerRules::Saver)
    m_PowerNotice = std::make_unique<PowerNotice>();
    if (m_NotchBar) {
        m_Power = std::make_unique<ForkPower>();
        m_Saver = std::make_unique<PowerRules::Saver>(m_Power->lowPowerMode());
        m_Saver->restore(choices.saver, choices.lowPowerMode);
        // The bar asked before there was a battery to read: the item comes now
        m_NotchBar->powerChanged();
        NotchBar* notchBar = m_NotchBar.get();
        m_PowerNotice->setMessageSink([notchBar](const PowerNotice::Notice& notice) {
            return notchBar->showNotice(notice.text, notice.actionTitle, NotchMenus::Action::ReconnectAtFps, notice.reconnectFps);
        });
    }

    // The stream's bitrate changed on the PC while it runs: by adaptive bitrate, which lowers it while
    // the network struggles and gives the stream's own back when it recovers, by the notch bar's
    // Quality menu, and by Stream Battery Saver
    // Settings say whether it adapts, unless Quality's switch said otherwise before a reconnect
    bool adaptive = choices.adaptive.value_or(forkPrefs->adaptiveBitrate());
    if (adaptive || m_NotchBar) {
        m_BitrateClient = std::make_shared<BitrateClient>(computer, bitrateKbps);
    }
    m_AppliedCeiling = bitrateKbps;
    if (adaptive) {
        m_AdaptiveBitrate = std::make_unique<AdaptiveBitrate>(m_BitrateClient, bitrateKbps, prefs.enableHdr, bitrateKbps);
    }
    else if (choices.manualKbps > 0 && m_BitrateClient) {
        // The bitrate set by hand before a reconnect, asked for once the PC says it can change it
        m_ManualKbps = choices.manualKbps;
        m_ManualPending = true;
    }
    // The saver's cap from the start, once the PC has said what it can do
    applySaver();
    if (m_Saver && m_Saver->lowPowerMode()) {
        m_PowerNotice->offer([this] { return powerNotice(); });
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

int ForkStreamExtensions::saverCapKbps() const
{
    return m_Saver && m_Saver->on() && m_OwnBitrateKbps > PowerRules::k_SaverKbps ? PowerRules::k_SaverKbps : 0;
}

int ForkStreamExtensions::adaptiveCeiling() const
{
    int cap = saverCapKbps();
    return cap > 0 ? cap : m_OwnBitrateKbps;
}

void ForkStreamExtensions::applySaver()
{
    if (!m_BitrateClient) {
        return;
    }
    BitrateState::State client = m_BitrateClient->state();
    if (!client.settled) {
        // Asked before the PC has said whether its encoder can change: the first request would skip
        // the wait for it (BitrateClient). Again once it has.
        m_SaverPending = true;
        return;
    }
    m_SaverPending = false;
    if (m_ManualPending) {
        m_ManualPending = false;
        if (client.live && !m_AdaptiveBitrate) {
            m_AppliedCeiling = adaptiveCeiling();
            int cap = saverCapKbps();
            m_BitrateClient->request(cap > 0 ? std::min(m_ManualKbps, cap) : m_ManualKbps);
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnected: the bitrate set by hand, %d kbps, again", m_ManualKbps);
            return;
        }
    }
    int ceiling = adaptiveCeiling();
    if (!client.live || ceiling == m_AppliedCeiling) {
        // Nothing to cap live (Quality says a reconnect would), or nothing changed
        return;
    }
    m_AppliedCeiling = ceiling;
    if (m_AdaptiveBitrate) {
        // From where the stream is going: above the ceiling, it's asked down to it at once
        int start = m_BitrateClient->latestKbps();
        m_AdaptiveBitrate.reset();
        m_AdaptiveBitrate = std::make_unique<AdaptiveBitrate>(m_BitrateClient, ceiling, m_Hdr, start);
    }
    else {
        int wanted = m_ManualKbps > 0 ? m_ManualKbps : m_OwnBitrateKbps;
        int cap = saverCapKbps();
        m_BitrateClient->request(cap > 0 ? std::min(wanted, cap) : wanted);
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Stream Battery Saver %s: adaptive bitrate goes up to %d kbps",
                saverCapKbps() > 0 ? "caps the bitrate" : "doesn't cap the bitrate", ceiling);
}

std::optional<PowerNotice::Notice> ForkStreamExtensions::powerNotice() const
{
    PowerNotice::Notice notice;
    if (!m_Saver) {
        return notice;
    }
    if (m_BitrateClient && !m_BitrateClient->state().settled) {
        // Whether the saver can cap it isn't known yet
        return std::nullopt;
    }
    bool capped = saverCapKbps() > 0 && m_BitrateClient && m_BitrateClient->state().live;
    switch (PowerRules::pill(m_Saver->lowPowerMode(), capped, m_Fps)) {
    case PowerRules::Pill::Capped:
        notice.text = QCoreApplication::translate("NotchBar", "Low Power Mode: bitrate capped at %1 Mb/s.")
                          .arg(QString::fromStdString(NotchQuality::mbps(PowerRules::k_SaverKbps)));
        break;
    case PowerRules::Pill::HoldsTo60:
        notice.text = QCoreApplication::translate("NotchBar", "Low Power Mode holds the screen to 60 fps.");
        break;
    case PowerRules::Pill::Hidden:
        break;
    }
    if (!notice.text.isEmpty() && m_Fps > 60) {
        // The screen shows 60 anyway: a stream at 60 spends less on the PC, the network and the Mac
        notice.actionTitle = QCoreApplication::translate("NotchBar", "Reconnect at 60 fps");
        notice.reconnectFps = 60;
    }
    return notice;
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
    state.saver = m_Saver && m_Saver->on();
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
            {
                // Held where it got to; at the saver's cap, that's the saver's, not a choice to keep
                int latest = m_BitrateClient->latestKbps();
                int cap = saverCapKbps();
                m_ManualKbps = cap > 0 && latest >= cap ? 0 : latest;
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: adaptive bitrate off, holding %d kbps", latest);
            }
            m_AdaptiveBitrate.reset();
        }
        else if (m_BitrateClient && m_BitrateClient->state().live) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: adaptive bitrate on");
            // From where the stream is going, a slider's request still on its way included
            m_AppliedCeiling = adaptiveCeiling();
            m_AdaptiveBitrate = std::make_unique<AdaptiveBitrate>(m_BitrateClient, m_AppliedCeiling, m_Hdr, m_BitrateClient->latestKbps());
        }
        break;
    case NotchMenus::Action::SetBitrate:
        // By hand only while adaptive bitrate is off; the slider is greyed otherwise
        if (m_BitrateClient && !m_AdaptiveBitrate && value > 0) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: bitrate set to %d kbps", value);
            m_ManualKbps = value;
            {
                // Up to the launch bitrate (Apollo's max); only the saver caps it lower
                int cap = saverCapKbps();
                m_BitrateClient->request(cap > 0 ? std::min(value, cap) : value);
            }
        }
        break;
    case NotchMenus::Action::ToggleBatterySaver:
        if (m_Saver) {
            m_Saver->toggle();
            applySaver();
            if (m_NotchBar) {
                m_NotchBar->powerChanged();
            }
        }
        break;
    case NotchMenus::Action::Reconnect:
    case NotchMenus::Action::ReconnectAtFps:
    case NotchMenus::Action::ReconnectAtResolution:
    case NotchMenus::Action::ReconnectAtBitrate: {
        // The stream ends, its app running on, and StreamSegue starts it again with what changed
        ReconnectRules::Overrides overrides;
        if (action == NotchMenus::Action::ReconnectAtFps) {
            overrides.fps = value;
        }
        else if (action == NotchMenus::Action::ReconnectAtResolution) {
            ReconnectRules::Size size = ReconnectRules::unpackSize(value);
            overrides.width = size.width;
            overrides.height = size.height;
        }
        else if (action == NotchMenus::Action::ReconnectAtBitrate) {
            overrides.bitrateKbps = value;
        }
        reconnect(overrides, action == NotchMenus::Action::Reconnect ? "" : " with a change");
        break;
    }
    case NotchMenus::Action::SetTrackpadMode:
        setTrackpadMode(value);
        break;
    case NotchMenus::Action::OpenBatterySettings:
        // The bar's own
    case NotchMenus::Action::ToggleNotchStats:
        // The bar's own
    case NotchMenus::Action::None:
        break;
    }

    if (m_NotchBar) {
        m_NotchBar->refreshMenus();
    }
}

void ForkStreamExtensions::reconnect(const ReconnectRules::Overrides& overrides, const char* why)
{
    Session* session = Session::get();
    if (session == nullptr) {
        return;
    }
    // What the bar chose for this stream holds for the next: adaptive bitrate on or off, the bitrate
    // set by hand, Stream Battery Saver switched by hand
    ReconnectRules::Choices choices;
    if (m_BitrateClient) {
        choices.adaptive = m_AdaptiveBitrate != nullptr;
        choices.manualKbps = m_AdaptiveBitrate ? 0 : m_ManualKbps;
    }
    if (m_Saver) {
        choices.saver = m_Saver->manual();
        choices.lowPowerMode = m_Saver->lowPowerMode();
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: reconnect%s", why);
    session->forkReconnect(overrides, choices);
    pushQuit();
}

void ForkStreamExtensions::setTrackpadMode(int mode)
{
    Session* session = Session::get();
    SdlInputHandler* input = inputHandler();
    if (session == nullptr || input == nullptr || mode == m_TrackpadMode || mode < ReconnectRules::k_TrackpadMacMouse ||
        mode > ReconnectRules::k_TrackpadMacTrackpad) {
        return;
    }
    if (ReconnectRules::trackpadNeedsReconnect(m_TrackpadStartedMode, mode)) {
        ReconnectRules::Overrides overrides;
        overrides.trackpadMode = mode;
        reconnect(overrides, " for another trackpad mode");
        return;
    }

    // In place: the stream's own settings, which a later reconnect copies, then the passthrough again
    StreamingPreferences* prefs = session->forkPreferences();
    prefs->trackpadMode = static_cast<StreamingPreferences::TrackpadMode>(mode);
    // A touchpad mode takes the game's mouse, as StreamProfiles::createSession() has it; Mac mouse
    // gives back a remote desktop's it took
    if (mode != ReconnectRules::k_TrackpadMacMouse && input->forkAbsoluteMouseMode()) {
        m_AbsoluteBeforeTouchpad = true;
        input->forkSetAbsoluteMouseMode(false);
    }
    else if (mode == ReconnectRules::k_TrackpadMacMouse && m_AbsoluteBeforeTouchpad) {
        m_AbsoluteBeforeTouchpad = false;
        input->forkSetAbsoluteMouseMode(true);
    }
    prefs->absoluteMouseMode = input->forkAbsoluteMouseMode();
    if (m_BarMenusOpen) {
        if (input->isCaptureActive()) {
            // Taking input again put the pointer back in the picture: the menu is still open
            input->forkSuspendRegionLock();
        }
        // What the bar leaves it as, so MenusClosed doesn't take this for the user's change
        m_CaptureLeftByBar = input->isCaptureActive();
    }

    ForkTrackpadPassthrough::deactivate();
    ForkTrackpadPassthrough::activate(m_Window, *prefs);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar: trackpad mode %d, in place (the stream started in %d)", mode,
                m_TrackpadStartedMode);
    m_TrackpadMode = mode;
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
    if (m_Power) {
        PowerRules::Reading power = m_Power->reading();
        if (!power.present) {
            context.power = QStringLiteral("no battery");
        }
        else {
            context.power = QStringLiteral("%1% %2%3, since the stream started %4")
                                .arg(power.level)
                                .arg(power.onAC ? (power.charging ? QStringLiteral("charging") : QStringLiteral("on a power adapter")) : QStringLiteral("on battery"))
                                .arg(PowerRules::known(power.watts) ? QStringLiteral(", %1").arg(QString::fromStdString(PowerRules::wattsText(power.watts))) : QString())
                                .arg(m_Power->startLevel() >= 0 ? QString::fromStdString(PowerRules::sinceStart(m_Power->startLevel(), power.level, m_Power->minutesSinceStart()))
                                                                : QStringLiteral("unknown"));
        }
        context.power += QStringLiteral(", Low Power Mode %1, Stream Battery Saver %2")
                             .arg(m_Power->lowPowerMode() ? QStringLiteral("on") : QStringLiteral("off"),
                                  m_Saver && m_Saver->on() ? QStringLiteral("on") : QStringLiteral("off"));
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
        if (m_SaverPending) {
            applySaver();
        }
        if (m_NotchBar) {
            m_NotchBar->bitrateChanged();
        }
        return;
    }
    if (ForkPower::isChangeEvent(event)) {
        // The battery or Low Power Mode changed. The saver follows Low Power Mode, and turning it on
        // is said beside the notch.
        if (m_Power && m_Saver) {
            bool wasLowPower = m_Saver->lowPowerMode();
            if (m_Saver->setLowPowerMode(m_Power->lowPowerMode())) {
                applySaver();
            }
            if (!wasLowPower && m_Saver->lowPowerMode()) {
                m_PowerNotice->offer([this] { return powerNotice(); });
            }
        }
        if (m_NotchBar) {
            m_NotchBar->powerChanged();
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
