// Tests for app/fork/forkevents.h: the fork's SDL event types are never SDL_USEREVENT, which
// Moonlight's session uses as is. A standalone program for the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/forkevents_test.cpp

#include "fork/forkevents.h"

#include <cstdio>

using namespace ForkEvents;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

// SDL_RegisterEvents(1) as SDL 2 does it: the next type from SDL_USEREVENT on, -1 past the last
struct Registrar
{
    uint32_t next = 0x8000;
    uint32_t operator()()
    {
        return next <= 0xFFFF ? next++ : 0xFFFFFFFF;
    }
};

int main()
{
    const uint32_t userEvent = 0x8000;

    // The first registration in the process: SDL_USEREVENT stays Moonlight's
    Registrar sdl;
    CHECK(pickType(sdl, userEvent) == 0x8001);
    // Later ones take the next type
    CHECK(pickType(sdl, userEvent) == 0x8002);
    CHECK(pickType(sdl, userEvent) == 0x8003);

    // After a registration elsewhere took SDL_USEREVENT: nothing to skip
    Registrar after;
    after.next = 0x8005;
    CHECK(pickType(after, userEvent) == 0x8005);

    // SDL out of types: its failure passes through, matching no event
    Registrar full;
    full.next = 0x10000;
    CHECK(pickType(full, userEvent) == 0xFFFFFFFF);

    if (s_Failures) {
        std::printf("forkevents: %d failures\n", s_Failures);
        return 1;
    }
    std::printf("forkevents: all tests passed\n");
    return 0;
}
