#pragma once

// Trackpad passthrough's rules, without AppKit, SDL or Qt so tests/fork/trackpad_test.cpp can check
// them: which Mac touches become which contacts in the frames sent to Apollo (luztouchpad.h), and
// which of the trackpad's own mouse events to hold back while Windows gets the fingers.
//
// Palm rejection. A palm or a resting thumb never reaches Windows as a finger. The rules follow
// macOS's own and other drivers' (FORK.md, "Palm rejection"):
// - Each new touch waits until it's decided, at most k_DecideFrames frames or k_DecideMs (what
//   Windows asks of a touchpad), then goes to Windows from where it is by then. The decision sticks
//   until the touch lifts.
// - Apple's driver names each contact's hand part, and MultitouchSupport's fingerID 6-7 is the
//   palm from its first frame (forkmultitouch.*).
// - A palm's short axis is wider than a fingertip's: about 9.8 mm caught 98% of palm samples on a
//   14" MacBook Pro while fingertips stayed under 9.4 mm. k_PalmFrames of the first frames at
//   k_PalmMinorMm or more make a palm, and so do as many in a row later on, for one that spreads.
// - macOS's resting touches (a thumb or palm it flags) wait as long as they rest.
// - A touch that lands while you type is a palm: within k_FirstKeyMs of a first key, or k_TypingMs
//   of the last while keys keep coming (libinput's disable-while-typing).
// - A thumb that lands in the bottom of the pad and stays still while another finger moves is a
//   resting thumb.
//
// Mac trackpad mode (setGestureOnly): macOS's own pointer, clicks and scrolling go to Windows as
// mouse input instead, so frames only carry 3- and 4-finger gestures and pinch. Fingers are
// still followed, but Windows hears about them only once 3 are down or macOS starts a pinch, and
// then until the last one lifts.

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <vector>

#include "luztouchpad.h"

namespace ForkTrackpad
{
    enum class TouchPhase {
        Began,
        Moved,
        Stationary,
        Ended,
        Cancelled,
    };

    // One NSTouch, as the capture code reads it
    struct Touch {
        std::uintptr_t identity = 0;  // NSTouch.identity: the same object for a finger's whole contact
        std::uintptr_t device = 0;  // NSTouch.device
        TouchPhase phase = TouchPhase::Moved;
        double x = 0;  // normalizedPosition: 0 at the pad's left, 1 at its right
        double y = 0;  // 0 at the pad's bottom, 1 at its top (AppKit's origin)
        double deviceWidth = 0;  // deviceSize, in points (1/72 inch)
        double deviceHeight = 0;
        bool resting = false;  // macOS treats it as a resting thumb or palm

        // From MultitouchSupport, when it's loaded and found this touch (forkmultitouch.*)
        bool hasContact = false;
        int fingerId = 0;  // Apple's hand part: 1 thumb, 2-5 fingers, 6-7 palm, 0 unknown
        float minorAxisMm = 0;  // The contact's short axis
    };

    // A built-in trackpad's size when macOS reports none or an unlikely one, in 1/100 mm
    constexpr std::uint16_t k_FallbackWidth = 13000;
    constexpr std::uint16_t k_FallbackHeight = 8000;

    // Palm rejection (above)
    constexpr int k_DecideFrames = 3;
    constexpr std::uint32_t k_DecideMs = 50;
    constexpr float k_PalmMinorMm = 10.0f;
    constexpr int k_PalmFrames = 2;
    constexpr std::uint32_t k_FirstKeyMs = 200;
    constexpr std::uint32_t k_TypingMs = 500;
    constexpr double k_ThumbZone = 0.85;  // A thumb lands below this, from the pad's top (0) to its bottom (1)
    constexpr double k_ThumbStillMm = 2.0;  // and moves less than this
    constexpr std::uint32_t k_MovingMs = 100;  // A finger that moved this recently is moving

    // Mac trackpad mode: this many fingers make a gesture for Windows
    constexpr int k_GestureFingers = 3;

    // What palm rejection kept from Windows, for the log
    struct RejectStats {
        int palms = 0;  // By hand part or size
        int typing = 0;  // Landed while typing
        int thumbs = 0;  // Resting thumbs
        int late = 0;  // Fingers that turned out to be palms, cancelled
    };

