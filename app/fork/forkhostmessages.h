#pragma once

#include <cstdint>
#include <functional>

// [fork] The control messages anyosag/Apollo sends of its own, types 0x4C00 to 0x4CFF (luzcursor.h
// has the first ones: the PC's pointer), which moonlight-common-c hands over with LuzLunar's patch
// 0004 (patches/moonlight-common-c/). Session sets the patch's callback around each connection;
// each module registers a handler for its types.
namespace ForkHostMessages
{
    // Called on moonlight-common-c's control receive thread, in the order Apollo sent the messages;
    // payload is what follows the type, valid only during the call. Keep it short: the control
    // stream waits meanwhile.
    using Handler = std::function<void(const std::uint8_t* payload, int length)>;

    // Any thread. An empty handler removes it. Not from inside a handler.
    void setHandler(std::uint16_t type, Handler handler);

    // Session: before LiStartConnection(), and after LiStopConnection()
    void connectionStarting();
    void connectionStopped();
}
