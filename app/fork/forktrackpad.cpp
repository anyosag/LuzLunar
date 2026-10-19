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

    // A palm by Apple's own label: MultitouchSupport's fingerID 6-7
    bool palmHand(const Touch& t)
    {
        return t.hasContact && (t.fingerId == 6 || t.fingerId == 7);
    }

    // Palm-sized: a short axis wider than a fingertip's
    bool wide(const Touch& t)
    {
        return t.hasContact && t.minorAxisMm >= k_PalmMinorMm;
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

int ContactTracker::usedSlots() const
{
    int used = 0;
    for (const Slot& s : m_Slots) {
        if (s.used) {
            used++;
        }
    }
    return used;
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
    return usedSlots() > 0;
}

bool ContactTracker::touching() const
{
    return fingersDown() || !m_Ignored.empty() || !m_Pending.empty();
}

void ContactTracker::keyDown(std::uint32_t timeMs)
{
    // A key soon after the last one is typing, which gets the longer window
    bool typingOn = m_KeyTyped && since(timeMs, m_LastKey) >= 0 &&
                    since(timeMs, m_LastKey) <= static_cast<std::int32_t>(k_TypingMs);
    m_TypingUntil = timeMs + (typingOn ? k_TypingMs : k_FirstKeyMs);
    m_LastKey = timeMs;
    m_KeyTyped = true;
}

bool ContactTracker::typing(std::uint32_t timeMs) const
{
    return m_KeyTyped && since(m_TypingUntil, timeMs) > 0;
}

void ContactTracker::observe(Pending& p, const Touch& t, std::uint32_t timeMs)
{
    if (t.resting) {
        p.resting = true;
        return;
    }
    if (p.resting) {
        // It stopped resting: it's decided afresh from here
        p.resting = false;
        p.since = timeMs;
        p.frames = 0;
        p.wideFrames = 0;
        p.startX = t.x;
        p.startY = 1.0 - t.y;
    }
    if (palmHand(t)) {
        p.wideFrames = k_PalmFrames;
    }
    else if (p.frames < k_DecideFrames && wide(t)) {
        p.wideFrames++;
    }
    if (t.hasContact && t.fingerId == 1) {
        p.thumb = true;
    }
    p.frames++;
    p.x = t.x;
    p.y = 1.0 - t.y;
}

double ContactTracker::movedMm(const Pending& p) const
{
    // A point is 1/72 inch
    double dx = (p.x - p.startX) * p.deviceWidth * 25.4 / 72.0;
    double dy = (p.y - p.startY) * p.deviceHeight * 25.4 / 72.0;
    return std::sqrt(dx * dx + dy * dy);
}

bool ContactTracker::adopt(std::uintptr_t identity, const Pending& p, std::array<bool, luztouchpad::k_max_contacts>& began)
{
    int free = freeSlot();
    if (free < 0 || (m_Device != 0 && p.device != m_Device)) {
        // A sixth finger, or one on another pad while this one is in use
        return false;
    }
    Slot& s = m_Slots[free];
    s = Slot();
    s.used = true;
    s.identity = identity;
    s.x = quantize(p.x);
    s.y = quantize(p.y);
    began[free] = true;
    if (m_Device == 0) {
        m_Device = p.device;
        padSize(p.deviceWidth, p.deviceHeight, &m_Width, &m_Height);
    }
    return true;
}

void ContactTracker::decide(std::uint32_t timeMs, std::array<bool, luztouchpad::k_max_contacts>& began, bool& changed)
{
    bool othersMoving = m_FingerMoved && since(timeMs, m_LastFingerMove) >= 0 &&
                        since(timeMs, m_LastFingerMove) <= static_cast<std::int32_t>(k_MovingMs);

    for (auto it = m_Pending.begin(); it != m_Pending.end();) {
        Pending& p = it->second;
        if (p.resting) {
            // A resting thumb or palm waits as long as macOS says it rests
            ++it;
            continue;
        }
        if (p.wideFrames >= k_PalmFrames) {
            m_Ignored.emplace(it->first, p.device);
            m_Rejected.palms++;
            it = m_Pending.erase(it);
            continue;
        }
        bool due = p.frames >= k_DecideFrames || since(timeMs, p.since) >= static_cast<std::int32_t>(k_DecideMs);
        if (!due) {
            ++it;
            continue;
        }
        if (p.thumb && p.startY >= k_ThumbZone && movedMm(p) < k_ThumbStillMm && othersMoving) {
            m_Ignored.emplace(it->first, p.device);
            m_Rejected.thumbs++;
            it = m_Pending.erase(it);
            continue;
        }
        if (adopt(it->first, p, began)) {
            changed = true;
        }
        else {
            m_Ignored.emplace(it->first, p.device);
        }
        it = m_Pending.erase(it);
    }
}

std::optional<luztouchpad::frame> ContactTracker::frameFor(std::uint32_t timeMs,
                                                           const std::array<bool, luztouchpad::k_max_contacts>& began,
                                                           const std::array<std::uint8_t, luztouchpad::k_max_contacts>& ending)
{
    // Mac trackpad mode: Windows hears about the fingers once enough of them make a gesture, and
    // then all of them go down together
    bool send = true;
    bool opening = false;
    if (m_GestureOnly && !m_Open) {
        int staying = 0;
        for (std::size_t i = 0; i < m_Slots.size(); i++) {
            if (m_Slots[i].used && ending[i] == 0) {
                staying++;
            }
        }
        if (staying >= k_GestureFingers) {
            m_Open = opening = true;
        }
        else {
            send = false;
        }
    }

    luztouchpad::frame f = baseFrame(timeMs);
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        Slot& s = m_Slots[i];
        if (!s.used) {
            continue;
        }
        bool ends = ending[i] != 0;
        if (send && !(opening && ends)) {
            luztouchpad::contact c;
            c.slot = static_cast<std::uint8_t>(i);
            if (began[i] || opening) {
                c.phase = luztouchpad::phase_down;
            }
            else if (ends) {
                c.phase = ending[i];
            }
            else {
                c.phase = luztouchpad::phase_move;
            }
            c.x = s.x;
            c.y = s.y;
            f.contacts[f.count++] = c;
        }
        if (ends) {
            s = Slot();
        }
    }

    if (!fingersDown()) {
        // The next finger may be on another pad. The pad can't stay pressed without a finger on
        // it, and a gesture ends with its last finger.
        m_Device = 0;
        m_Buttons = 0;
        m_Open = false;
    }
    if (!send) {
        return std::nullopt;
    }
    m_Sent = true;
    return f;
}

