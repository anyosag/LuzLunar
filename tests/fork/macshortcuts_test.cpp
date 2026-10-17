// Unit tests for app/fork/forkmacshortcuts.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Iapp tests/fork/macshortcuts_test.cpp app/fork/forkmacshortcuts.cpp
#include "fork/forkmacshortcuts.h"

#include <cstdio>
#include <map>
#include <set>
#include <string>

using namespace ForkMacShortcuts;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

namespace
{
    // A fake macOS: hot key states, what refuses to turn off, and a log of calls in order
    struct FakeMac {
        std::map<int, bool> global;    // System Settings state
        std::map<int, bool> appOff;    // turned off for LuzLunar only
        std::set<int> refuses;
        std::vector<std::string> log;
        std::vector<int> record;

        Backend backend()
        {
            return {
                [this](int id) {
                    auto it = global.find(id);
                    return it == global.end() || it->second;
                },
                [this](int id, Scope scope, bool enabled) {
                    log.push_back(std::string(enabled ? "on " : "off ") + std::to_string(id));
                    if (refuses.count(id)) {
                        return false;
                    }
                    if (scope == ScopeGlobal) {
                        global[id] = enabled;
                    }
                    else {
                        appOff[id] = !enabled;
                    }
                    return true;
                },
                [this](const std::vector<int>& ids) {
                    std::string entry = "persist";
                    for (int id : ids) {
                        entry += " " + std::to_string(id);
                    }
                    log.push_back(entry);
                    record = ids;
                },
            };
        }
    };

    bool hasDuplicate(const std::vector<int>& ids)
    {
        return std::set<int>(ids.begin(), ids.end()).size() != ids.size();
    }
}

