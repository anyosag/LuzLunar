#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>

// [fork] Reaching the notch bar with Mac trackpad mode's pointer. That pointer is the PC's, drawn in
// the picture, and Windows keeps it on the PC's screen, so it can't go up into the bar above the
// picture by itself. These are the rules for when the Mac's own pointer takes over: the PC's pointer
// is followed by the moves sent to it (Windows moves it a pixel a count in Mac trackpad mode), and
// once it has been pushed up against the top for a moment, the PC is asked where it is
// (GET /actions/cursor), as an app may have moved it since. Only when the PC says it's at the top
// does the Mac's pointer go up into the bar. Free of Qt, so tests can build it alone
// (tests/fork/barreach_test.cpp); ForkBarReach (forkbarreach.h) asks the PC.
namespace BarReach
{
    // How long and how far the pointer is pushed up against the top before the PC is asked, so
    // throwing it up at a tab or a window's close button doesn't land in the bar
    const std::uint32_t k_PushMs = 250;
    const double k_PushPoints = 24;     // of the Mac's pointer motion, after macOS's acceleration
    // A push ends when nothing has pushed up for this long, or the pointer goes down
    const std::uint32_t k_PauseMs = 150;
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
    };

    class Tracker
    {
    public:
        // A move sent to the PC (in its pixels) and the Mac's pointer motion it came from (in points,
        // up negative), with a button held or not. True to ask the PC where its pointer is now.
        bool moved(int dx, int dy, double dxPoints, double dyPoints, bool buttonDown, std::uint32_t ms)
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

            if (m_Pushing && ms - m_LastUpMs > k_PauseMs) {
                m_Pushing = false;
            }
            if (buttonDown || dy > k_DownPx || !atTop) {
                // Dragging, as a window up to the top to fill the screen, or not at the top
                m_Pushing = false;
            }
            else if (dyPoints < 0 && -dyPoints >= std::fabs(dxPoints)) {
                // Mostly up: sliding along the top, as across tabs, doesn't push
                if (!m_Pushing) {
                    m_Pushing = true;
                    m_PushStartMs = ms;
                    m_PushPoints = 0;
                }
                m_PushPoints += -dyPoints;
                m_LastUpMs = ms;
            }

            if (!m_Pushing || m_Asking || ms - m_PushStartMs < k_PushMs || m_PushPoints < k_PushPoints) {
                return false;
            }
            if (m_Asked && ms - m_LastAskMs < k_AskGapMs) {
                return false;
            }
            m_Asking = true;
            m_Asked = true;
            m_LastAskMs = ms;
            m_SinceAskX = 0;
            m_SinceAskY = 0;
            return true;
        }

        // The PC's answer to the question asked. Where the Mac's pointer goes into the bar, from 0 at
        // the picture's left edge to 1 at its right, when the PC's pointer is at the top and still
        // pushed; none otherwise.
        std::optional<double> answered(const Cursor& cursor, std::uint32_t ms)
        {
            m_Asking = false;
            bool onDisplay = cursor.width > 0 && cursor.height > 0 && cursor.x >= 0 && cursor.x < cursor.width &&
                             cursor.y < cursor.height;
            if (!onDisplay) {
                // On another display beside this one: nothing to follow
                m_Known = false;
                m_Pushing = false;
                return std::nullopt;
            }

            // The moves sent since it was asked came after
            m_Known = true;
            m_Width = cursor.width;
            m_Height = cursor.height;
            m_X = std::clamp(cursor.x + m_SinceAskX, 0, m_Width - 1);
            m_Y = std::clamp(cursor.y + m_SinceAskY, 0, m_Height - 1);

            bool pushed = m_Pushing && ms - m_LastUpMs <= k_PauseMs;
            if (cursor.y > 0 || m_Y > 0) {
                // Lower than it seemed: a push starts again once it's at the top
                m_Pushing = false;
                return std::nullopt;
            }
            if (!cursor.shown || !pushed) {
                return std::nullopt;
            }
            m_Pushing = false;
            return (cursor.x + 0.5) / cursor.width;
        }

        // The question went unanswered; the next push asks again
        void unanswered()
        {
            m_Asking = false;
        }

        // The PC's pointer was put there, as fractions of the picture (the Mac's came back down into it)
        void placed(double fx, double fy)
        {
            m_Pushing = false;
            if (m_Width <= 0 || m_Height <= 0) {
                return;
            }
            m_Known = true;
            m_X = std::clamp(static_cast<int>(fx * m_Width), 0, m_Width - 1);
            m_Y = std::clamp(static_cast<int>(fy * m_Height), 0, m_Height - 1);
        }

        // Where the PC's pointer is isn't known any more: the stream stopped moving it, and something
        // else may have
        void forget()
        {
            m_Known = false;
            m_Pushing = false;
        }

        bool known() const { return m_Known; }
        int x() const { return m_X; }
        int y() const { return m_Y; }
        bool asking() const { return m_Asking; }

    private:
        bool m_Known = false;
        int m_X = 0;
        int m_Y = 0;
        int m_Width = 0;
        int m_Height = 0;

        bool m_Pushing = false;
        std::uint32_t m_PushStartMs = 0;
        std::uint32_t m_LastUpMs = 0;
        double m_PushPoints = 0;

        bool m_Asking = false;
        bool m_Asked = false;
        std::uint32_t m_LastAskMs = 0;
        int m_SinceAskX = 0;
        int m_SinceAskY = 0;
    };
}
