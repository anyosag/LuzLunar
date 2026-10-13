#pragma once

#include <memory>

#include <QString>
#include <QtGlobal>

struct SDL_Window;

// A bar beside the camera notch that shows the streamed app and live stream stats while the
// stream is fullscreen on a MacBook display with a notch. macOS draws a fullscreen app's window
// below the notch, so the bar is a separate non-activating panel over that strip.
class NotchBar
{
public:
    // Null where there's no bar to show, e.g. on other platforms
    static std::unique_ptr<NotchBar> create(SDL_Window* window, const QString& title);

    virtual ~NotchBar() = default;

protected:
    NotchBar() = default;
};

#ifndef Q_OS_DARWIN
inline std::unique_ptr<NotchBar> NotchBar::create(SDL_Window*, const QString&)
{
    return nullptr;
}
#endif