    // The pad's size in 1/100 mm from NSTouch.deviceSize. Outside 40-250 mm it's the fallback.
    void padSize(double widthPt, double heightPt, std::uint16_t* width, std::uint16_t* height);

    // Turns AppKit's touch events into frames: up to 5 fingers in slots 0-4, each frame listing
    // every finger still on the pad.
    class ContactTracker
    {
    public:
        // One AppKit touch event with every touch it carries, at timeMs on the client's clock.
        // Returns a frame when Windows needs to hear about a change.
        std::optional<luztouchpad::frame> update(const std::vector<Touch>& touches, std::uint32_t timeMs);

        // Decides touches still waiting once their time is up, for a finger held still that
        // brings no events, and lifts a quick tap decided as it ended. Call with the keepalive.
        std::optional<luztouchpad::frame> tick(std::uint32_t timeMs);

        // A key was typed (not a modifier or a shortcut): touches that land now are palms
        void keyDown(std::uint32_t timeMs);

        // The pad was clicked down or let go. A frame when fingers are on the pad.
        std::optional<luztouchpad::frame> setButton(bool pressed, std::uint32_t timeMs);

        // The current fingers again, for the keepalive. None when no finger is down.
        std::optional<luztouchpad::frame> keepalive(std::uint32_t timeMs) const;

        // A frame that cancels everything on the host, then forgets every finger. None when
        // nothing was sent since the last reset, so there's nothing to cancel.
        std::optional<luztouchpad::frame> cancelAll(std::uint32_t timeMs);

        // Forgets everything without sending, for when passthrough starts. Fingers already on the
        // pad are then ignored until they lift: they began before Windows could see them.
        void reset();

        // Mac trackpad mode: frames only for gestures of k_GestureFingers or more, and pinch
        void setGestureOnly(bool on);

        // macOS started a pinch: the fingers on the pad go to Windows until the last one lifts,
        // including any still being decided. A frame when there are fingers to send now.
        std::optional<luztouchpad::frame> openGesture(std::uint32_t timeMs);

        // In Mac trackpad mode, whether Windows has the fingers now (a gesture)
        bool gestureOpen() const { return m_GestureOnly && m_Open; }

        // Fingers Windows has been told about
        bool fingersDown() const;

        // Any finger on the pad, including ignored ones: the trackpad is in use
        bool touching() const;

        std::uint8_t buttons() const { return m_Buttons; }

        const RejectStats& rejected() const { return m_Rejected; }

    private:
        struct Slot {
            bool used = false;
            std::uintptr_t identity = 0;
            std::uint16_t x = 0;
            std::uint16_t y = 0;
            int wideRun = 0;  // Palm-sized frames in a row
            bool liftNext = false;  // A quick tap: it went down in the last frame and lifts in the next
        };

        // A touch not sent yet, until it's decided
        struct Pending {
            std::uintptr_t device = 0;
            double deviceWidth = 0;
            double deviceHeight = 0;
            std::uint32_t since = 0;  // When it began, or last stopped resting
            int frames = 0;  // Frames since then
            int wideFrames = 0;  // Of those, palm-sized
            bool resting = false;
            bool thumb = false;  // MultitouchSupport calls it a thumb
            double startX = 0;  // Where it began or stopped resting: 0-1, y from the top
            double startY = 0;
            double x = 0;
            double y = 0;
        };

        luztouchpad::frame baseFrame(std::uint32_t timeMs) const;
        int slotOf(std::uintptr_t identity) const;
        int freeSlot() const;
        int usedSlots() const;
        bool typing(std::uint32_t timeMs) const;
        void observe(Pending& p, const Touch& t, std::uint32_t timeMs);
        void decide(std::uint32_t timeMs, std::array<bool, luztouchpad::k_max_contacts>& began, bool& changed);
        bool adopt(std::uintptr_t identity, const Pending& p, std::array<bool, luztouchpad::k_max_contacts>& began);
        double movedMm(const Pending& p) const;
        std::optional<luztouchpad::frame> frameFor(std::uint32_t timeMs, const std::array<bool, luztouchpad::k_max_contacts>& began,
                                                   const std::array<std::uint8_t, luztouchpad::k_max_contacts>& ending);
        void closeEmptyGesture();

