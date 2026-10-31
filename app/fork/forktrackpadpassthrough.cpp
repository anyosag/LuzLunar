#include "forktrackpadpassthrough.h"

#include <atomic>
#include <memory>
#include <optional>
#include <string>
#include <utility>

#include <QObject>
#include <QtGlobal>

#include <Limelight.h>

#include "forkcursor.h"
#include "forkevents.h"
#include "forkmultitouch.h"
#include "forkpreferences.h"
#include "forktrackpad.h"
#include "luztouchpad.h"
#include "mac/gesturesuppressor_mac.h"
#include "mac/trackpadcapture_mac.h"
#include "settings/streamingpreferences.h"
#include "streaming/streamutils.h"

#ifdef Q_OS_DARWIN
#include "mac/multidisplay_mac.h"
#endif

namespace
{
    struct State {
        SDL_Window* window = nullptr;
        bool settingOn = false;
        bool hostSupports = false;
        bool log = false;  // LUZLUNAR_TRACKPAD_LOG=1: every frame in the log
        bool active = false;

        // Mac trackpad mode: macOS's own pointer, clicks and scrolling go to Windows as a mouse, and
        // only gestures go to the touchpad. Else the touchpad gets every finger.
        bool macMode = false;
        bool multitouch = false;  // MultitouchSupport gives contact sizes for palm rejection

        ForkTrackpad::ContactTracker tracker;
        ForkTrackpad::MuteFilter mute;
        std::uint8_t lastButtons = 0;
        Uint32 lastSentTicks = 0;
        SDL_TimerID keepaliveTimer = 0;
        int sendFailures = 0;

        // Mac trackpad mode
        int streamWidth = 0;
        int streamHeight = 0;
        double scrollSpeed = 1.0;  // Wheel units per point
        bool reverseScroll = false;
        ForkTrackpad::Carry pointerX;
        ForkTrackpad::Carry pointerY;
        ForkTrackpad::Carry scrollX;
        ForkTrackpad::Carry scrollY;
        ForkTrackpad::MacMute macMute;

        std::function<bool(const QString&)> sink;
        bool toldAccessibility = false;
    };

    std::unique_ptr<State> s_State;
    std::function<bool(const QString&)> s_Sink;
    std::function<void(int, int, double, double)> s_PointerListener;
    // Mac trackpad mode's pointer moves sent to Windows, ever (macPointerMoves())
    std::atomic<unsigned> s_MacPointerMoves { 0 };

    Uint32 keepaliveEventType()
    {
        static Uint32 type = ForkEvents::registerType();
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
        State& s = *s_State;
        if (s.multitouch) {
            // With each contact's size and hand part, for palm rejection
            std::vector<ForkTrackpad::Touch> sized = touches;
            ForkMultitouch::annotateNow(sized);
            sendIf(s.tracker.update(sized, timeMs));
        }
        else {
            sendIf(s.tracker.update(touches, timeMs));
        }
        s.mute.touching(s.tracker.touching(), timeMs);
    }

    // Mac trackpad mode, from the capture's monitor: macOS's own pointer motion in points
    void onMacPointer(double dx, double dy, std::uint32_t)
    {
        if (!s_State || !s_State->active) {
            return;
        }
        State& s = *s_State;
        s.macMute.pointerHandled(SDL_GetTicks());
        if (s.tracker.gestureOpen()) {
            // Windows has the fingers for a gesture
            return;
        }

        // The pointer crosses as much of the video as it would of the Mac's screen, like the
        // video's own pixels (the same fit as absolute mouse mode)
        int windowWidth = 0;
        int windowHeight = 0;
        SDL_GetWindowSize(s.window, &windowWidth, &windowHeight);
        SDL_Rect src = { 0, 0, s.streamWidth, s.streamHeight };
        SDL_Rect dst = { 0, 0, windowWidth, windowHeight };
        StreamUtils::scaleSourceToDestinationSurface(&src, &dst);
        double scaleX = dst.w > 0 ? static_cast<double>(s.streamWidth) / dst.w : 1.0;
        double scaleY = dst.h > 0 ? static_cast<double>(s.streamHeight) / dst.h : 1.0;

        int x = s.pointerX.take(dx * scaleX);
        int y = s.pointerY.take(dy * scaleY);
        if (x != 0 || y != 0) {
            if (LiSendMouseMoveEvent(static_cast<short>(x), static_cast<short>(y)) == 0) {
                // Where the PC's pointer goes, for the pointer this Mac draws (forkcursor.*)
                ForkCursor::sentMove(x, y);
            }
            s_MacPointerMoves++;
        }
        if (s_PointerListener) {
            // Less than a pixel still counts as pushing
            s_PointerListener(x, y, dx, dy);
        }
    }

