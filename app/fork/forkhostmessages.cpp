#include "forkhostmessages.h"

#include <array>
#include <mutex>

#include <Limelight.h>

#include "luzcursor.h"

namespace
{
    std::mutex s_Mutex;
    std::array<ForkHostMessages::Handler, luzcursor::k_type_last - luzcursor::k_type_first + 1> s_Handlers;

    // moonlight-common-c's control receive thread (patch 0004)
    void onMessage(uint16_t type, const uint8_t* payload, int length)
    {
        if (type < luzcursor::k_type_first || type > luzcursor::k_type_last || length < 0) {
            return;
        }
        std::lock_guard<std::mutex> lock(s_Mutex);
        const ForkHostMessages::Handler& handler = s_Handlers[type - luzcursor::k_type_first];
        if (handler) {
            handler(payload, length);
        }
    }
}

void ForkHostMessages::setHandler(std::uint16_t type, Handler handler)
{
    if (type < luzcursor::k_type_first || type > luzcursor::k_type_last) {
        return;
    }
    std::lock_guard<std::mutex> lock(s_Mutex);
    s_Handlers[type - luzcursor::k_type_first] = std::move(handler);
}

void ForkHostMessages::connectionStarting()
{
    LiSetForkHostMessageCallback(onMessage);
}

void ForkHostMessages::connectionStopped()
{
    LiSetForkHostMessageCallback(nullptr);
}
