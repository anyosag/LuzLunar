#include "fork/forkpower.h"

#include <chrono>
#include <cmath>
#include <deque>
#include <mutex>

#import <Foundation/Foundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>

// [fork] ForkPower on macOS. The level, the power adapter, charging, macOS's time estimates and the
// battery's Voltage and Current come from IOKit's power sources (IOPSCopyPowerSourcesInfo, keys in
// IOPSKeys.h). Where the power source leaves out Voltage or Current, and for the battery's capacity,
// the battery's IORegistry entry, which isn't documented (AppleSmartBattery: Voltage, InstantAmperage or Amperage,
// AppleRawMaxCapacity or NominalChargeCapacity, and PowerTelemetryData's SystemPowerIn on a power
// adapter). Where none of them is there, the menu leaves out what needs it.

namespace
{
    const int64_t k_RefreshNs = 10 * static_cast<int64_t>(NSEC_PER_SEC);
    // A minute of the 10 s readings
    const size_t k_WattsSamples = 6;

    bool number(CFDictionaryRef dictionary, CFStringRef key, double* value)
    {
        CFTypeRef ref = dictionary != nullptr ? CFDictionaryGetValue(dictionary, key) : nullptr;
        if (ref == nullptr || CFGetTypeID(ref) != CFNumberGetTypeID()) {
            return false;
        }
        // As a signed integer first: the battery's currents are signed, some stored in 64 bits
        int64_t integer = 0;
        if (!CFNumberIsFloatType(static_cast<CFNumberRef>(ref)) &&
                CFNumberGetValue(static_cast<CFNumberRef>(ref), kCFNumberSInt64Type, &integer)) {
            *value = static_cast<double>(integer);
            return true;
        }
        return CFNumberGetValue(static_cast<CFNumberRef>(ref), kCFNumberDoubleType, value);
    }

    bool boolean(CFDictionaryRef dictionary, CFStringRef key, bool* value)
    {
        CFTypeRef ref = dictionary != nullptr ? CFDictionaryGetValue(dictionary, key) : nullptr;
        if (ref == nullptr || CFGetTypeID(ref) != CFBooleanGetTypeID()) {
            return false;
        }
        *value = CFBooleanGetValue(static_cast<CFBooleanRef>(ref));
        return true;
    }

    bool sameString(CFDictionaryRef dictionary, CFStringRef key, CFStringRef expected)
    {
        CFTypeRef ref = dictionary != nullptr ? CFDictionaryGetValue(dictionary, key) : nullptr;
        return ref != nullptr && CFGetTypeID(ref) == CFStringGetTypeID() &&
               CFStringCompare(static_cast<CFStringRef>(ref), expected, 0) == kCFCompareEqualTo;
    }

    // What the battery's IORegistry entry adds: watts and capacity, where it has them
    struct Registry {
        double voltageMv = PowerRules::unknown();
        double amperageMa = PowerRules::unknown();
        double capacityMah = PowerRules::unknown();
        double systemPowerInMw = PowerRules::unknown();
    };

    Registry readRegistry()
    {
        Registry registry;
        // MACH_PORT_NULL is the default main port (kIOMainPortDefault, which needs macOS 12)
        io_service_t battery = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("AppleSmartBattery"));
        if (battery == IO_OBJECT_NULL) {
            return registry;
        }
        CFMutableDictionaryRef properties = nullptr;
        if (IORegistryEntryCreateCFProperties(battery, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS && properties != nullptr) {
            double value;
            if (number(properties, CFSTR("Voltage"), &value) && value > 0) {
                registry.voltageMv = value;
            }
            if (number(properties, CFSTR("InstantAmperage"), &value) || number(properties, CFSTR("Amperage"), &value)) {
                registry.amperageMa = value;
            }
            if ((number(properties, CFSTR("AppleRawMaxCapacity"), &value) || number(properties, CFSTR("NominalChargeCapacity"), &value)) &&
                    value > 100) {
                registry.capacityMah = value;
            }
            CFTypeRef telemetry = CFDictionaryGetValue(properties, CFSTR("PowerTelemetryData"));
            if (telemetry != nullptr && CFGetTypeID(telemetry) == CFDictionaryGetTypeID() &&
                    number(static_cast<CFDictionaryRef>(telemetry), CFSTR("SystemPowerIn"), &value) && value > 0) {
                registry.systemPowerInMw = value;
            }
            CFRelease(properties);
        }
        IOObjectRelease(battery);
        return registry;
    }