    // Mac trackpad mode: a trackpad's or Magic Mouse's scrolling in points, momentum included.
    // True when it's taken care of here.
    bool onMacScroll(double dx, double dy, std::uint32_t)
    {
        if (!s_State || !s_State->active) {
            return false;
        }
        State& s = *s_State;
        if (s.tracker.gestureOpen()) {
            // Windows has the fingers for a gesture, and makes its own scrolling of them
            return true;
        }
        if (s.reverseScroll) {
            dx = -dx;
            dy = -dy;
        }

        // A wheel notch is 120 units: at speed 1, a point is a unit
        int vertical = s.scrollY.take(dy * s.scrollSpeed);
        int horizontal = s.scrollX.take(dx * s.scrollSpeed);
        if (vertical != 0) {
            LiSendHighResScrollEvent(static_cast<short>(vertical));
        }
        if (horizontal != 0) {
            LiSendHighResHScrollEvent(static_cast<short>(horizontal));
        }
        return true;
    }

    // Mac trackpad mode: macOS started a pinch, which Windows makes from the fingers
    void onPinch(std::uint32_t timeMs)
    {
        if (!s_State || !s_State->active) {
            return;
        }
        sendIf(s_State->tracker.openGesture(timeMs));
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
            s.macMute.reset();
            s.lastButtons = 0;
            ForkGestureSuppressor::setArmed(true);
            if (s.keepaliveTimer == 0) {
                s.keepaliveTimer = SDL_AddTimer(luztouchpad::k_keepalive_ms, keepaliveTick, nullptr);
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, s.macMode ? "[fork] Mac trackpad on: macOS points, clicks and scrolls, Windows gets the gestures"
                                                                : "[fork] Trackpad passthrough on: the trackpad is a Windows touchpad");

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
            s.macMute.reset();
            s.pointerX.reset();
            s.pointerY.reset();
            s.scrollX.reset();
            s.scrollY.reset();
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
        bool active = ForkTrackpad::shouldBeActive(c);

        // Why it stops, so a stretch with two pointers can be explained from the log
        if (s.active && !active) {
            std::string why;
            auto add = [&why](bool failed, const char* reason) {
                if (failed) {
                    why += why.empty() ? reason : std::string(", ") + reason;
                }
            };
            add(!c.captured, "the stream let go of the mouse");
            add(!c.windowFocused, "its window lost the keyboard focus");
            add(!c.windowKey, "its window isn't the key window of the active app");
#ifdef Q_OS_DARWIN
            why += "; in front: " + MultiDisplayMac::activeAppName();
#endif
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Trackpad passthrough stops: %s", why.c_str());
        }
        setActive(active);
    }

    // Typing, as palm rejection counts it: a key that types, not a modifier or a shortcut, so a
    // Command-click or a held Shift doesn't keep the trackpad from working
    bool typingKey(const SDL_KeyboardEvent& key)
    {
        SDL_Scancode code = key.keysym.scancode;
        bool modifier = code >= SDL_SCANCODE_LCTRL && code <= SDL_SCANCODE_RGUI;
        return key.repeat == 0 && !modifier && (key.keysym.mod & (KMOD_GUI | KMOD_CTRL | KMOD_ALT)) == 0;
    }
}

void ForkTrackpadPassthrough::setMessageSink(std::function<bool(const QString&)> sink)
{
    s_Sink = std::move(sink);
    if (s_State) {
        s_State->sink = s_Sink;
    }
}

void ForkTrackpadPassthrough::setMacPointerListener(std::function<void(int, int, double, double)> listener)
{
    s_PointerListener = std::move(listener);
}

bool ForkTrackpadPassthrough::macPointerActive()
{
    return s_State && s_State->active && s_State->macMode;
}

bool ForkTrackpadPassthrough::macPointerMode()
{
    return s_State && s_State->window != nullptr && s_State->macMode;
}

unsigned ForkTrackpadPassthrough::macPointerMoves()
{
    return s_MacPointerMoves.load();
}

