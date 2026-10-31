#include "cursorrules.h"

#include <algorithm>
#include <climits>
#include <cstdlib>

namespace CursorRules
{
    void Tracker::moved(int dx, int dy, std::uint32_t ms)
    {
        if (dx == 0 && dy == 0) {
            return;
        }
        m_SentX += dx;
        m_SentY += dy;
        m_LastMoveMs = ms;
        m_Moved = true;
        if (m_Known) {
            m_X = clampX(static_cast<long long>(m_X) + dx);
            m_Y = clampY(static_cast<long long>(m_Y) + dy);
        }
        m_History.push_back(Move { m_SentX, m_SentY, dx, dy });
        if (m_History.size() > k_History) {
            m_BaseSumX = m_History.front().sumX;
            m_BaseSumY = m_History.front().sumY;
            m_History.pop_front();
        }
    }

    Correction Tracker::state(const luzcursor::state_t& state, std::uint32_t ms)
    {
        if (state.width <= 0 || state.height <= 0) {
            return Correction::None;
        }
        m_Width = state.width;
        m_Height = state.height;
        m_Bounded = state.clip_right > state.clip_left && state.clip_bottom > state.clip_top;
        m_Left = state.clip_left;
        m_Top = state.clip_top;
        m_Right = state.clip_right;
        m_Bottom = state.clip_bottom;

        // The moves the PC had: up to the one whose sums are the state's. The sums only grow along
        // the history, and the PC's come in order, so the first is the one.
        std::size_t had = 0;
        bool found = state.sum_dx == m_BaseSumX && state.sum_dy == m_BaseSumY;
        for (std::size_t i = 0; !found && i < m_History.size(); i++) {
            if (m_History[i].sumX == state.sum_dx && m_History[i].sumY == state.sum_dy) {
                found = true;
                had = i + 1;
            }
        }

        if (!found) {
            // Moves this Mac didn't count, or one lost on its way: once every move has arrived, the
            // PC's sums become this Mac's
            if (m_Moved && ms - m_LastMoveMs < k_IdleMs) {
                return Correction::None;
            }
            m_SentX = state.sum_dx;
            m_SentY = state.sum_dy;
            m_BaseSumX = state.sum_dx;
            m_BaseSumY = state.sum_dy;
            m_History.clear();
            return correct(state.x, state.y, ms);
        }

        // From where the PC has it, the moves it didn't have yet, kept where Windows keeps the pointer
        int x = state.x;
        int y = state.y;
        for (std::size_t i = had; i < m_History.size(); i++) {
            x = clampX(static_cast<long long>(x) + m_History[i].dx);
            y = clampY(static_cast<long long>(y) + m_History[i].dy);
        }
        m_BaseSumX = state.sum_dx;
        m_BaseSumY = state.sum_dy;
        m_History.erase(m_History.begin(), m_History.begin() + static_cast<std::ptrdiff_t>(had));
        return correct(x, y, ms);
    }

    Correction Tracker::correct(int x, int y, std::uint32_t ms)
    {
        if (!m_Known) {
            m_Known = true;
            m_X = x;
            m_Y = y;
            m_Easing = false;
            return Correction::Snap;
        }
        int far = std::max(std::abs(x - m_X), std::abs(y - m_Y));
        if (far == 0) {
            return Correction::None;
        }
        if (far <= 1) {
            // A pixel: not worth an ease
            m_X = x;
            m_Y = y;
            return Correction::None;
        }
        if (far <= k_EasePx) {
            // From where it's drawn now, an ease that runs included
            double drawnX = this->x(ms);
            double drawnY = this->y(ms);
            m_X = x;
            m_Y = y;
            m_EaseX = drawnX - x;
            m_EaseY = drawnY - y;
            m_EaseStartMs = ms;
            m_Easing = true;
            return Correction::Ease;
        }
        m_X = x;
        m_Y = y;
        m_Easing = false;
        return Correction::Snap;
    }

    bool Tracker::easing(std::uint32_t ms) const
    {
        return m_Easing && ms - m_EaseStartMs < k_EaseMs;
    }

    double Tracker::x(std::uint32_t ms) const
    {
        if (!easing(ms)) {
            return m_X;
        }
        // Most of the way early: what's left goes as the cube of the time left
        double left = 1.0 - static_cast<double>(ms - m_EaseStartMs) / k_EaseMs;
        return m_X + m_EaseX * left * left * left;
    }

    double Tracker::y(std::uint32_t ms) const
    {
        if (!easing(ms)) {
            return m_Y;
        }
        double left = 1.0 - static_cast<double>(ms - m_EaseStartMs) / k_EaseMs;
        return m_Y + m_EaseY * left * left * left;
    }

    int Tracker::clampX(long long x) const
    {
        if (!m_Bounded) {
            return static_cast<int>(std::clamp<long long>(x, INT_MIN, INT_MAX));
        }
        return static_cast<int>(std::clamp<long long>(x, m_Left, static_cast<long long>(m_Right) - 1));
    }

    int Tracker::clampY(long long y) const
    {
        if (!m_Bounded) {
            return static_cast<int>(std::clamp<long long>(y, INT_MIN, INT_MAX));
        }
        return static_cast<int>(std::clamp<long long>(y, m_Top, static_cast<long long>(m_Bottom) - 1));
    }
}