    // The internal battery's state now; the watts as measured this moment
    PowerRules::Reading readPowerSources()
    {
        PowerRules::Reading reading;
        CFTypeRef info = IOPSCopyPowerSourcesInfo();
        if (info == nullptr) {
            return reading;
        }
        CFArrayRef sources = IOPSCopyPowerSourcesList(info);
        CFDictionaryRef battery = nullptr;
        for (CFIndex i = 0; sources != nullptr && i < CFArrayGetCount(sources); i++) {
            CFDictionaryRef description = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, i));
            if (sameString(description, CFSTR(kIOPSTypeKey), CFSTR(kIOPSInternalBatteryType))) {
                battery = description;
                break;
            }
        }

        double voltage = PowerRules::unknown();
        double current = PowerRules::unknown();
        if (battery != nullptr) {
            reading.present = true;
            reading.onAC = sameString(battery, CFSTR(kIOPSPowerSourceStateKey), CFSTR(kIOPSACPowerValue));
            boolean(battery, CFSTR(kIOPSIsChargingKey), &reading.charging);
            bool charged = false;
            reading.charged = reading.onAC && (boolean(battery, CFSTR(kIOPSIsChargedKey), &charged) ? charged : !reading.charging);

            double capacity = 0;
            double maximum = 0;
            if (number(battery, CFSTR(kIOPSCurrentCapacityKey), &capacity) && number(battery, CFSTR(kIOPSMaxCapacityKey), &maximum) && maximum > 0) {
                reading.level = static_cast<int>(std::lround(100 * capacity / maximum));
            }
            double minutes = 0;
            if (number(battery, CFSTR(kIOPSTimeToEmptyKey), &minutes) && minutes > 0) {
                reading.minutesToEmpty = static_cast<int>(minutes);
            }
            if (number(battery, CFSTR(kIOPSTimeToFullChargeKey), &minutes) && minutes > 0) {
                reading.minutesToFull = static_cast<int>(minutes);
            }
            double value = 0;
            if (number(battery, CFSTR(kIOPSVoltageKey), &value) && value > 0) {
                voltage = value;
            }
            if (number(battery, CFSTR(kIOPSCurrentKey), &value)) {
                current = value;
            }
        }
        if (sources != nullptr) {
            CFRelease(sources);
        }
        CFRelease(info);
        if (!reading.present) {
            return reading;
        }

        Registry registry = readRegistry();
        if (!PowerRules::known(voltage)) {
            voltage = registry.voltageMv;
        }
        if (!PowerRules::known(current) || current == 0) {
            current = registry.amperageMa;
        }
        if (PowerRules::known(registry.capacityMah) && PowerRules::known(voltage)) {
            reading.capacityWh = registry.capacityMah * voltage / 1e6;
        }
        if (!reading.onAC) {
            // Discharging: mV × mA is µW
            if (PowerRules::known(voltage) && PowerRules::known(current) && current < 0) {
                reading.watts = voltage * -current / 1e6;
            }
        }
        else if (PowerRules::known(registry.systemPowerInMw)) {
            reading.watts = registry.systemPowerInMw / 1000;
        }
        return reading;
    }

    bool lowPowerModeNow()
    {
        return [NSProcessInfo processInfo].isLowPowerModeEnabled;
    }
}

struct ForkPower::Impl
{
    // Shared with the blocks and callbacks that outlive a call: they check alive on the main thread
    struct Shared {
        bool alive = true;
        PowerRules::Reading reading;
        bool lowPowerMode = false;
        std::deque<double> watts;   // the last minute's, for the average
        bool lastOnAC = false;
    };

    std::shared_ptr<Shared> shared = std::make_shared<Shared>();
    int startLevel = -1;
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    dispatch_queue_t queue = nullptr;       // where the power sources are read, off the main thread
    dispatch_source_t timer = nullptr;
    CFRunLoopSourceRef powerSourceChanges = nullptr;
    id lowPowerObserver = nil;

    // Main thread: keeps a reading, and tells the stream's event loop when what it shows changed
    static void store(const std::shared_ptr<Shared>& shared, const PowerRules::Reading& reading, bool lowPowerMode)
    {
        if (!shared->alive) {
            return;
        }
        if (reading.onAC != shared->lastOnAC) {
            // A new source: the old minute's watts say nothing about it
            shared->watts.clear();
            shared->lastOnAC = reading.onAC;
        }
        if (PowerRules::known(reading.watts)) {
            shared->watts.push_back(reading.watts);
            while (shared->watts.size() > k_WattsSamples) {
                shared->watts.pop_front();
            }
        }
        PowerRules::Reading averaged = reading;
        if (!shared->watts.empty()) {
            double sum = 0;
            for (double value : shared->watts) {
                sum += value;
            }
            averaged.watts = sum / shared->watts.size();
        }

        const PowerRules::Reading& before = shared->reading;
        bool changed = averaged.present != before.present || averaged.onAC != before.onAC || averaged.charging != before.charging ||
                       averaged.charged != before.charged || averaged.level != before.level ||
                       averaged.minutesToEmpty != before.minutesToEmpty || averaged.minutesToFull != before.minutesToFull ||
                       PowerRules::known(averaged.watts) != PowerRules::known(before.watts) ||
                       (PowerRules::known(averaged.watts) && std::fabs(averaged.watts - before.watts) >= 0.05) ||
                       lowPowerMode != shared->lowPowerMode;
        shared->reading = averaged;
        shared->lowPowerMode = lowPowerMode;
        if (changed) {
            SDL_Event event = {};
            event.type = ForkPower::changeEventType();
            SDL_PushEvent(&event);
        }
    }

