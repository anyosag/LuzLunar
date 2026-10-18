#include "forktrackpadpassthrough.h"

#include <memory>
#include <optional>
#include <utility>

#include <QObject>
#include <QtGlobal>

#include <Limelight.h>

#include "forkpreferences.h"
#include "forktrackpad.h"
#include "luztouchpad.h"
#include "mac/gesturesuppressor_mac.h"
#include "mac/trackpadcapture_mac.h"
#include "settings/streamingpreferences.h"

namespace
{
    struct State {
        SDL_Window* window = nullptr;
        bool settingOn = false;
        bool hostSupports = false;
        bool log = false;  // LUZLUNAR_TRACKPAD_LOG=1: every frame in the log
        bool active = false;

        ForkTrackpad::ContactTracker tracker;
        ForkTrackpad::MuteFilter mute;
        std::uint8_t lastButtons = 0;
        Uint32 lastSentTicks = 0;
        SDL_TimerID keepaliveTimer = 0;
        int sendFailures = 0;

        std::function<bool(const QString&)> sink;
        bool toldAccessibility = false;
    };

    std::unique_ptr<State> s_State;
    std::function<bool(const QString&)> s_Sink;

    Uint32 keepaliveEventType()
    {
        static Uint32 type = SDL_RegisterEvents(1);
        return type;
    }

    // On SDL's timer thread: wake the stream's event loop to resend held fingers
    Uint32 keepaliveTick(Uint32 interval, void*)
    {
        SDL_Event event = {};
        event.type = keepaliveEventType();
        SDL_PushEvent(&event);
        return interval;
    }