int main()
{
    // The table: unique keys and ids, every id in range and named, nothing protected
    std::set<std::string> keys;
    std::vector<int> allIds;
    for (const Group& group : groups()) {
        CHECK(keys.insert(group.key).second);
        CHECK(group.label[0] != '\0');
        CHECK(!group.hotKeys.empty());
        for (const HotKey& hotKey : group.hotKeys) {
            CHECK(hotKey.id > 0 && hotKey.id <= MaxHotKeyId);
            CHECK(hotKey.name[0] != '\0');
            CHECK(!isProtected(hotKey.id));
            allIds.push_back(hotKey.id);
        }
    }
    CHECK(!hasDuplicate(allIds));

    // Force Quit, logout and VoiceOver are never taken
    CHECK(isProtected(0) && isProtected(6) && isProtected(14) && isProtected(59));

    // Screenshots and Cmd+Tab stay with the Mac by default; Spotlight goes to the host
    CHECK(findGroup("screenshots") && !findGroup("screenshots")->defaultToHost);
    CHECK(findGroup("appSwitcher") && !findGroup("appSwitcher")->defaultToHost);
    CHECK(findGroup("spotlight") && findGroup("spotlight")->defaultToHost);
    CHECK(findGroup("nothing") == nullptr);

    // Only Cmd+Tab needs the global switch
    for (const Group& group : groups()) {
        CHECK((group.scope == ScopeGlobal) == (std::string(group.key) == "appSwitcher"));
    }

    // The defaults take Spotlight but not Cmd+Shift+4 (30) or Cmd+Tab (1)
    std::vector<Wanted> defaults = wantedHotKeys([](const Group& g) { return g.defaultToHost; });
    std::set<int> defaultIds;
    for (const Wanted& w : defaults) {
        defaultIds.insert(w.id);
    }
    CHECK(defaultIds.count(64) && defaultIds.count(79) && defaultIds.count(233));
    CHECK(!defaultIds.count(30) && !defaultIds.count(28) && !defaultIds.count(184) && !defaultIds.count(1));
    CHECK(defaultIds.size() == defaults.size());

    // Record format
    CHECK(formatRecord(1234, { 1, 2 }) == "1234:1,2");
    CHECK(formatRecord(1234, {}).empty());
    long pid = 0;
    std::vector<int> ids;
    CHECK(parseRecord("1234:1,2", &pid, &ids) && pid == 1234 && ids == std::vector<int>({ 1, 2 }));
    CHECK(parseRecord("7:64", &pid, &ids) && pid == 7 && ids == std::vector<int>({ 64 }));
    CHECK(!parseRecord("", &pid, &ids));
    CHECK(!parseRecord("1234", &pid, &ids));
    CHECK(!parseRecord("1234:", &pid, &ids));
    CHECK(!parseRecord(":1", &pid, &ids));
    CHECK(!parseRecord("0:1", &pid, &ids));
    CHECK(!parseRecord("12:1,,2", &pid, &ids));
    CHECK(!parseRecord("12:1,1", &pid, &ids));
    CHECK(!parseRecord("12:0", &pid, &ids));
    CHECK(!parseRecord("12:265", &pid, &ids));
    CHECK(!parseRecord("12:-1", &pid, &ids));
    CHECK(!parseRecord("12: 1", &pid, &ids));
    CHECK(!parseRecord("x:1", &pid, &ids));

    // Taking: global hot keys are recorded before they're turned off; ones already off are skipped
    {
        FakeMac mac;
        mac.global[60] = false; // Ctrl+Space turned off in System Settings
        Controller ctl(mac.backend(), { { 1, ScopeGlobal, "SwitchFwd" }, { 64, ScopeApp, "Spotlight" },
                                        { 60, ScopeApp, "TSMLastScript" } });
        ctl.update(true);
        CHECK(ctl.taken());
        CHECK(mac.log.size() == 3);
        CHECK(mac.log[0] == "persist 1");
        CHECK(mac.log[1] == "off 1" && mac.log[2] == "off 64");
        CHECK(ctl.held().size() == 2);
        CHECK(mac.appOff[64] && !mac.global[1]);

        // Taking again does nothing
        ctl.update(true);
        CHECK(mac.log.size() == 3);

        // Giving back turns on exactly what was taken, then clears the record
        ctl.update(false);
        CHECK(!ctl.taken() && ctl.held().empty());
        CHECK(mac.log.size() == 6);
        CHECK(mac.log[3] == "on 1" && mac.log[4] == "on 64" && mac.log[5] == "persist");
        CHECK(mac.record.empty());
        CHECK(mac.global[1] && !mac.appOff[64]);
        CHECK(mac.global.count(60) && !mac.global[60]); // still off, as the user chose

        // Focus back: taken again
        ctl.update(true);
        CHECK(ctl.taken() && ctl.held().size() == 2);
        ctl.releaseAll();
        CHECK(!ctl.taken());
    }

    // A hot key macOS refuses isn't held, and the record drops it
    {
        FakeMac mac;
        mac.refuses.insert(2);
        Controller ctl(mac.backend(), { { 1, ScopeGlobal, "SwitchFwd" }, { 2, ScopeGlobal, "SwitchBack" } });
        ctl.update(true);
        CHECK(ctl.held().size() == 1 && ctl.held()[0].id == 1);
        CHECK(mac.record == std::vector<int>({ 1 }));
        ctl.update(false);
        CHECK(mac.record.empty());
        CHECK(mac.log.back() == "persist");
    }

    // App-only hot keys never touch the record
    {
        FakeMac mac;
        Controller ctl(mac.backend(), { { 64, ScopeApp, "Spotlight" } });
        ctl.update(true);
        ctl.update(false);
        for (const std::string& entry : mac.log) {
            CHECK(entry.rfind("persist", 0) != 0);
        }
    }

    // Nothing wanted: nothing happens
    {
        FakeMac mac;
        Controller ctl(mac.backend(), {});
        ctl.update(true);
        ctl.update(false);
        CHECK(mac.log.empty());
    }

    if (s_Failures == 0) {
        std::printf("All Mac shortcut tests passed\n");
    }
    return s_Failures == 0 ? 0 : 1;
}
