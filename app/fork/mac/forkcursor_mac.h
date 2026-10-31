#pragma once

#include <memory>

#include "SDL_compat.h"
#include "fork/luzcursor.h"

// [fork] AppKit's side of the PC's pointer drawn by this Mac (forkcursor.*). Remote desktop mode:
// the PC's shape as the Mac's own cursor, an NSCursor made from all of the shape's pixels and sized
// in points, as SDL's colour cursors aren't (a pixel a point: twice too big on Retina). Mac trackpad
// mode: a sprite on a click-through panel just above the stream window, moved with each move.
// Inverting pixels, as Windows' I-beam has, are drawn white with a dark outline
// (luzcursor::display_pixels()). Main thread. macOS only.
namespace ForkCursorMac
{
    // The PC's shape as an SDL cursor for SDL_SetCursor(), pointsPerPixel points a pixel; null if it
    // couldn't be made. SDL_FreeCursor() frees it.
    SDL_Cursor* createCursor(const luzcursor::shape_t& shape, double pointsPerPixel);

    class Sprite
    {
    public:
        explicit Sprite(SDL_Window* window);
        ~Sprite();

        Sprite(const Sprite&) = delete;
        Sprite& operator=(const Sprite&) = delete;

        // The shape it draws, pointsPerPixel points a pixel
        void setShape(const std::shared_ptr<const luzcursor::shape_t>& shape, double pointsPerPixel);

        // Shown with its hotspot at x, y of the stream window, in points from its content's top-left
        void show(double x, double y);
        void hide();

        // The notch bar's pulses, on the PC's own shape: larger and in the bar's accent, count times,
        // as Apollo draws them (its cursor_pulse.h); with Reduce Motion, the color only
        void pulse(int count, bool reduceMotion);
        void settle();

        struct Impl;

    private:
        Impl* m_Impl;
    };
}
