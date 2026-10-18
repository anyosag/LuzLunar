#pragma once

// The rules for holding back macOS's own trackpad gestures while trackpad passthrough runs,
// without AppKit or Qt so tests/fork/trackpadgestures_test.cpp can check them. The event tap and
// System Settings calls that use them are in mac/gesturesuppressor_mac.mm.

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace ForkTrackpadGestures
{
    // Decides which of the Dock's gesture events (CGEventType 30: Spaces and fullscreen swipes,
    // Mission Control, App Exposé, the Show Desktop and Apps pinches) to drop. A gesture is a run
    // of those events less than k_QuietMs apart, and it's dropped or passed whole, as decided at
    // its first event: the Dock must see a gesture end the way it began, so arming or disarming
    // never cuts one in two. Times are ms and may wrap.
    class DockGestureFilter
    {
    public:
        static constexpr std::uint32_t k_QuietMs = 300;

        // While armed, gestures that start are dropped
        void setArmed(bool armed) { m_Armed = armed; }
        bool armed() const { return m_Armed; }

        // For each Dock gesture event: true to drop it
        bool swallow(std::uint32_t timeMs);

    private:
        bool m_Armed = false;
        bool m_InGesture = false;
        bool m_Swallowing = false;
        std::uint32_t m_Last = 0;
    };

    // A System Settings value LuzLunar turns off while passthrough runs
    struct Setting {
        std::string name;  // The record's name for it, and the backend's key
        int off = 0;  // Its value when off
    };

    // A setting LuzLunar changed: what it was and what LuzLunar wrote
    struct Held {
        std::string name;
        int original = 0;
        int written = 0;
    };

    struct HoldBackend {
        // The setting's current value; nothing when it can't be read
        std::function<std::optional<int>(const std::string& name)> read;
        // False when it couldn't be set
        std::function<bool(const std::string& name, int value)> write;
        // Saves the crash record before anything is changed, and clears it with an empty string
        std::function<void(const std::string& record)> persist;
    };

    // "pid:name=original/written,name=original/written"
    std::string formatRecord(long pid, const std::vector<Held>& held);
    bool parseRecord(const std::string& text, long* pid, std::vector<Held>* held);

    // Puts back what a record says was changed, where the value is still what was written (the
    // user may have changed it since). Clears the record.
    void restore(const HoldBackend& backend, const std::vector<Held>& held);

    // At startup, for a record left by a LuzLunar that quit without putting the settings back:
    // restores them unless that copy is still running. A malformed record is cleared. Returns
    // true when it restored something.
    bool restoreRecord(const std::string& record, const HoldBackend& backend,
                       const std::function<bool(long pid)>& isRunningCopy);

    // Turns settings off while passthrough runs and back on afterwards. Releasing waits
    // k_ReleaseDelayMs, so Cmd+Tab out and straight back doesn't flip System Settings twice.
    class SettingsHold
    {
    public:
        static constexpr std::uint32_t k_ReleaseDelayMs = 2000;

        SettingsHold(HoldBackend backend, std::vector<Setting> settings, long pid);

        // Passthrough started (true) or stopped (false) at timeMs
        void want(bool on, std::uint32_t timeMs);

        // Releases once the delay after want(false) has passed
        void tick(std::uint32_t timeMs);

        // Releases now, for the end of the stream and quitting
        void releaseNow();

        bool holding() const { return !m_Held.empty(); }
        const std::vector<Held>& held() const { return m_Held; }

    private:
        void hold();

        HoldBackend m_Backend;
        std::vector<Setting> m_Settings;
        long m_Pid;
        std::vector<Held> m_Held;
        bool m_ReleasePending = false;
        std::uint32_t m_ReleaseAt = 0;
    };
}
