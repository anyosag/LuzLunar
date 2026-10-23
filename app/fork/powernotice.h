#pragma once

#include <functional>
#include <optional>

#include <QString>

#include "SDL_compat.h"

// [fork] The Low Power Mode message beside the notch (PowerRules::pill()): when a stream starts in
// Low Power Mode, and whenever Low Power Mode turns on during one. The notch bar isn't on screen yet
// when the stream starts, so a message is offered again every half second for up to 10 seconds,
// its text asked for each time, so it says what holds by then. ForkStreamExtensions owns it, on the
// SDL main thread.
class PowerNotice
{
public:
    PowerNotice();
    ~PowerNotice();

    PowerNotice(const PowerNotice&) = delete;
    PowerNotice& operator=(const PowerNotice&) = delete;

    // Shows a message; returns false while it can't yet (the notch bar's showNotice())
    void setMessageSink(std::function<bool(const QString&)> sink);

    // Offers the message from now on, in place of one still waiting; text says what it is when it's
    // shown: empty for nothing to say, nullopt for not known yet (asked again at the next try)
    void offer(std::function<std::optional<QString>()> text);

    void handleEvent(const SDL_Event& event);

private:
    void stop();

    std::function<std::optional<QString>()> m_Text;
    int m_Attempts = 0;
    SDL_TimerID m_Timer = 0;
    std::function<bool(const QString&)> m_MessageSink;
};
