#pragma once

#include <memory>

#include "SDL_compat.h"
#include "powerrules.h"

// [fork] The Mac's battery and Low Power Mode during a stream (mac/power_mac.mm), for the notch
// bar's Battery item and menu and Stream Battery Saver; powerrules.h decides what they show. macOS
// says when a power source or Low Power Mode changes, and it looks again every 10 s for the watts,
// off the main thread. Each change reaches the stream's event loop as an SDL event (isChangeEvent()),
// as the Qt event loop is paused while streaming. ForkStreamExtensions owns it for the stream, on
// the main thread. Elsewhere than macOS it says there's no battery.
class ForkPower
{
public:
    ForkPower();
    ~ForkPower();

    ForkPower(const ForkPower&) = delete;
    ForkPower& operator=(const ForkPower&) = delete;

    // What the power sources said last, the watts averaged over the last minute
    PowerRules::Reading reading() const;
    bool lowPowerMode() const;

    // The battery's level when the stream started, and how long ago that was; -1 without a battery
    int startLevel() const;
    double minutesSinceStart() const;

    static Uint32 changeEventType();
    static bool isChangeEvent(const SDL_Event& event);

    struct Impl;

private:
    std::unique_ptr<Impl> m_Impl;
};
