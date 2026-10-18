#pragma once

// Trackpad passthrough's rules, without AppKit, SDL or Qt so tests/fork/trackpad_test.cpp can check
// them: which Mac touches become which contacts in the frames sent to Apollo (luztouchpad.h), and
// which of the trackpad's own mouse events to hold back while Windows gets the fingers.

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
    };

    // A built-in trackpad's size when macOS reports none or an unlikely one, in 1/100 mm
    constexpr std::uint16_t k_FallbackWidth = 13000;
    constexpr std::uint16_t k_FallbackHeight = 8000;

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

        // Fingers Windows has been told about
        bool fingersDown() const;

        // Any finger on the pad, including ignored ones: the trackpad is in use
        bool touching() const;

        std::uint8_t buttons() const { return m_Buttons; }

    private:
        struct Slot {
            bool used = false;
            std::uintptr_t identity = 0;
            std::uint16_t x = 0;
            std::uint16_t y = 0;
        };

        luztouchpad::frame baseFrame(std::uint32_t timeMs) const;
        int slotOf(std::uintptr_t identity) const;
        int freeSlot() const;

        std::array<Slot, luztouchpad::k_max_contacts> m_Slots {};
        std::map<std::uintptr_t, std::uintptr_t> m_Ignored;  // identity -> its pad
        std::uintptr_t m_Device = 0;  // The pad the fingers are on, until they all lift
        std::uint8_t m_Buttons = 0;
        std::uint16_t m_Width = k_FallbackWidth;
        std::uint16_t m_Height = k_FallbackHeight;
        bool m_Sent = false;
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