void ForkTrackpadPassthrough::activate(SDL_Window* window, const StreamingPreferences& prefs)
{
    s_State = std::make_unique<State>();
    s_State->sink = s_Sink;
    s_State->settingOn = prefs.trackpadMode != StreamingPreferences::TM_MAC_MOUSE;
    if (!s_State->settingOn) {
        return;
    }
    State& s = *s_State;

    // LUZLUNAR_TRACKPAD_FORCE=1 sends frames to any host, to try it; one without passthrough
    // drops them as an unknown input type
    bool forced = qgetenv("LUZLUNAR_TRACKPAD_FORCE") == "1";
    s.log = qgetenv("LUZLUNAR_TRACKPAD_LOG") == "1";
    std::uint32_t features = LiGetHostFeatureFlags();
    s.hostSupports = forced || (features & luztouchpad::k_host_feature_flag) != 0;
    if (!s.hostSupports) {
        tell(QObject::tr("This PC's Apollo can't take the trackpad as a touchpad, so it stays a mouse"));
        return;
    }

    // Mac trackpad mode needs the host to keep its touchpad to gestures and its pointer speed out
    // of the way (it was asked to at launch); an older Apollo gets the Windows touchpad
    if (prefs.trackpadMode == StreamingPreferences::TM_MAC_TRACKPAD) {
        s.macMode = forced || (features & luztouchpad::k_host_mac_trackpad_flag) != 0;
        if (!s.macMode) {
            tell(QObject::tr("This PC's Apollo predates Mac trackpad mode, so the trackpad is a Windows touchpad until it updates"));
        }
    }
    s.tracker.setGestureOnly(s.macMode);
    s.streamWidth = prefs.width;
    s.streamHeight = prefs.height;
    s.scrollSpeed = ForkPreferences::get()->trackpadScrollSpeed();
    s.reverseScroll = prefs.reverseScrollDirection;

    ForkTrackpadCapture::MacInput mac;
    if (s.macMode) {
        mac.pointer = onMacPointer;
        mac.scroll = onMacScroll;
        mac.pinchBegan = onPinch;
    }

    s.window = window;
    if (!ForkTrackpadCapture::start(window, onTouches, mac)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't read the trackpad's touches; it stays a mouse");
        s.window = nullptr;
        return;
    }
    ForkGestureSuppressor::start(ForkPreferences::get()->trackpadPauseMacSettings());

    s.multitouch = ForkMultitouch::start();
    if (s.multitouch) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Palm rejection has the contacts' sizes from MultitouchSupport");
    }
    else {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Palm rejection goes without the contacts' sizes: %s",
                    ForkMultitouch::why().c_str());
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Trackpad passthrough ready%s%s", s.macMode ? " in Mac trackpad mode" : "",
                forced ? " (forced)" : "");
    evaluate();
}

void ForkTrackpadPassthrough::deactivate()
{
    if (!s_State) {
        return;
    }
    State& s = *s_State;
    if (s.window != nullptr) {
        setActive(false);
        if (s.multitouch) {
            std::string why = ForkMultitouch::why();
            if (!why.empty()) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] MultitouchSupport stopped giving contact sizes: %s", why.c_str());
            }
            ForkMultitouch::stop();
        }
        ForkGestureSuppressor::stop();
        ForkTrackpadCapture::stop();

        const ForkTrackpad::RejectStats& r = s.tracker.rejected();
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Palm rejection this stream: %d palms, %d touches while typing, %d resting thumbs, %d late palms cancelled",
                    r.palms, r.typing, r.thumbs, r.late);
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

    if (event.type == SDL_KEYDOWN && s_State->active && typingKey(event.key)) {
        // A touch that lands while you type is a palm
        s_State->tracker.keyDown(event.key.timestamp);
    }

    if (event.type == keepaliveEventType()) {
        State& s = *s_State;
        Uint32 now = SDL_GetTicks();
        if (s.active) {
            // A touch held still brings no events: it's decided once its time is up
            sendIf(s.tracker.tick(now));
            if (SDL_TICKS_PASSED(now, s.lastSentTicks + luztouchpad::k_keepalive_ms)) {
                sendIf(s.tracker.keepalive(now));
            }
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
    if (!s_State || !s_State->active) {
        return false;
    }
    if (s_State->macMode) {
        // Sent from macOS's own event already
        return s_State->macMute.muteMotion(event->timestamp);
    }
    return s_State->mute.muteMotion(event->timestamp);
}

bool ForkTrackpadPassthrough::muteWheel(const SDL_MouseWheelEvent* event)
{
    if (!s_State || !s_State->active || s_State->macMode) {
        // In Mac trackpad mode SDL only gets a mouse's wheel: the trackpad's scrolling went out
        // from macOS's own events
        return false;
    }
    return s_State->mute.muteWheel(event->timestamp);
}

bool ForkTrackpadPassthrough::muteButton(const SDL_MouseButtonEvent* event)
{
    if (!s_State || !s_State->active) {
        return false;
    }
    State& s = *s_State;
    if (s.macMode) {
        // macOS's clicks go to Windows, except while Windows has the fingers for a gesture
        return s.macMute.button(event->button, event->state == SDL_PRESSED, s.tracker.gestureOpen());
    }
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
