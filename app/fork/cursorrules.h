#pragma once

#include <cstddef>
#include <cstdint>
#include <deque>
#include <string>

#include "luzcursor.h"

// [fork] The PC's pointer drawn by this Mac (forkcursor.*): where it is in Mac trackpad mode, which
// moves it by deltas, when the Mac draws it, and how big. Apollo's STATE says where Windows has it,
// with the moves it has injected so far added up (luzcursor.h), so the prediction is checked against
// the moves the PC had then, not the ones still on their way. Free of Qt, SDL and AppKit, so it's
// tested on its own (tests/fork/cursorrules_test.cpp).
namespace CursorRules
{
    // A correction up to this far eases in over k_EaseMs; a larger one is an app moving the pointer,
    // and the Mac's jumps as the PC's did
    const int k_EasePx = 24;
    const std::uint32_t k_EaseMs = 60;
    // A sum this Mac never sent (moves it didn't count) is taken as the PC's once no move has gone
    // for this long, as every move has arrived by then
    const std::uint32_t k_IdleMs = 250;
    // The moves kept to find the PC's sums among: seconds of them
    const std::size_t k_History = 1024;

    enum class Correction {
        None,   // the prediction was right, or there's nothing to go by yet
        Ease,   // off by a little: eases over to the PC's
        Snap,   // off by more, or the first: jumps to it
    };

    class Tracker
    {
    public:
        // A move sent to the PC (LiSendMouseMoveEvent()), in its pixels
        void moved(int dx, int dy, std::uint32_t ms);

        // A STATE: where the PC has the pointer with the moves it had. The moves sent since go on
        // from there, kept where Windows keeps the pointer (the state's clip rectangle).
        Correction state(const luzcursor::state_t& state, std::uint32_t ms);

        // Where to draw the hotspot now, in the PC display's pixels, with an ease that runs
        double x(std::uint32_t ms) const;
        double y(std::uint32_t ms) const;
        bool easing(std::uint32_t ms) const;

        // Where the moves put it, without the ease
        int predictedX() const { return m_X; }
        int predictedY() const { return m_Y; }
        bool known() const { return m_Known; }
        // The PC's display, as the last STATE had it; 0 before one
        int width() const { return m_Width; }
        int height() const { return m_Height; }

        // The moves sent so far, added up, and how many are kept
        std::int64_t sentX() const { return m_SentX; }
        std::int64_t sentY() const { return m_SentY; }
        std::size_t kept() const { return m_History.size(); }

    private:
        struct Move {
            std::int64_t sumX;  // the sums with this move
            std::int64_t sumY;
            int dx;
            int dy;
        };

        int clampX(long long x) const;
        int clampY(long long y) const;
        Correction correct(int x, int y, std::uint32_t ms);

        bool m_Known = false;
        int m_X = 0;
        int m_Y = 0;
        std::int64_t m_SentX = 0;
        std::int64_t m_SentY = 0;
        // Before the first move kept: the sums there, and where the PC had the pointer
        std::int64_t m_BaseSumX = 0;
        std::int64_t m_BaseSumY = 0;
        std::deque<Move> m_History;
        std::uint32_t m_LastMoveMs = 0;
        bool m_Moved = false;
        int m_Width = 0;
        int m_Height = 0;
        bool m_Bounded = false;
        int m_Left = 0;
        int m_Top = 0;
        int m_Right = 0;
        int m_Bottom = 0;
        // The ease: how far from the prediction the drawn pointer was as it began
        double m_EaseX = 0;
        double m_EaseY = 0;
        std::uint32_t m_EaseStartMs = 0;
        bool m_Easing = false;
    };

    // How the Mac draws the pointer in a mouse mode
    enum class Mode {
        None,           // it doesn't: the PC draws it (Mac mouse held for games, Windows touchpad)
        Cursor,         // remote desktop: the Mac's own cursor over the picture, in the PC's shape
        Sprite,         // Mac trackpad: drawn over the picture where the moves put the PC's pointer
    };

