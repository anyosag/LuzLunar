#pragma once

#include <functional>
#include <string>
#include <vector>

// Which macOS system shortcuts (symbolic hot keys) a stream takes from the Mac and sends to the
// host while system key capture is on. Plain C++, so it's easy to test; the macOS calls are in
// mac/macintegration.mm and the stream glue in forksystemshortcuts.cpp.
namespace ForkMacShortcuts
{
    // The highest symbolic hot key id macOS 27 accepts
    const int MaxHotKeyId = 264;

    // How a hot key is turned off while streaming
    enum Scope {
        // Only for LuzLunar's own windows, and macOS drops it when LuzLunar exits
        ScopeApp,
        // For every app, until it's turned back on. Only for hot keys macOS won't turn off per app
        // (Cmd+Tab); a crash record puts them back if LuzLunar dies holding them.
        ScopeGlobal,
    };

    struct HotKey {
        int id;
        // macOS's own name for the id, checked before use so a renumbered id is left alone
        const char* name;
    };

    struct Group {
        // fork/macShortcuts/<key> in the settings
        const char* key;
        const char* label;
        // Sent to the host unless the settings say otherwise
        bool defaultToHost;
        Scope scope;
        std::vector<HotKey> hotKeys;
    };

    const std::vector<Group>& groups();

    // Null if there's no such group
    const Group* findGroup(const std::string& key);

    // Hot keys a stream never takes: Force Quit, logout, accessibility, brightness and the like
    bool isProtected(int id);

    struct Wanted {
        int id;
        Scope scope;
        const char* name;
    };

    // The hot keys of the groups sent to the host, in table order without repeats
    std::vector<Wanted> wantedHotKeys(const std::function<bool(const Group&)>& toHost);

    // The crash record: the process that turned global hot keys off, and which.
    // "1234:1,2". An empty list formats as "".
    std::string formatRecord(long pid, const std::vector<int>& ids);
    bool parseRecord(const std::string& text, long* pid, std::vector<int>* ids);

    struct Backend {
        // Whether the hot key is on for everyone (System Settings > Keyboard Shortcuts)
        std::function<bool(int id)> isEnabled;
        // Turns a hot key off or back on; false if macOS refused
        std::function<bool(int id, Scope scope, bool enabled)> setEnabled;
        // Saves the crash record of global hot keys held off (empty clears it)
        std::function<void(const std::vector<int>& globalIds)> persist;
    };

    // Takes the wanted hot keys from the Mac while capture is active and gives back exactly
    // those it took. Hot keys already off are left alone, so turning them back on can't
    // override a choice made in System Settings.
    class Controller
    {
    public:
        Controller(Backend backend, std::vector<Wanted> wanted);

        // Takes the hot keys if take is true and they aren't held, gives them back otherwise
        void update(bool take);
        void releaseAll() { update(false); }

        bool taken() const { return m_Taken; }
        const std::vector<Wanted>& held() const { return m_Held; }

    private:
        std::vector<int> heldGlobalIds() const;

        Backend m_Backend;
        std::vector<Wanted> m_Wanted;
        std::vector<Wanted> m_Held;
        bool m_Taken;
    };
}
