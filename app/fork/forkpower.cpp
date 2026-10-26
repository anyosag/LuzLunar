#include "forkpower.h"

#include <QtGlobal>

#include "forkevents.h"

Uint32 ForkPower::changeEventType()
{
    static Uint32 type = ForkEvents::registerType();
    return type;
}

bool ForkPower::isChangeEvent(const SDL_Event& event)
{
    return event.type == changeEventType();
}

#ifndef Q_OS_DARWIN

struct ForkPower::Impl
{
};

ForkPower::ForkPower()
{
}

ForkPower::~ForkPower()
{
}

PowerRules::Reading ForkPower::reading() const
{
    return PowerRules::Reading();
}

bool ForkPower::lowPowerMode() const
{
    return false;
}

int ForkPower::startLevel() const
{
    return -1;
}

double ForkPower::minutesSinceStart() const
{
    return 0;
}

#endif