std::optional<luztouchpad::frame> ContactTracker::update(const std::vector<Touch>& touches, std::uint32_t timeMs)
{
    bool changed = false;
    std::array<std::uint8_t, luztouchpad::k_max_contacts> ending {};  // phase_up or phase_cancel
    std::array<bool, luztouchpad::k_max_contacts> began {};
    std::set<std::uintptr_t> present;
    std::set<std::uintptr_t> devices;

    // A quick tap that went down in the last frame lifts in this one
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (m_Slots[i].used && m_Slots[i].liftNext) {
            ending[i] = luztouchpad::phase_up;
            changed = true;
        }
    }

    for (const Touch& t : touches) {
        present.insert(t.identity);
        devices.insert(t.device);
        bool ends = t.phase == TouchPhase::Ended || t.phase == TouchPhase::Cancelled;

        int slot = slotOf(t.identity);
        if (slot >= 0) {
            Slot& s = m_Slots[slot];
            if (s.liftNext) {
                continue;
            }
            if (t.phase == TouchPhase::Cancelled || t.resting) {
                // Taken away, or now a resting thumb: Windows mustn't make it a tap
                ending[slot] = luztouchpad::phase_cancel;
                changed = true;
                continue;
            }
            s.wideRun = wide(t) ? s.wideRun + 1 : 0;
            if (palmHand(t) || s.wideRun >= k_PalmFrames) {
                // A finger that turns out to be a palm: cancelled, and left out until it lifts
                ending[slot] = luztouchpad::phase_cancel;
                changed = true;
                m_Rejected.late++;
                if (!ends) {
                    m_Ignored.emplace(t.identity, t.device);
                }
                continue;
            }
            std::uint16_t x = quantize(t.x);
            std::uint16_t y = quantize(1.0 - t.y);
            if (x != s.x || y != s.y) {
                s.x = x;
                s.y = y;
                changed = true;
                m_FingerMoved = true;
                m_LastFingerMove = timeMs;
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

        auto pending = m_Pending.find(t.identity);
        if (pending != m_Pending.end()) {
            if (!ends) {
                observe(pending->second, t, timeMs);
                continue;
            }
            // It lifted before it was decided: a quick tap goes down now and lifts with the next
            // frame, unless it was a palm or resting by then
            Pending p = pending->second;
            m_Pending.erase(pending);
            bool tap = t.phase == TouchPhase::Ended && !p.resting && !t.resting && !palmHand(t) &&
                       p.wideFrames < k_PalmFrames && !(p.frames < k_DecideFrames && wide(t));
            if (tap) {
                p.x = t.x;
                p.y = 1.0 - t.y;
                if (adopt(t.identity, p, began)) {
                    m_Slots[slotOf(t.identity)].liftNext = true;
                    changed = true;
                }
            }
            continue;
        }

        if (ends) {
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
        if (m_Device != 0 && t.device != m_Device) {
            // A finger on another pad while this one is in use
            m_Ignored.emplace(t.identity, t.device);
            continue;
        }
        if (typing(timeMs)) {
            // A palm brushing the pad as you type
            m_Ignored.emplace(t.identity, t.device);
            m_Rejected.typing++;
            continue;
        }
        if (palmHand(t)) {
            m_Ignored.emplace(t.identity, t.device);
            m_Rejected.palms++;
            continue;
        }

        Pending p;
        p.device = t.device;
        p.deviceWidth = t.deviceWidth;
        p.deviceHeight = t.deviceHeight;
        p.since = timeMs;
        p.startX = p.x = t.x;
        p.startY = p.y = 1.0 - t.y;
        observe(p, t, timeMs);
        m_Pending.emplace(t.identity, p);
    }

    // A finger an event from its pad no longer carries went away without an end, as when macOS
    // takes over a gesture. Only judged by events from the same pad.
    if (devices.count(m_Device) != 0) {
        for (std::size_t i = 0; i < m_Slots.size(); i++) {
            if (m_Slots[i].used && !m_Slots[i].liftNext && ending[i] == 0 && present.count(m_Slots[i].identity) == 0) {
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
    for (auto it = m_Pending.begin(); it != m_Pending.end();) {
        if (devices.count(it->second.device) != 0 && present.count(it->first) == 0) {
            it = m_Pending.erase(it);
        }
        else {
            ++it;
        }
    }

    decide(timeMs, began, changed);
    closeEmptyGesture();

    if (!changed) {
        return std::nullopt;
    }
    return frameFor(timeMs, began, ending);
}

void ContactTracker::closeEmptyGesture()
{
    // A pinch opened for fingers still being decided, none of which made it to Windows
    if (m_Open && !fingersDown() && m_Pending.empty()) {
        m_Open = false;
    }
}

std::optional<luztouchpad::frame> ContactTracker::tick(std::uint32_t timeMs)
{
    bool changed = false;
    std::array<std::uint8_t, luztouchpad::k_max_contacts> ending {};
    std::array<bool, luztouchpad::k_max_contacts> began {};
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (m_Slots[i].used && m_Slots[i].liftNext) {
            ending[i] = luztouchpad::phase_up;
            changed = true;
        }
    }
    decide(timeMs, began, changed);
    closeEmptyGesture();
    if (!changed) {
        return std::nullopt;
    }
    return frameFor(timeMs, began, ending);
}

void ContactTracker::setGestureOnly(bool on)
{
    m_GestureOnly = on;
    m_Open = false;
}

std::optional<luztouchpad::frame> ContactTracker::openGesture(std::uint32_t timeMs)
{
    if (!m_GestureOnly || m_Open || (!fingersDown() && m_Pending.empty())) {
        return std::nullopt;
    }
    // Fingers still being decided go down as they're decided
    m_Open = true;
    if (!fingersDown()) {
        return std::nullopt;
    }
    luztouchpad::frame f = baseFrame(timeMs);
    for (std::size_t i = 0; i < m_Slots.size(); i++) {
        if (m_Slots[i].used) {
            luztouchpad::contact c;
            c.slot = static_cast<std::uint8_t>(i);
            c.phase = luztouchpad::phase_down;
            c.x = m_Slots[i].x;
            c.y = m_Slots[i].y;
            f.contacts[f.count++] = c;
        }
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
    if (!fingersDown() || (m_GestureOnly && !m_Open)) {
        return std::nullopt;
    }
    std::optional<luztouchpad::frame> f = keepalive(timeMs);
    m_Sent = true;
    return f;
}

std::optional<luztouchpad::frame> ContactTracker::keepalive(std::uint32_t timeMs) const
{
    if (!fingersDown() || (m_GestureOnly && !m_Open)) {
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
    m_Pending.clear();
    m_Device = 0;
    m_Buttons = 0;
    m_Sent = false;
    m_Open = false;
    m_FingerMoved = false;
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

int Carry::take(double value)
{
    if (!std::isfinite(value)) {
        return 0;
    }
    m_Rest += value;
    double whole = std::trunc(m_Rest);
    if (whole > 32767) {
        whole = 32767;
    }
    else if (whole < -32767) {
        whole = -32767;
    }
    m_Rest -= whole;
    if (std::fabs(m_Rest) >= 1) {
        // More than a short holds: the rest is dropped, not saved up
        m_Rest = 0;
    }
    return static_cast<int>(whole);
}

void MacMute::pointerHandled(std::uint32_t timeMs)
{
    m_Handled = true;
    m_LastHandled = timeMs;
}

bool MacMute::muteMotion(std::uint32_t timeMs) const
{
    // SDL stamps its copy as it reads the same event, just before or after the monitor sees it
    std::int32_t apart = since(timeMs, m_LastHandled);
    return m_Handled && apart >= -static_cast<std::int32_t>(k_PointerMs) && apart <= static_cast<std::int32_t>(k_PointerMs);
}

bool MacMute::button(int button, bool pressed, bool gestureOpen)
{
    if (pressed) {
        if (gestureOpen) {
            m_Muted.insert(button);
            return true;
        }
        return false;
    }
    return m_Muted.erase(button) != 0;
}

void MacMute::reset()
{
    m_Handled = false;
    m_LastHandled = 0;
    m_Muted.clear();
}

bool shouldBeActive(const Conditions& c)
{
    return c.settingOn && c.hostSupports && c.captured && c.relativeMouse &&
           c.windowFocused && c.windowKey && c.appActive;
}
}
