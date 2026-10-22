#include "powernotice.h"

#include <QCoreApplication>

#include "forkevents.h"
#include "mac/macintegration.h"

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

PowerNotice::PowerNotice(int streamFps)
{
    eventType();
    if (streamFps <= 60 || !MacIntegration::lowPowerModeEnabled()) {
        return;
    }

    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Low Power Mode is on: macOS shows about 60 fps of this %d fps stream", streamFps);
    m_Message = QCoreApplication::translate("PowerNotice", "Low Power Mode holds this Mac to 60 fps. Turn it off for %1 fps.")
                    .arg(streamFps);
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

PowerNotice::~PowerNotice()
{
    stop();
}

void PowerNotice::setMessageSink(std::function<bool(const QString&)> sink)
{
    m_MessageSink = std::move(sink);
}

void PowerNotice::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType() || event.user.code != k_EventCode || m_Message.isEmpty()) {
        return;
    }
    if (m_MessageSink && m_MessageSink(m_Message)) {
        m_Message.clear();
        stop();
        return;
    }
    if (++m_Attempts >= k_MaxAttempts) {
        // The bar never came up (a windowed stream without one, say): the log has it
        m_Message.clear();
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
