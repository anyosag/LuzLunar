// Unit tests for app/fork/powerrules.h, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/powerrules_test.cpp
#include "fork/powerrules.h"

#include <cstdio>

using namespace PowerRules;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

static Reading onBattery(int level)
{
    Reading reading;
    reading.present = true;
    reading.level = level;
    return reading;
}

static void testGlyph()
{
    // The canvas's states
    Glyph g = glyph(onBattery(76), false);
    CHECK(g.fill == Fill::White && !g.bolt);
    CHECK(std::fabs(g.fillWidth - 14.136) < 0.001);
    CHECK(glyph(onBattery(8), false).fill == Fill::Red);
    CHECK(glyph(onBattery(10), false).fill == Fill::Red);
    CHECK(glyph(onBattery(11), false).fill == Fill::White);
    // Low Power Mode wins over low
    CHECK(glyph(onBattery(8), true).fill == Fill::Yellow);
    CHECK(glyph(onBattery(42), true).fill == Fill::Yellow);

    Reading charging = onBattery(8);
    charging.onAC = true;
    charging.charging = true;
    g = glyph(charging, false);
    CHECK(g.fill == Fill::White && g.bolt);     // not red on a power adapter

    // An empty battery still shows a sliver
    CHECK(glyph(onBattery(0), false).fillWidth == 1.4);
    CHECK(glyph(onBattery(100), false).fillWidth == 18.6);
}

static void testBranch()
{
    Reading reading = onBattery(76);
    CHECK(branch(reading) == Branch::OnBattery);
    reading.onAC = true;
    reading.charging = true;
    CHECK(branch(reading) == Branch::Charging);
    reading.charging = false;
    reading.charged = true;
    CHECK(branch(reading) == Branch::Charged);
    // Held at 80% by Optimized Battery Charging: not charged, not charging
    reading.charged = false;
    CHECK(branch(reading) == Branch::NotCharging);
}

static void testRates()
{
    // The canvas's: 8 W from a 70 Wh battery at 76%
    Reading reading = onBattery(76);
    reading.watts = 8.0;
    reading.capacityWh = 70;
    CHECK(std::lround(percentPerHour(reading)) == 11);
    CHECK(minutesLeft(reading) == 399);
    CHECK(duration(minutesLeft(reading)) == "6 h 40 min");

    // The watts first, as "% an hour" counts them; macOS's estimate without them
    reading.minutesToEmpty = 250;
    CHECK(minutesLeft(reading) == 399);
    Reading estimate = onBattery(76);
    estimate.minutesToEmpty = 250;
    CHECK(minutesLeft(estimate) == 250);
    CHECK(duration(250) == "4 h 10 min");

    // Without the watts, the level over the time left
    Reading noWatts = onBattery(50);
    noWatts.minutesToEmpty = 300;
    CHECK(std::lround(percentPerHour(noWatts)) == 10);
    // Nothing known
    CHECK(!known(percentPerHour(onBattery(50))));
    CHECK(minutesLeft(onBattery(50)) == -1);

    // Not on AC
    Reading ac = reading;
    ac.onAC = true;
    CHECK(minutesLeft(ac) == -1 && !known(percentPerHour(ac)));
}

static void testTexts()
{
    CHECK(duration(45) == "45 min");
    CHECK(duration(43) == "45 min");
    CHECK(duration(65) == "1 h 5 min");
    CHECK(duration(300) == "5 h");
    CHECK(duration(2) == "5 min");
    CHECK(duration(0) == "0 min");
    CHECK(wattsText(8.04) == "8.0 W");

    CHECK(sinceStart(85, 76, 48.7) == "−9% in 48 min");
    CHECK(sinceStart(50, 53, 12) == "+3% in 12 min");
    CHECK(sinceStart(50, 50, 2) == "0% in 2 min");
    CHECK(sinceStart(90, 70, 95) == "−20% in 1 h 35 min");
}

static void testSaver()
{
    // Follows Low Power Mode
    Saver saver(false);
    CHECK(!saver.on());
    CHECK(saver.setLowPowerMode(true) && saver.on());

    // Turned off by hand: until Low Power Mode changes
    saver.toggle();
    CHECK(!saver.on());
    CHECK(!saver.setLowPowerMode(true));    // no change, still off
    CHECK(!saver.on());
    CHECK(!saver.setLowPowerMode(false));   // forgotten, and off with Low Power Mode anyway
    CHECK(!saver.on());
    CHECK(saver.setLowPowerMode(true) && saver.on());

    // Turned on by hand without Low Power Mode, forgotten when it comes and goes
    Saver manual(false);
    manual.toggle();
    CHECK(manual.on());
    CHECK(!manual.setLowPowerMode(true) && manual.on());
    CHECK(manual.setLowPowerMode(false) && !manual.on());

    // Kept across a reconnect while Low Power Mode holds
    Saver off(true);
    off.toggle();
    CHECK(off.manual() == std::optional<bool>(false));
    Saver next(true);
    next.restore(off.manual(), off.lowPowerMode());
    CHECK(!next.on());
    CHECK(!next.setLowPowerMode(false) && !next.on() && !next.manual());   // forgotten, off either way
    // Not once it changed in between
    Saver changed(false);
    changed.restore(off.manual(), off.lowPowerMode());
    CHECK(!changed.manual() && !changed.on());
    // Nothing chosen by hand
    Saver none(true);
    none.restore(std::nullopt, true);
    CHECK(none.on() && !none.manual());
}

static void testPill()
{
    // The canvas's truth table
    CHECK(pill(false, false, 120) == Pill::Hidden);
    CHECK(pill(false, true, 120) == Pill::Hidden);
    CHECK(pill(true, true, 120) == Pill::Capped);
    CHECK(pill(true, true, 60) == Pill::Capped);
    CHECK(pill(true, false, 120) == Pill::HoldsTo60);
    CHECK(pill(true, false, 60) == Pill::Hidden);
}

int main()
{
    testGlyph();
    testBranch();
    testRates();
    testTexts();
    testSaver();
    testPill();

    if (s_Failures == 0) {
        std::printf("powerrules: all tests passed\n");
        return 0;
    }
    std::printf("powerrules: %d failure(s)\n", s_Failures);
    return 1;
}
