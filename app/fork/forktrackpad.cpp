#include "forktrackpad.h"

#include <cmath>

namespace ForkTrackpad
{
namespace
{
    // How far later is after earlier, across the clock wrapping
    std::int32_t since(std::uint32_t later, std::uint32_t earlier)
    {
        return static_cast<std::int32_t>(later - earlier);
    }

    std::uint16_t quantize(double value)
    {
        if (!(value > 0)) {
            return 0;
        }
        if (value >= 1) {
            return 65535;
        }
        return static_cast<std::uint16_t>(std::lround(value * 65535.0));
    }
}

void padSize(double widthPt, double heightPt, std::uint16_t* width, std::uint16_t* height)
{
    // A point is 1/72 inch, so 2540/72 hundredths of a millimeter
    double w = widthPt * 2540.0 / 72.0;
    double h = heightPt * 2540.0 / 72.0;
    if (!(w >= 4000 && w <= 25000 && h >= 4000 && h <= 25000)) {
        *width = k_FallbackWidth;
        *height = k_FallbackHeight;
        return;
    }
    *width = static_cast<std::uint16_t>(std::lround(w));
    *height = static_cast<std::uint16_t>(std::lround(h));
}

int ContactTracker::slotOf(std::uintptr_t identity) const
{
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (m_Slots[i].used && m_Slots[i].identity == identity) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

int ContactTracker::freeSlot() const
{
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (!m_Slots[i].used) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

luztouchpad::frame ContactTracker::baseFrame(std::uint32_t timeMs) const
{
    luztouchpad::frame f;
    f.width = m_Width;
    f.height = m_Height;
    f.time_ms = timeMs;
    f.buttons = m_Buttons;
    return f;
}

bool ContactTracker::fingersDown() const
{
    for (const Slot& s : m_Slots) {
        if (s.used) {
            return true;
        }
    }
    return false;
}

bool ContactTracker::touching() const
{
    return fingersDown() || !m_Ignored.empty();
}

std::optional<luztouchpad::frame> ContactTracker::update(const std::vector<Touch>& touches, std::uint32_t timeMs)
{
    bool changed = false;
    std::array<std::uint8_t, luztouchpad::k_max_contacts> ending {};  // phase_up or phase_cancel
    std::array<bool, luztouchpad::k_max_contacts> began {};
    std::set<std::uintptr_t> present;
    std::set<std::uintptr_t> devices;

    for (const Touch& t : touches) {
        present.insert(t.identity);
        devices.insert(t.device);
        bool ends = t.phase == TouchPhase::Ended || t.phase == TouchPhase::Cancelled;

        int slot = slotOf(t.identity);
        if (slot >= 0) {
            Slot& s = m_Slots[slot];
            if (t.phase == TouchPhase::Cancelled || t.resting) {
                // Taken away, or now a resting thumb: Windows mustn't make it a tap
                ending[slot] = luztouchpad::phase_cancel;
                changed = true;
                continue;
            }
            std::uint16_t x = quantize(t.x);
            std::uint16_t y = quantize(1.0 - t.y);
            if (x != s.x || y != s.y) {
                s.x = x;
                s.y = y;
                changed = true;
            }
            if (t.phase == TouchPhase::Ended) {
                ending[slot] = luztouchpad::phase_up;
                changed = true;
            }
            continue;
        }

        auto ignored = m_Ignored.find(t.identity);
        if (ignored != m_Ignored.end()) {
            if (ends) {
                m_Ignored.erase(ignored);
            }
            continue;
        }

        if (ends || t.resting) {
            continue;
        }
        if (t.phase != TouchPhase::Began) {
            // On the pad before passthrough started: ignored until it lifts
            m_Ignored.emplace(t.identity, t.device);
            continue;
        }
        if (t.deviceHeight > t.deviceWidth) {
            // A Magic Mouse's surface is taller than it's wide; it stays a mouse
            continue;
        }
        int free = freeSlot();
        if ((m_Device != 0 && t.device != m_Device) || free < 0) {
            // A finger on another pad while this one is in use, or a sixth finger
            m_Ignored.emplace(t.identity, t.device);
            continue;
        }

        Slot& s = m_Slots[free];
        s.used = true;
        s.identity = t.identity;
        s.x = quantize(t.x);
        s.y = quantize(1.0 - t.y);
        began[free] = true;
        if (m_Device == 0) {
            m_Device = t.device;
            padSize(t.deviceWidth, t.deviceHeight, &m_Width, &m_Height);
        }
        changed = true;
    }

    // A finger an event from its pad no longer carries went away without an end, as when macOS
    // takes over a gesture. Only judged by events from the same pad.
    if (devices.count(m_Device) != 0) {
        for (std::size_t i = 0; i < m_Slots.size(); i++) {
            if (m_Slots[i].used && ending[i] == 0 && present.count(m_Slots[i].identity) == 0) {
                ending[i] = luztouchpad::phase_cancel;
                changed = true;
            }
        }
    }
    for (auto it = m_Ignored.begin(); it != m_Ignored.end();) {
        if (devices.count(it->second) != 0 && present.count(it->first) == 0) {
            it = m_Ignored.erase(it);
        }
        else {
            ++it;
        }
    }

    if (!changed) {
        return std::nullopt;
    }

    luztouchpad::frame f = baseFrame(timeMs);
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (!m_Slots[i].used) {
            continue;
        }
        luztouchpad::contact c;
        c.slot = static_cast<std::uint8_t>(i);
        if (began[i]) {
            c.phase = luztouchpad::phase_down;
        }
        else if (ending[i] != 0) {
            c.phase = ending[i];
        }
        else {
            c.phase = luztouchpad::phase_move;
        }
        c.x = m_Slots[i].x;
        c.y = m_Slots[i].y;
        f.contacts[f.count++] = c;
        if (ending[i] != 0) {
            m_Slots[i] = Slot();
        }
    }

    if (!fingersDown()) {
        // The next finger may be on another pad. The pad can't stay pressed without a finger on it.
        m_Device = 0;
        m_Buttons = 0;
    }
    m_Sent = true;
    return f;
}

std::optional<luztouchpad::frame> ContactTracker::setButton(bool pressed, std::uint32_t timeMs)
{
    std::uint8_t buttons = pressed ? luztouchpad::button_pressed : 0;
    if (buttons == m_Buttons) {
        return std::nullopt;
    }
    m_Buttons = buttons;
    if (!fingersDown()) {
        return std::nullopt;
    }
    std::optional<luztouchpad::frame> f = keepalive(timeMs);
    m_Sent = true;
    return f;
}

std::optional<luztouchpad::frame> ContactTracker::keepalive(std::uint32_t timeMs) const
{
    if (!fingersDown()) {
        return std::nullopt;
    }
    luztouchpad::frame f = baseFrame(timeMs);
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (m_Slots[i].used) {
            luztouchpad::contact c;
            c.slot = static_cast<std::uint8_t>(i);
            c.phase = luztouchpad::phase_move;
            c.x = m_Slots[i].x;
            c.y = m_Slots[i].y;
            f.contacts[f.count++] = c;
        }
    }
    return f;
}

std::optional<luztouchpad::frame> ContactTracker::cancelAll(std::uint32_t timeMs)
{
    if (!m_Sent) {
        reset();
        return std::nullopt;
    }
    luztouchpad::frame f = baseFrame(timeMs);
    f.buttons = 0;
    f.flags = luztouchpad::flag_cancel_all;
    reset();
    return f;
}

void ContactTracker::reset()
{
    m_Slots = {};
    m_Ignored.clear();
    m_Device = 0;
    m_Buttons = 0;
    m_Sent = false;
}

void MuteFilter::touching(bool any, std::uint32_t timeMs)
{
    bool open = !m_Spans.empty() && m_Spans.back().open;
    if (any && !open) {
        Span span;
        span.start = timeMs;
        span.end = timeMs;
        span.open = true;
        m_Spans.push_back(span);
        if (m_Spans.size() > k_MaxSpans) {
            m_Spans.erase(m_Spans.begin());
        }
    }
    else if (!any && open) {
        m_Spans.back().open = false;
        m_Spans.back().end = timeMs;
    }
}

void MuteFilter::reset()
{
    m_Spans.clear();
    m_WheelMuted = false;
    m_LastMutedWheel = 0;
    m_MutedButtons.clear();
    m_PadButtons.clear();
}

bool MuteFilter::inTouch(std::uint32_t timeMs) const
{
    for (const Span& s : m_Spans) {
        if (since(timeMs, s.start) >= -static_cast<std::int32_t>(k_LeadMs) && (s.open || since(timeMs, s.end) <= 0)) {
            return true;
        }
    }
    return false;
}

bool MuteFilter::inTail(std::uint32_t timeMs) const
{
    for (const Span& s : m_Spans) {
        if (since(timeMs, s.start) >= -static_cast<std::int32_t>(k_LeadMs) &&
                (s.open || since(timeMs, s.end) <= static_cast<std::int32_t>(k_TailMs))) {
            return true;
        }
    }
    return false;
}

bool MuteFilter::muteMotion(std::uint32_t timeMs) const
{
    return inTail(timeMs);
}

bool MuteFilter::muteWheel(std::uint32_t timeMs)
{
    bool chained = m_WheelMuted && since(timeMs, m_LastMutedWheel) >= 0 &&
                   since(timeMs, m_LastMutedWheel) <= static_cast<std::int32_t>(k_WheelChainMs);
    bool mute = inTail(timeMs) || chained;
    m_WheelMuted = mute;
    if (mute) {
        m_LastMutedWheel = timeMs;
    }
    return mute;
}

ButtonAction MuteFilter::button(int button, bool pressed, std::uint32_t timeMs)
{
    if (pressed) {
        if (inTouch(timeMs)) {
            m_PadButtons.insert(button);
            return ButtonAction::PressPad;
        }
        if (inTail(timeMs)) {
            // macOS's tap to click, just after the lift: Windows taps from the fingers itself
            m_MutedButtons.insert(button);
            return ButtonAction::Mute;
        }
        return ButtonAction::Pass;
    }

    if (m_PadButtons.erase(button) != 0) {
        return m_PadButtons.empty() ? ButtonAction::ReleasePad : ButtonAction::Mute;
    }
    if (m_MutedButtons.erase(button) != 0) {
        return ButtonAction::Mute;
    }
    return ButtonAction::Pass;
}

bool shouldBeActive(const Conditions& c)
{
    return c.settingOn && c.hostSupports && c.captured && c.relativeMouse &&
           c.windowFocused && c.windowKey && c.appActive;
}
}
