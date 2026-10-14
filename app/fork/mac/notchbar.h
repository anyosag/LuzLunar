#pragma once

#include <memory>

#include <QString>
#include <QtGlobal>

struct SDL_Window;

// A bar beside the camera notch that shows the streamed app and live stream stats while the
// stream is fullscreen on a MacBook display with a notch. macOS draws a fullscreen app's window
// below the notch, so the bar is a separate non-activating panel over that strip.
//
// Messages appear beside the notch too, growing out of a blinking red dot: Moonlight's poor
// connection warning (through ForkStreamStats::reportConnectionStatus()) and clipboard messages
// (through showToast()). While the bar isn't on screen, they stay in Moonlight's status overlay.
class NotchBar
{
public:
    // Null where there's no bar to show, e.g. on other platforms
    static std::unique_ptr<NotchBar> create(SDL_Window* window, const QString& title);

    virtual ~NotchBar() = default;

    // Shows a message beside the notch for a few seconds. Returns false, showing nothing, while
    // the bar isn't on screen. Call on the main thread.
    virtual bool showToast(const QString& text) = 0;

protected:
    NotchBar() = default;
};

#ifndef Q_OS_DARWIN
inline std::unique_ptr<NotchBar> NotchBar::create(SDL_Window*, const QString&)
{
    return nullptr;
}
#endif
