#include "forkevents.h"

#include "SDL_compat.h"

uint32_t ForkEvents::registerType()
{
    return pickType([] { return SDL_RegisterEvents(1); }, SDL_USEREVENT);
}
