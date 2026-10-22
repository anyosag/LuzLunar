#pragma once

#include <QtGlobal>

struct SDL_Window;

// [fork] What macOS says about a window's screen, for where SDL can't tell. A ProMotion screen
// has no fixed refresh rate, so SDL can report 0 Hz for it, and Moonlight then assumes 60 Hz:
// after a renderer reset that turns V-Sync off for a 120 fps stream. After Nonary's
// moonlight-qt (app/streaming/video/ffmpeg-renderers/macdisplaytiming.mm).
namespace DisplayTiming
{
#ifdef Q_OS_DARWIN
    // The window's screen's highest refresh rate (NSScreen.maximumFramesPerSecond, macOS 12+),
    // or 0 if it can't tell. Main thread only.
    int maximumRefreshRate(SDL_Window* window);
#else
    inline int maximumRefreshRate(SDL_Window*) { return 0; }
#endif
}
