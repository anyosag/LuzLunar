#pragma once

#include <cstdint>

// [fork] SDL event types for the fork's modules, which wake the stream's event loop from worker
// threads and timers. SDL hands out SDL_USEREVENT itself at the first SDL_RegisterEvents() in a
// process, and Moonlight's session uses SDL_USEREVENT as is (frame-ready, rumble, ...). A module
// that got it would run on each of those events, and its own events would reach Moonlight as
// frame-ready ones (their code 0 is SDL_CODE_FRAME_READY). The choice is kept free of SDL so it can
// be unit tested on its own (tests/fork/forkevents_test.cpp).
namespace ForkEvents
{
    // registerOne: SDL_RegisterEvents(1). Takes the next type when it hands out userEvent.
    template<typename Register>
    uint32_t pickType(Register&& registerOne, uint32_t userEvent)
    {
        uint32_t type = registerOne();
        return type == userEvent ? registerOne() : type;
    }

    // A new event type that is never SDL_USEREVENT
    uint32_t registerType();
}