    void tell(const QString& text)
    {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] %s", qPrintable(text));
        if (s_State && s_State->sink) {
            s_State->sink(text);
        }
    }

    void send(const luztouchpad::frame& frame)
    {
        State& s = *s_State;
        bool reliable = luztouchpad::is_reliable(frame, s.lastButtons);
        luztouchpad::packet packet = luztouchpad::encode(frame);
        int err = LiSendForkInputPacket(packet.data(), static_cast<uint32_t>(packet.size()), luztouchpad::k_channel, reliable);
        if (err != 0 && s.sendFailures++ == 0) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't send a trackpad frame: %d", err);
        }
        s.lastButtons = frame.buttons;
        s.lastSentTicks = SDL_GetTicks();

        if (s.log) {
            QString contacts;
            for (std::size_t i = 0; i < frame.count; i++) {
                const luztouchpad::contact& c = frame.contacts[i];
                contacts += QString(" %1:%2@%3,%4").arg(c.slot).arg(c.phase).arg(c.x).arg(c.y);
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Trackpad frame t=%u buttons=%u flags=%u%s%s",
                        frame.time_ms, frame.buttons, frame.flags, qPrintable(contacts), reliable ? " (reliable)" : "");
        }
    }

    void sendIf(const std::optional<luztouchpad::frame>& frame)
    {
        if (frame) {
            send(*frame);
        }
    }

    // From the capture's local monitor, on the main thread
    void onTouches(const std::vector<ForkTrackpad::Touch>& touches, std::uint32_t timeMs)
    {
        if (!s_State || !s_State->active) {
            return;
        }
        sendIf(s_State->tracker.update(touches, timeMs));
        s_State->mute.touching(s_State->tracker.touching(), timeMs);
    }

    void setActive(bool active)
    {
        State& s = *s_State;
        if (active == s.active) {
            return;
        }
        s.active = active;

        if (active) {
            // Fingers already on the pad began before Windows could see them; they're left alone
            s.tracker.reset();
            s.mute.reset();
            s.lastButtons = 0;
            ForkGestureSuppressor::setArmed(true);
            if (s.keepaliveTimer == 0) {
                s.keepaliveTimer = SDL_AddTimer(luztouchpad::k_keepalive_ms, keepaliveTick, nullptr);
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Trackpad passthrough on: the trackpad is a Windows touchpad");

            if (!ForkGestureSuppressor::tapRunning() && !s.toldAccessibility) {
                s.toldAccessibility = true;
                tell(QObject::tr("To keep macOS's swipes in the stream, allow LuzLunar in Privacy & Security › Accessibility"));
            }
        }
        else {
            // Lift whatever Windows still holds
            sendIf(s.tracker.cancelAll(SDL_GetTicks()));
            s.tracker.reset();
            s.mute.reset();
            ForkGestureSuppressor::setArmed(false);
            if (s.keepaliveTimer != 0) {
                SDL_RemoveTimer(s.keepaliveTimer);
                s.keepaliveTimer = 0;
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Trackpad passthrough off: the trackpad is a mouse");
        }
    }

    void evaluate()
    {
        if (!s_State || s_State->window == nullptr) {
            return;
        }
        State& s = *s_State;

        ForkTrackpad::Conditions c;
        c.settingOn = s.settingOn;
        c.hostSupports = s.hostSupports;
        c.captured = c.relativeMouse = SDL_GetRelativeMouseMode() == SDL_TRUE;
        c.windowFocused = (SDL_GetWindowFlags(s.window) & SDL_WINDOW_INPUT_FOCUS) != 0;
        c.windowKey = c.appActive = ForkTrackpadCapture::streamWindowIsKey();
        setActive(ForkTrackpad::shouldBeActive(c));
    }
}

void ForkTrackpadPassthrough::setMessageSink(std::function<bool(const QString&)> sink)
{
    s_Sink = std::move(sink);
    if (s_State) {
        s_State->sink = s_Sink;
    }
}

void ForkTrackpadPassthrough::activate(SDL_Window* window, const StreamingPreferences& prefs)
{
    s_State = std::make_unique<State>();
    s_State->sink = s_Sink;
    s_State->settingOn = prefs.trackpadPassthrough;
    if (!s_State->settingOn) {
        return;
    }

    // LUZLUNAR_TRACKPAD_FORCE=1 sends frames to any host, to try it; one without passthrough
    // drops them as an unknown input type
    bool forced = qgetenv("LUZLUNAR_TRACKPAD_FORCE") == "1";
    s_State->log = qgetenv("LUZLUNAR_TRACKPAD_LOG") == "1";
    s_State->hostSupports = forced || (LiGetHostFeatureFlags() & luztouchpad::k_host_feature_flag) != 0;
    if (!s_State->hostSupports) {
        tell(QObject::tr("This PC's Apollo can't take the trackpad as a touchpad, so it stays a mouse"));
        return;
    }

    s_State->window = window;
    if (!ForkTrackpadCapture::start(window, onTouches)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't read the trackpad's touches; it stays a mouse");
        s_State->window = nullptr;
        return;
    }
    ForkGestureSuppressor::start(ForkPreferences::get()->trackpadPauseMacSettings());
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Trackpad passthrough ready%s", forced ? " (forced)" : "");
    evaluate();
}

void ForkTrackpadPassthrough::deactivate()
{
    if (!s_State) {
        return;
    }
    if (s_State->window != nullptr) {
        setActive(false);
        ForkGestureSuppressor::stop();
        ForkTrackpadCapture::stop();
    }
    s_State.reset();
}

void ForkTrackpadPassthrough::handleEvent(const SDL_Event& event)
{
    if (!s_State || s_State->window == nullptr) {
        return;
    }

    if (event.type == SDL_QUIT) {
        // The connection is still up here, unlike when the stream's extensions go away
        setActive(false);
        s_State->settingOn = false;
        return;
    }

    if (event.type == keepaliveEventType()) {
        State& s = *s_State;
        Uint32 now = SDL_GetTicks();
        if (s.active && SDL_TICKS_PASSED(now, s.lastSentTicks + luztouchpad::k_keepalive_ms)) {
            sendIf(s.tracker.keepalive(now));
        }
    }

    // Focus, key window and capture all count, and the screenshot tools can free the mouse
    // without going through SdlInputHandler, so look on every event
    evaluate();
}

void ForkTrackpadPassthrough::update()
{
    evaluate();
}

bool ForkTrackpadPassthrough::muteMotion(const SDL_MouseMotionEvent* event)
{
    return s_State && s_State->active && s_State->mute.muteMotion(event->timestamp);
}

bool ForkTrackpadPassthrough::muteWheel(const SDL_MouseWheelEvent* event)
{
    return s_State && s_State->active && s_State->mute.muteWheel(event->timestamp);
}

bool ForkTrackpadPassthrough::muteButton(const SDL_MouseButtonEvent* event)
{
    if (!s_State || !s_State->active) {
        return false;
    }
    State& s = *s_State;
    switch (s.mute.button(event->button, event->state == SDL_PRESSED, event->timestamp)) {
    case ForkTrackpad::ButtonAction::PressPad:
        sendIf(s.tracker.setButton(true, event->timestamp));
        return true;
    case ForkTrackpad::ButtonAction::ReleasePad:
        sendIf(s.tracker.setButton(false, event->timestamp));
        return true;
    case ForkTrackpad::ButtonAction::Mute:
        return true;
    case ForkTrackpad::ButtonAction::Pass:
    default:
        return false;
    }
}
