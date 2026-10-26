#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>

// [fork] Reaching the notch bar with Mac trackpad mode's pointer. That pointer is the PC's, drawn in
// the picture, and Windows keeps it on the PC's screen, so it can't go up into the bar above the
// picture by itself. These are the rules for when the Mac's own pointer takes over: the PC's pointer
// is followed by the moves sent to it (Windows moves it a pixel a count in Mac trackpad mode). As a
// push up against the top begins, the PC is asked where its pointer is and to pulse it twice
// (POST /actions/cursor), as an app may have moved it since; only when the PC says it's at the top
// does the Mac's pointer go up into the bar, at the end of the second pulse, if the push is still on.
// Free of Qt, so tests can build it alone (tests/fork/barreach_test.cpp); ForkBarReach
// (forkbarreach.h) asks the PC.
namespace BarReach
{
    // Two pulses on the PC's pointer, as Apollo draws them (its cursor_pulse.h): the projection
    // leaves as the second ends
    const int k_Pulses = 2;
    const std::uint32_t k_PulseMs = 170;
    // At least this much of the Mac's pointer motion up, after macOS's acceleration, by then
    const double k_PushPoints = 24;
    // A push ends when nothing has pushed up for this long, or the pointer goes down. Long enough
    // for the finger to lift and come back between swipes up, as a push on a trackpad often is; a
    // throw up at a tab that stops still doesn't go, as going takes a move up after the pulses.
    const std::uint32_t k_PauseMs = 350;
    // As the pulses end, the pointer goes if the push moved up this recently: a swipe that kept on
    // past the top does, a throw up at a tab that stopped there doesn't
    const std::uint32_t k_GoMs = 200;
    const int k_DownPx = 2;
    // Questions go one at a time, at least this far apart
    const std::uint32_t k_AskGapMs = 200;

    // The PC's answer: its pointer from the top-left corner of the display the stream shows, in its
    // pixels; above the top (negative y) or beside the display while it's on another one
    struct Cursor {
        int x = 0;
        int y = 0;
        int width = 0;
        int height = 0;
        bool shown = false;     // Windows draws it: a game may hide it
        bool pulsing = false;   // the PC pulses it now, as asked
    };

    enum class Action {
        None,
        Ask,            // ask the PC where its pointer is, and to pulse it if it's at the top
        PulseHere,      // the PC can't pulse it: pulse it over the picture instead
        Cancel,         // the push stopped short: the pulses settle back
        HandOver,       // the Mac's pointer goes up into the bar, above fraction of the picture's width
    };

    struct Step {
        Action action = Action::None;
        double fraction = 0;    // HandOver: from 0 at the picture's left edge to 1 at its right
        bool pcPulses = false;  // Cancel: the PC's pulses, else the ones over the picture
    };

    class Tracker
    {
    public:
        // A move sent to the PC (in its pixels) and the Mac's pointer motion it came from (in points,
        // up negative), with a button held or not
        Step moved(int dx, int dy, double dxPoints, double dyPoints, bool buttonDown, std::uint32_t ms)
        {
            // Where Windows has it: kept on the display
            bool atTop = !m_Known;  // not known yet: any push may be at the top, and the first asks
            if (m_Known) {
                m_X = std::clamp(m_X + dx, 0, m_Width - 1);
                m_Y = std::clamp(m_Y + dy, 0, m_Height - 1);
                atTop = m_Y == 0;
            }
            if (m_Asking) {
                m_SinceAskX += dx;
                m_SinceAskY += dy;
            }

            Step ended;
            if (m_Pushing && ms - m_LastUpMs > k_PauseMs) {
                ended = endPush();
            }
            if (buttonDown || dy > k_DownPx || !atTop) {
                // Dragging, as a window up to the top to fill the screen, or not at the top
                Step step = endPush();
                return ended.action != Action::None ? ended : step;
            }
            if (dyPoints < 0 && -dyPoints >= std::fabs(dxPoints)) {
                // Mostly up: sliding along the top, as across tabs, doesn't push
                if (!m_Pushing) {
                    m_Pushing = true;
                    m_PushPoints = 0;
                }
                m_PushPoints += -dyPoints;
                m_LastUpMs = ms;
            }
            if (ended.action != Action::None) {
                return ended;
            }
            if (!m_Pushing) {
                return {};
            }

            if (m_Waiting) {
                return go(ms);
            }
            if (m_Asking || (m_Asked && ms - m_LastAskMs < k_AskGapMs)) {
                return {};
            }
            m_Asking = true;
            m_Asked = true;
            m_LastAskMs = ms;
            m_SinceAskX = 0;
            m_SinceAskY = 0;
            Step step;
            step.action = Action::Ask;
            return step;
        }

