#include "forkmultitouch.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <map>
#include <mutex>

#if defined(__APPLE__)
#include <dlfcn.h>
#endif

namespace ForkMultitouch
{
namespace
{
    // MultitouchSupport's record of one contact (MTTouch, also called Finger), as reverse-engineered
    // by calftrail/Touch, OpenMultitouchSupport and others: 96 bytes since macOS 10.5
    struct MTPoint {
        float x;
        float y;
    };

    struct MTVector {
        MTPoint position;
        MTPoint velocity;
    };

    struct MTTouch {
        int frame;
        double timestamp;
        int pathIndex;  // The same for a contact's whole life
        int state;
        int fingerId;
        int handId;
        MTVector normalized;  // 0-1 across and up the pad
        float zTotal;
        float zPressure;
        float angle;
        float majorAxis;  // mm
        float minorAxis;  // mm
        MTVector absolute;  // mm
        int field14;
        int field15;
        float zDensity;
    };

    static_assert(sizeof(MTTouch) == 96, "MTTouch is 96 bytes");
    static_assert(offsetof(MTTouch, state) == 20, "state at 20");
    static_assert(offsetof(MTTouch, fingerId) == 24, "fingerId at 24");
    static_assert(offsetof(MTTouch, normalized) == 32, "normalized at 32");
    static_assert(offsetof(MTTouch, majorAxis) == 60, "majorAxis at 60");
    static_assert(offsetof(MTTouch, minorAxis) == 64, "minorAxis at 64");
    static_assert(offsetof(MTTouch, zDensity) == 92, "zDensity at 92");

    using Clock = std::chrono::steady_clock;

    // A pad's frame older than this no longer says what's on it
    constexpr auto k_Recent = std::chrono::milliseconds(100);

    // The first frames with contacts are checked: more than k_MaxBadFrames of them that make no
    // sense, and the framework's layout has changed under us
    constexpr int k_CheckFrames = 50;
    constexpr int k_MaxBadFrames = 10;

    struct PadFrame {
        std::vector<Contact> contacts;
        Clock::time_point at;
    };

    std::mutex s_Lock;  // The framework calls back on its own thread
    std::map<const void*, PadFrame> s_Pads;
    bool s_Running = false;
    bool s_Broken = false;
    int s_Checked = 0;
    int s_Bad = 0;
    std::string s_Why = "not started";

    [[maybe_unused]] void record(const void* device, const MTTouch* touches, int count)
    {
        PadFrame frame;
        frame.at = Clock::now();
        bool bad = false;
        for (int i = 0; i < count && touches != nullptr; i++) {
            const MTTouch& t = touches[i];
            Contact c;
            c.x = t.normalized.position.x;
            c.y = t.normalized.position.y;
            c.state = t.state;
            c.fingerId = t.fingerId;
            c.minorAxisMm = t.minorAxis;
            c.majorAxisMm = t.majorAxis;
            if (!plausible(c)) {
                bad = true;
            }
            frame.contacts.push_back(c);
        }

        std::lock_guard<std::mutex> lock(s_Lock);
        if (count > 0 && s_Checked < k_CheckFrames) {
            s_Checked++;
            if (bad && ++s_Bad > k_MaxBadFrames) {
                s_Broken = true;
                s_Why = "its contacts don't make sense (the framework changed)";
            }
        }
        s_Pads[device] = std::move(frame);
    }

#if defined(__APPLE__)
    using ContactCallback = int (*)(void* device, const MTTouch* touches, int count, double timestamp, int frame);

    // The framework's functions, and CoreFoundation's for its device list (CFArrayRef, CFIndex)
    struct Api {
        void* (*createList)() = nullptr;
        void (*registerCallback)(void*, ContactCallback) = nullptr;
        void (*unregisterCallback)(void*, ContactCallback) = nullptr;
        int (*startDevice)(void*, int) = nullptr;
        int (*stopDevice)(void*) = nullptr;
        long (*arrayCount)(const void*) = nullptr;
        const void* (*arrayValue)(const void*, long) = nullptr;
        void (*release)(const void*) = nullptr;
    };

    Api s_Api;
    void* s_DeviceList = nullptr;
    std::vector<void*> s_Started;

    int onFrame(void* device, const MTTouch* touches, int count, double, int)
    {
        record(device, touches, count);
        return 0;
    }

    template <typename T>
    bool find(void* library, const char* name, T* out)
    {
        *out = reinterpret_cast<T>(dlsym(library, name));
        return *out != nullptr;
    }
#endif
}

bool touchingState(int state)
{
    return state >= 3 && state <= 6;
}

bool plausible(const Contact& c)
{
    return std::isfinite(c.x) && std::isfinite(c.y) && c.x >= -0.1f && c.x <= 1.1f && c.y >= -0.1f && c.y <= 1.1f &&
           c.state >= 0 && c.state <= 7 && c.fingerId >= 0 && c.fingerId <= 7 &&
           std::isfinite(c.minorAxisMm) && std::isfinite(c.majorAxisMm) &&
           c.minorAxisMm >= 0 && c.minorAxisMm <= 80 && c.majorAxisMm >= 0 && c.majorAxisMm <= 120;
}

namespace
{
    struct Pair {
        float distance;
        std::size_t touch;
        std::size_t contact;
    };

