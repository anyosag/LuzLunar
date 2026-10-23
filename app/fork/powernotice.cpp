#include "powernotice.h"

#include "forkevents.h"

namespace
{
    const Uint32 k_RetryMs = 500;
    // 10 seconds of tries
    const int k_MaxAttempts = 20;

    // Its own code, so the event can't pass for one of Moonlight's
    const Sint32 k_EventCode = 0x4c504d;

    Uint32 eventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }
}

PowerNotice::PowerNotice()
{
    eventType();
}

PowerNotice::~PowerNotice()
{
    stop();
}

void PowerNotice::setMessageSink(std::function<bool(const Notice&)> sink)
{
    m_MessageSink = std::move(sink);
}

void PowerNotice::offer(std::function<std::optional<Notice>()> text)
{
    m_Text = std::move(text);
    m_Attempts = 0;
    if (m_Timer != 0 || !m_Text) {
        return;
    }
    m_Timer = SDL_AddTimer(k_RetryMs,
                           [](Uint32 interval, void*) -> Uint32 {
                               SDL_Event event = {};
                               event.type = eventType();
                               event.user.code = k_EventCode;
                               SDL_PushEvent(&event);
                               return interval;
                           },
                           nullptr);
}

void PowerNotice::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType() || event.user.code != k_EventCode || !m_Text) {
        return;
    }
    std::optional<Notice> notice = m_Text();
    if ((notice && (notice->text.isEmpty() || (m_MessageSink && m_MessageSink(*notice)))) || ++m_Attempts >= k_MaxAttempts) {
        // Nothing to say by now, said, or the bar never came up (a windowed stream without one, say)
        m_Text = nullptr;
        stop();
    }
}

void PowerNotice::stop()
{
    if (m_Timer != 0) {
        SDL_RemoveTimer(m_Timer);
        m_Timer = 0;
    }
}
