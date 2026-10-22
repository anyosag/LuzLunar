#pragma once

#include <functional>

#include <QString>

#include "SDL_compat.h"

// [fork] Says beside the notch when a stream asks for more than 60 fps while macOS's Low Power
// Mode holds the screen to about 60 fps. The notch bar isn't on screen yet when the stream
// starts, so the message is offered again every half second for up to 10 seconds; without a
// bar it's only logged. ForkStreamExtensions owns it, on the SDL main thread.
class PowerNotice
{
public:
    // Checks Low Power Mode now; does nothing at 60 fps or less
    explicit PowerNotice(int streamFps);
    ~PowerNotice();

    PowerNotice(const PowerNotice&) = delete;
    PowerNotice& operator=(const PowerNotice&) = delete;

    // Shows a message; returns false while it can't yet (the notch bar's showToast())
    void setMessageSink(std::function<bool(const QString&)> sink);

    void handleEvent(const SDL_Event& event);

private:
    void stop();

    QString m_Message;
    int m_Attempts = 0;
    SDL_TimerID m_Timer = 0;
    std::function<bool(const QString&)> m_MessageSink;
};