    // The pairs within k_MatchDistance, closest first, each touch and contact in one at most.
    // flipY reads the contacts' y the other way up.
    std::vector<Pair> match(const std::vector<ForkTrackpad::Touch>& touches, const std::vector<Contact>& contacts, bool flipY)
    {
        std::vector<Pair> pairs;
        for (std::size_t i = 0; i < touches.size(); i++) {
            for (std::size_t j = 0; j < contacts.size(); j++) {
                if (!touchingState(contacts[j].state)) {
                    continue;
                }
                float y = flipY ? 1.0f - contacts[j].y : contacts[j].y;
                float dx = static_cast<float>(touches[i].x) - contacts[j].x;
                float dy = static_cast<float>(touches[i].y) - y;
                float distance = std::sqrt(dx * dx + dy * dy);
                if (distance <= k_MatchDistance) {
                    pairs.push_back({distance, i, j});
                }
            }
        }
        std::sort(pairs.begin(), pairs.end(), [](const Pair& a, const Pair& b) { return a.distance < b.distance; });

        std::vector<Pair> taken;
        std::vector<bool> touchTaken(touches.size(), false);
        std::vector<bool> contactTaken(contacts.size(), false);
        for (const Pair& p : pairs) {
            if (touchTaken[p.touch] || contactTaken[p.contact]) {
                continue;
            }
            touchTaken[p.touch] = true;
            contactTaken[p.contact] = true;
            taken.push_back(p);
        }
        return taken;
    }
}

void annotate(std::vector<ForkTrackpad::Touch>& touches, const std::vector<Contact>& contacts)
{
    // The framework's y is taken to grow up the pad like NSTouch's. Should it count the other way,
    // the pairing read upside down finds more of the fingers, and is the one used.
    std::vector<Pair> pairs = match(touches, contacts, false);
    std::vector<Pair> flipped = match(touches, contacts, true);
    if (flipped.size() > pairs.size()) {
        pairs = flipped;
    }

    for (const Pair& p : pairs) {
        ForkTrackpad::Touch& t = touches[p.touch];
        const Contact& c = contacts[p.contact];
        t.hasContact = true;
        t.fingerId = c.fingerId;
        t.minorAxisMm = c.minorAxisMm;
    }
}

bool start()
{
    stop();

#if defined(__APPLE__)
    void* framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (framework == nullptr) {
        std::lock_guard<std::mutex> lock(s_Lock);
        s_Why = "MultitouchSupport isn't on this Mac";
        return false;
    }

    // The framework stays loaded from here on: unloading it could pull it from under a callback
    Api api;
    bool found = find(framework, "MTDeviceCreateList", &api.createList) &&
                 find(framework, "MTRegisterContactFrameCallback", &api.registerCallback) &&
                 find(framework, "MTUnregisterContactFrameCallback", &api.unregisterCallback) &&
                 find(framework, "MTDeviceStart", &api.startDevice) &&
                 find(framework, "MTDeviceStop", &api.stopDevice) &&
                 find(RTLD_DEFAULT, "CFArrayGetCount", &api.arrayCount) &&
                 find(RTLD_DEFAULT, "CFArrayGetValueAtIndex", &api.arrayValue) &&
                 find(RTLD_DEFAULT, "CFRelease", &api.release);
    if (!found) {
        std::lock_guard<std::mutex> lock(s_Lock);
        s_Why = "MultitouchSupport lacks the functions it used to have";
        return false;
    }

    void* list = api.createList();
    if (list == nullptr) {
        std::lock_guard<std::mutex> lock(s_Lock);
        s_Why = "MultitouchSupport lists no trackpads";
        return false;
    }

    {
        std::lock_guard<std::mutex> lock(s_Lock);
        s_Pads.clear();
        s_Broken = false;
        s_Checked = 0;
        s_Bad = 0;
        s_Why.clear();
        s_Running = true;
    }

    s_Api = api;
    s_DeviceList = list;
    long count = api.arrayCount(list);
    for (long i = 0; i < count; i++) {
        void* device = const_cast<void*>(api.arrayValue(list, i));
        if (device == nullptr) {
            continue;
        }
        api.registerCallback(device, onFrame);
        api.startDevice(device, 0);
        s_Started.push_back(device);
    }

    if (s_Started.empty()) {
        stop();
        std::lock_guard<std::mutex> lock(s_Lock);
        s_Why = "MultitouchSupport lists no trackpads";
        return false;
    }
    return true;
#else
    std::lock_guard<std::mutex> lock(s_Lock);
    s_Why = "MultitouchSupport is macOS's";
    return false;
#endif
}

void stop()
{
#if defined(__APPLE__)
    for (void* device : s_Started) {
        s_Api.unregisterCallback(device, onFrame);
        s_Api.stopDevice(device);
    }
    s_Started.clear();
    if (s_DeviceList != nullptr) {
        s_Api.release(s_DeviceList);
        s_DeviceList = nullptr;
    }
#endif

    std::lock_guard<std::mutex> lock(s_Lock);
    if (s_Running && !s_Broken) {
        s_Why = "stopped";
    }
    s_Running = false;
    s_Pads.clear();
}

std::vector<Contact> contactsNow()
{
    std::vector<Contact> contacts;
    std::lock_guard<std::mutex> lock(s_Lock);
    if (!s_Running || s_Broken) {
        return contacts;
    }
    Clock::time_point now = Clock::now();
    for (const auto& pad : s_Pads) {
        if (now - pad.second.at <= k_Recent) {
            contacts.insert(contacts.end(), pad.second.contacts.begin(), pad.second.contacts.end());
        }
    }
    return contacts;
}

void annotateNow(std::vector<ForkTrackpad::Touch>& touches)
{
    std::vector<Contact> contacts = contactsNow();
    if (!contacts.empty()) {
        annotate(touches, contacts);
    }
}

std::string why()
{
    std::lock_guard<std::mutex> lock(s_Lock);
    return s_Running && !s_Broken ? std::string() : s_Why;
}
}