        // The PC's answer to the question asked
        Step answered(const Cursor& cursor, std::uint32_t ms)
        {
            m_Asking = false;
            m_PcPulses = cursor.pulsing;
            bool onDisplay = cursor.width > 0 && cursor.height > 0 && cursor.x >= 0 && cursor.x < cursor.width &&
                             cursor.y < cursor.height;
            if (!onDisplay) {
                // On another display beside this one: nothing to follow
                m_Known = false;
                m_Waiting = false;
                return settle();
            }

            // The moves sent since it was asked came after
            m_Known = true;
            m_Width = cursor.width;
            m_Height = cursor.height;
            m_X = std::clamp(cursor.x + m_SinceAskX, 0, m_Width - 1);
            m_Y = std::clamp(cursor.y + m_SinceAskY, 0, m_Height - 1);

            if (cursor.y > 0 || m_Y > 0 || !cursor.shown) {
                // Lower than it seemed, or hidden: a push starts again once it's at the top
                m_Pushing = false;
                m_Waiting = false;
                return settle();
            }
            if (!m_Pushing || ms - m_LastUpMs > k_PauseMs) {
                // The push ended while the PC answered
                m_Pushing = false;
                return settle();
            }
            m_Waiting = true;
            m_ReleaseAtMs = ms + k_Pulses * k_PulseMs;
            if (!cursor.pulsing) {
                m_HerePulses = true;
                Step step;
                step.action = Action::PulseHere;
                return step;
            }
            return {};
        }

        // The question went unanswered; the next push asks again
        void unanswered()
        {
            m_Asking = false;
        }

        // Now and then while the pulses run: they may have ended with no move since, or the push
        // stopped with no move to say so
        Step tick(std::uint32_t ms)
        {
            if (m_Pushing && ms - m_LastUpMs > k_PauseMs) {
                return endPush();
            }
            if (m_Pushing && m_Waiting) {
                return go(ms);
            }
            return {};
        }

        // Where the PC's pointer is isn't known any more: the stream stopped moving it, and something
        // else may have
        void forget()
        {
            m_Known = false;
            endPush();
        }

        bool known() const { return m_Known; }
        int x() const { return m_X; }
        int y() const { return m_Y; }
        int width() const { return m_Width; }
        int height() const { return m_Height; }
        bool asking() const { return m_Asking; }
        // Waiting for the pulses to end, or for the PC's answer: tick() wants calling
        bool busy() const { return m_Waiting || m_Asking || m_PcPulses || m_HerePulses; }

    private:
        // ms at or after then, across the wrap
        static bool reached(std::uint32_t ms, std::uint32_t then)
        {
            return static_cast<std::int32_t>(ms - then) >= 0;
        }

        // Up into the bar once the pulses have ended, with enough push, still pushing
        Step go(std::uint32_t ms)
        {
            if (!reached(ms, m_ReleaseAtMs) || m_PushPoints < k_PushPoints || ms - m_LastUpMs > k_GoMs) {
                return {};
            }
            m_Waiting = false;
            m_PcPulses = m_HerePulses = false;
            m_Pushing = false;
            Step step;
            step.action = Action::HandOver;
            step.fraction = (m_X + 0.5) / m_Width;
            return step;
        }

        Step endPush()
        {
            m_Pushing = false;
            m_Waiting = false;
            return settle();
        }

        // Pulses that run settle back
        Step settle()
        {
            if (!m_PcPulses && !m_HerePulses) {
                return {};
            }
            Step step;
            step.action = Action::Cancel;
            step.pcPulses = m_PcPulses;
            m_PcPulses = m_HerePulses = false;
            return step;
        }

        bool m_Known = false;
        int m_X = 0;
        int m_Y = 0;
        int m_Width = 0;
        int m_Height = 0;

        bool m_Pushing = false;
        std::uint32_t m_LastUpMs = 0;
        double m_PushPoints = 0;

        bool m_Asking = false;
        bool m_Asked = false;
        std::uint32_t m_LastAskMs = 0;
        int m_SinceAskX = 0;
        int m_SinceAskY = 0;

        bool m_Waiting = false;         // the PC said it's at the top: going up as the pulses end
        std::uint32_t m_ReleaseAtMs = 0;
        bool m_PcPulses = false;        // the PC pulses its pointer, as asked
        bool m_HerePulses = false;      // pulses over the picture instead
    };
}