        std::array<Slot, luztouchpad::k_max_contacts> m_Slots {};
        std::map<std::uintptr_t, std::uintptr_t> m_Ignored;  // identity -> its pad
        std::map<std::uintptr_t, Pending> m_Pending;
        std::uintptr_t m_Device = 0;  // The pad the fingers are on, until they all lift
        std::uint8_t m_Buttons = 0;
        std::uint16_t m_Width = k_FallbackWidth;
        std::uint16_t m_Height = k_FallbackHeight;
        bool m_Sent = false;

        bool m_KeyTyped = false;
        std::uint32_t m_LastKey = 0;
        std::uint32_t m_TypingUntil = 0;
        bool m_FingerMoved = false;
        std::uint32_t m_LastFingerMove = 0;

        bool m_GestureOnly = false;
        bool m_Open = false;

        RejectStats m_Rejected;
    };

    enum class ButtonAction {
        Pass,  // An ordinary mouse button: send it as usual
        Mute,  // The trackpad's own click, which Windows makes from the fingers: drop it
        PressPad,  // A click with fingers on the pad: drop it and press the pad in the frames
        ReleasePad,  // The last pad click let go: drop it and release the pad in the frames
    };

    // Decides which mouse events came from the trackpad while passthrough is on, so they aren't
    // sent twice. SDL gives every Mac mouse event the same mouse id, so it goes by time: the
    // pointer motion, scrolling and clicks a trackpad makes happen while fingers are on it, or
    // just after they lift. Times are SDL ticks (ms) and may wrap.
    class MuteFilter
    {
    public:
        static constexpr std::uint32_t k_LeadMs = 5;  // An event may be stamped just before the touch
        static constexpr std::uint32_t k_TailMs = 150;  // Taps click, and AppKit's events lag, after the lift
        static constexpr std::uint32_t k_WheelChainMs = 100;  // Momentum scrolling keeps going after the lift

        // Whether any finger is on the pad, from timeMs on
        void touching(bool any, std::uint32_t timeMs);

        // Forgets everything, for when passthrough starts or stops
        void reset();

        bool muteMotion(std::uint32_t timeMs) const;
        bool muteWheel(std::uint32_t timeMs);
        ButtonAction button(int button, bool pressed, std::uint32_t timeMs);

    private:
        struct Span {
            std::uint32_t start = 0;
            std::uint32_t end = 0;
            bool open = true;
        };

        static constexpr std::size_t k_MaxSpans = 8;

        bool inTouch(std::uint32_t timeMs) const;  // Fingers on the pad at that time
        bool inTail(std::uint32_t timeMs) const;  // Fingers on the pad then or shortly before

        std::vector<Span> m_Spans;
        bool m_WheelMuted = false;
        std::uint32_t m_LastMutedWheel = 0;
        std::set<int> m_MutedButtons;  // Their release is dropped too
        std::set<int> m_PadButtons;  // Pressing the pad; it's released with the last one
    };

    // Mac trackpad mode: carries the part of a whole unit a value leaves over to the next one, so
    // slow pointer motion and gentle scrolling aren't lost to rounding
    class Carry
    {
    public:
        // Adds value and returns the whole units due now, rounded toward zero, within a short's range
        int take(double value);
        void reset() { m_Rest = 0; }

    private:
        double m_Rest = 0;
    };

    // Mac trackpad mode: pointer motion goes to Windows from macOS's own events, so SDL's copy of
    // it is dropped. So are the clicks made while Windows has the fingers for a gesture.
    class MacMute
    {
    public:
        static constexpr std::uint32_t k_PointerMs = 100;  // SDL's copy of a move is stamped this close to it

        // macOS's pointer event was taken care of (sent, or dropped for a gesture)
        void pointerHandled(std::uint32_t timeMs);

        bool muteMotion(std::uint32_t timeMs) const;

        // True to drop a click: one pressed while a gesture is open, and its release
        bool button(int button, bool pressed, bool gestureOpen);

        void reset();

    private:
        bool m_Handled = false;
        std::uint32_t m_LastHandled = 0;
        std::set<int> m_Muted;
    };

    // What decides whether passthrough runs right now
    struct Conditions {
        bool settingOn = false;  // The stream's setting, with the app's override
        bool hostSupports = false;  // Apollo advertised luztouchpad::k_host_feature_flag
        bool captured = false;  // The stream has the mouse
        bool relativeMouse = false;  // The Mac cursor is held still and hidden
        bool windowFocused = false;
        bool windowKey = false;
        bool appActive = false;
    };

    bool shouldBeActive(const Conditions& c);
}