    // Reads on the queue, and stores on the main thread
    void refresh()
    {
        std::shared_ptr<Shared> copy = shared;
        dispatch_async(queue, ^{
            PowerRules::Reading reading = readPowerSources();
            dispatch_async(dispatch_get_main_queue(), ^{
                store(copy, reading, lowPowerModeNow());
            });
        });
    }

    static void powerSourcesChanged(void* context)
    {
        // On the main run loop
        static_cast<Impl*>(context)->refresh();
    }
};

ForkPower::ForkPower()
    : m_Impl(std::make_unique<Impl>())
{
    changeEventType();
    Impl* impl = m_Impl.get();

    // The first reading at once, for the level the stream starts at; a few milliseconds, once
    PowerRules::Reading reading = readPowerSources();
    impl->shared->lastOnAC = reading.onAC;
    if (PowerRules::known(reading.watts)) {
        impl->shared->watts.push_back(reading.watts);
    }
    impl->shared->reading = reading;
    impl->shared->lowPowerMode = lowPowerModeNow();
    impl->startLevel = reading.present ? reading.level : -1;
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Power: %s, %d%%%s%s, Low Power Mode %s, %s",
                reading.present ? "battery" : "no battery", reading.level, reading.onAC ? ", on a power adapter" : "",
                reading.charging ? ", charging" : "", impl->shared->lowPowerMode ? "on" : "off",
                PowerRules::known(reading.watts) ? "the watts are measured" : "no watts to measure");

    impl->queue = dispatch_queue_create("com.anyosag.luzlunar.power", DISPATCH_QUEUE_SERIAL);

    // A power adapter plugged in or out, charging, the level
    impl->powerSourceChanges = IOPSNotificationCreateRunLoopSource(&Impl::powerSourcesChanged, impl);
    if (impl->powerSourceChanges != nullptr) {
        CFRunLoopAddSource(CFRunLoopGetMain(), impl->powerSourceChanges, kCFRunLoopCommonModes);
    }

    // Low Power Mode, posted on any thread
    std::shared_ptr<Impl::Shared> shared = impl->shared;
    impl->lowPowerObserver = [[NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                                                              object:nil
                                                                               queue:NSOperationQueue.mainQueue
                                                                          usingBlock:^(NSNotification* notification) {
        (void)notification;
        if (shared->alive) {
            Impl::store(shared, shared->reading, lowPowerModeNow());
        }
    }] retain];

    // The watts move all the time; the level and the estimates more slowly
    impl->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(impl->timer, dispatch_time(DISPATCH_TIME_NOW, k_RefreshNs), k_RefreshNs, NSEC_PER_SEC);
    dispatch_source_set_event_handler(impl->timer, ^{
        if (shared->alive) {
            impl->refresh();
        }
    });
    dispatch_resume(impl->timer);
}

ForkPower::~ForkPower()
{
    // Main thread, as are every callback and block: none runs after this
    m_Impl->shared->alive = false;
    if (m_Impl->timer != nullptr) {
        dispatch_source_cancel(m_Impl->timer);
        dispatch_release(m_Impl->timer);
    }
    if (m_Impl->powerSourceChanges != nullptr) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), m_Impl->powerSourceChanges, kCFRunLoopCommonModes);
        CFRelease(m_Impl->powerSourceChanges);
    }
    if (m_Impl->lowPowerObserver != nil) {
        [NSNotificationCenter.defaultCenter removeObserver:m_Impl->lowPowerObserver];
        [m_Impl->lowPowerObserver release];
    }
    // Reads still queued finish and find it gone
    if (m_Impl->queue != nullptr) {
        dispatch_release(m_Impl->queue);
    }
}

PowerRules::Reading ForkPower::reading() const
{
    return m_Impl->shared->reading;
}

bool ForkPower::lowPowerMode() const
{
    return m_Impl->shared->lowPowerMode;
}

int ForkPower::startLevel() const
{
    return m_Impl->startLevel;
}

double ForkPower::minutesSinceStart() const
{
    return std::chrono::duration<double>(std::chrono::steady_clock::now() - m_Impl->start).count() / 60;
}