    inline Mode modeFor(bool absoluteMouse, bool macTrackpadMode)
    {
        if (macTrackpadMode) {
            return Mode::Sprite;
        }
        return absoluteMouse ? Mode::Cursor : Mode::None;
    }

    // The launch argument's value (luzCursor): "1" to draw it from the start, "host" to be able to
    // later while Apollo draws it for now, empty not to ask (the setting off, an Apollo that can't,
    // or a multi-display stream's helper window, whose display the PC draws it on)
    inline std::string launchValue(bool settingOn, bool apolloCanDraw, bool helperWindow, Mode mode)
    {
        if (!settingOn || !apolloCanDraw || helperWindow) {
            return std::string();
        }
        return mode == Mode::None ? "host" : "1";
    }

    struct Situation {
        Mode mode = Mode::None;        // as the stream's mouse is now, with the setting on and the PC able
        bool stateKnown = false;
        luzcursor::state_t state;
        bool shapeUsable = false;      // the state's shape arrived whole
        bool trackerKnown = false;     // Sprite: where the moves put it
        int x = 0;
        int y = 0;
        bool screenshotTools = false;  // macOS's ⇧⌘4 or ⇧⌘5 is up: a sprite would be in the picture taken
    };

    // Remote desktop: the Mac's cursor over the picture has the PC's shape
    inline bool cursorShows(const Situation& s)
    {
        return s.mode == Mode::Cursor && s.stateKnown && s.state.client_draws() && s.shapeUsable;
    }

    // Mac trackpad: the sprite shows where the moves put the PC's pointer, while it's on the display
    inline bool spriteShows(const Situation& s)
    {
        return s.mode == Mode::Sprite && s.stateKnown && s.state.client_draws() && s.shapeUsable && s.trackerKnown &&
               s.x >= 0 && s.y >= 0 && s.x < s.state.width && s.y < s.state.height && !s.screenshotTools;
    }

    // The Mac asks the PC to draw it, or to let it: it draws in this mode
    inline bool macDraws(Mode mode)
    {
        return mode != Mode::None;
    }

    // As big as the picture shows it: the picture's width in points over the PC display's in pixels
    inline double pointsPerPixel(double pictureWidthPoints, int displayWidthPixels)
    {
        return displayWidthPixels > 0 && pictureWidthPoints > 0 ? pictureWidthPoints / displayWidthPixels : 0;
    }

    // In the window's points, from the PC display's pixels: the picture's rectangle maps the display
    struct Point {
        double x = 0;
        double y = 0;
    };

    struct Rect {
        double x = 0;
        double y = 0;
        double w = 0;
        double h = 0;
    };

    // Where the PC display is in the picture: Apollo fits it in the stream's frame keeping its shape,
    // with bars on two sides if they differ (its make_port())
    inline Rect displayInPicture(const Rect& picture, int displayWidth, int displayHeight)
    {
        if (displayWidth <= 0 || displayHeight <= 0 || picture.w <= 0 || picture.h <= 0) {
            return picture;
        }
        double scale = picture.w / displayWidth < picture.h / displayHeight ? picture.w / displayWidth : picture.h / displayHeight;
        Rect fitted;
        fitted.w = displayWidth * scale;
        fitted.h = displayHeight * scale;
        fitted.x = picture.x + (picture.w - fitted.w) / 2;
        fitted.y = picture.y + (picture.h - fitted.h) / 2;
        return fitted;
    }

    inline Point inWindow(double pcX, double pcY, double pictureX, double pictureY, double pictureWidth, double pictureHeight,
                          int displayWidth, int displayHeight)
    {
        Point point;
        if (displayWidth <= 0 || displayHeight <= 0) {
            return point;
        }
        point.x = pictureX + pcX * pictureWidth / displayWidth;
        point.y = pictureY + pcY * pictureHeight / displayHeight;
        return point;
    }
}
