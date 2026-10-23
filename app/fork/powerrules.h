#pragma once

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <optional>
#include <string>

// [fork] The Mac's battery during a stream, for the notch bar's Battery item and menu, Stream
// Battery Saver and the Low Power Mode message beside the notch. ForkPower (forkpower.h,
// mac/power_mac.mm) reads the battery; this decides what it shows. Free of Qt and AppKit, so tests
// can build it alone (tests/fork/powerrules_test.cpp).
namespace PowerRules
{
    inline double unknown()
    {
        return std::numeric_limits<double>::quiet_NaN();
    }

    inline bool known(double value)
    {
        return !std::isnan(value);
    }

    // What the power sources say now
    struct Reading {
        bool present = false;       // the Mac has a battery
        bool onAC = false;          // on a power adapter
        bool charging = false;
        bool charged = false;       // full, on a power adapter
        int level = 0;              // percent
        int minutesToFull = -1;     // macOS's estimates; -1 while it has none
        int minutesToEmpty = -1;
        double watts = unknown();   // what the Mac draws: from the battery, or on AC from the adapter
        double capacityWh = unknown();  // the battery's full charge
    };

    // The bar's battery, as macOS's menu bar draws it: 27 by 13, its fill 18.6 wide when full
    enum class Fill {
        White,
        Red,        // 10% or less, on battery
        Yellow,     // Low Power Mode, whatever the level
    };

    struct Glyph {
        Fill fill = Fill::White;
        bool bolt = false;          // on a power adapter, charging or charged
        double fillWidth = 0;
    };

    inline Glyph glyph(const Reading& reading, bool lowPowerMode)
    {
        Glyph result;
        int level = std::max(0, std::min(reading.level, 100));
        result.fill = lowPowerMode ? Fill::Yellow : (!reading.onAC && level <= 10 ? Fill::Red : Fill::White);
        result.bolt = reading.onAC;
        result.fillWidth = std::max(1.4, 18.6 * level / 100.0);
        return result;
    }

    // The menu's "While streaming"
    enum class Branch {
        OnBattery,      // the watts, % an hour, time left, this stream so far
        Charging,       // "Full in …", what the Mac draws
        Charged,        // full on a power adapter: what the Mac draws
        NotCharging,    // on a power adapter, held short of full (Optimized Battery Charging, a weak adapter)
    };

    inline Branch branch(const Reading& reading)
    {
        if (!reading.onAC) {
            return Branch::OnBattery;
        }
        if (reading.charging) {
            return Branch::Charging;
        }
        return reading.charged ? Branch::Charged : Branch::NotCharging;
    }

    // Minutes left on battery at this rate: what's left over the watts, as "% an hour" counts it, else
    // macOS's estimate; -1
    inline int minutesLeft(const Reading& reading)
    {
        if (reading.onAC) {
            return -1;
        }
        if (known(reading.watts) && known(reading.capacityWh) && reading.watts > 0.1) {
            return static_cast<int>(std::lround(reading.level / 100.0 * reading.capacityWh / reading.watts * 60));
        }
        if (reading.minutesToEmpty > 0) {
            return reading.minutesToEmpty;
        }
        return -1;
    }

    // The battery used an hour, in percent: the watts over the battery's capacity, else the level over
    // the hours left; NaN
    inline double percentPerHour(const Reading& reading)
    {
        if (reading.onAC) {
            return unknown();
        }
        if (known(reading.watts) && known(reading.capacityWh) && reading.capacityWh > 1) {
            return reading.watts / reading.capacityWh * 100;
        }
        int left = minutesLeft(reading);
        if (left > 0) {
            return reading.level / (left / 60.0);
        }
        return unknown();
    }

    // "4 h 10 min", "45 min", "5 h": to 5 minutes, as the canvas does
    inline std::string duration(int minutes)
    {
        char text[32];
        int rounded = static_cast<int>(std::lround(std::max(minutes, 0) / 5.0)) * 5;
        if (minutes > 0 && rounded == 0) {
            rounded = 5;
        }
        int h = rounded / 60;
        int m = rounded % 60;
        if (h == 0) {
            std::snprintf(text, sizeof(text), "%d min", m);
        }
        else if (m == 0) {
            std::snprintf(text, sizeof(text), "%d h", h);
        }
        else {
            std::snprintf(text, sizeof(text), "%d h %d min", h, m);
        }
        return text;
    }

    // "8.0 W"
    inline std::string wattsText(double watts)
    {
        char text[24];
        std::snprintf(text, sizeof(text), "%.1f W", watts);
        return text;
    }

    // "−9% in 48 min", "+3% in 12 min", "0% in 2 min": the level since the stream started
    inline std::string sinceStart(int startLevel, int level, double minutes)
    {
        char text[48];
        int change = level - startLevel;
        int whole = static_cast<int>(std::max(minutes, 0.0));
        std::string in = whole < 60 ? std::to_string(whole) + " min" : duration(whole);
        if (change < 0) {
            std::snprintf(text, sizeof(text), "−%d%% in %s", -change, in.c_str());
        }
        else if (change > 0) {
            std::snprintf(text, sizeof(text), "+%d%% in %s", change, in.c_str());
        }
        else {
            std::snprintf(text, sizeof(text), "0%% in %s", in.c_str());
        }
        return text;
    }

    // Stream Battery Saver caps the bitrate at this, without reconnecting
    const int k_SaverKbps = 10000;

    // Stream Battery Saver follows Low Power Mode, and a choice by hand holds only until Low Power
    // Mode changes: turning it off isn't remembered
    class Saver
    {
    public:
        explicit Saver(bool lowPowerMode)
            : m_LowPowerMode(lowPowerMode)
        {
        }

        // Low Power Mode now; true when that changed whether the saver is on
        bool setLowPowerMode(bool lowPowerMode)
        {
            bool was = on();
            if (lowPowerMode != m_LowPowerMode) {
                m_LowPowerMode = lowPowerMode;
                m_Manual.reset();
            }
            return on() != was;
        }

        void toggle()
        {
            m_Manual = !on();
        }

        bool on() const
        {
            return m_Manual.value_or(m_LowPowerMode);
        }

        bool lowPowerMode() const { return m_LowPowerMode; }

    private:
        bool m_LowPowerMode;
        std::optional<bool> m_Manual;
    };

    // The message beside the notch
    enum class Pill {
        Hidden,
        Capped,     // "Low Power Mode: bitrate capped at 10 Mb/s."
        HoldsTo60,  // "Low Power Mode holds the screen to 60 fps."
    };

    // capped: the saver holds the stream's bitrate down now (on, and the PC changes it live)
    inline Pill pill(bool lowPowerMode, bool capped, int streamFps)
    {
        if (!lowPowerMode) {
            return Pill::Hidden;
        }
        if (capped) {
            return Pill::Capped;
        }
        return streamFps > 60 ? Pill::HoldsTo60 : Pill::Hidden;
    }
}
