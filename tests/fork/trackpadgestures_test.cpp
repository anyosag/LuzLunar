// Tests for app/fork/forktrackpadgestures.*: which Dock gestures trackpad passthrough holds back,
// and the System Settings values it turns off and puts back, crash record included.
//   clang++ -std=c++17 -Iapp/fork tests/fork/trackpadgestures_test.cpp app/fork/forktrackpadgestures.cpp

#include "forktrackpadgestures.h"

#include <cstdio>
#include <map>
#include <string>

using namespace ForkTrackpadGestures;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

// System Settings, in memory
struct FakeSettings {
    std::map<std::string, int> values;
    std::string record;
    int writes = 0;
    bool failWrites = false;

    HoldBackend backend()
    {
        return HoldBackend {
            [this](const std::string& name) -> std::optional<int> {
                auto it = values.find(name);
                if (it == values.end()) {
                    return std::nullopt;
                }
                return it->second;
            },
            [this](const std::string& name, int value) {
                if (failWrites) {
                    return false;
                }
                values[name] = value;
                writes++;
                return true;
            },
            [this](const std::string& text) { record = text; },
        };
    }
};

static const std::vector<Setting> k_Settings = { { "edge", 0 }, { "drag", 0 } };

static void testDockFilter()
{
    DockGestureFilter f;
    // Not armed: everything passes
    CHECK(!f.swallow(0));
    CHECK(!f.swallow(16));

    // Arming in the middle of a gesture lets that gesture finish
    f.setArmed(true);
    CHECK(!f.swallow(32));
    CHECK(!f.swallow(48));
    // 300 ms of quiet ends it; the next one is dropped whole
    CHECK(f.swallow(400));
    CHECK(f.swallow(416));
    CHECK(f.swallow(432));

    // Disarming in the middle of a dropped gesture keeps dropping it to its end
    f.setArmed(false);
    CHECK(f.swallow(448));
    CHECK(!f.swallow(800));
    CHECK(!f.armed());

    // Events just under the quiet time apart are one gesture
    f.setArmed(true);
    CHECK(f.swallow(1200));
    f.setArmed(false);
    CHECK(f.swallow(1200 + DockGestureFilter::k_QuietMs - 1));
    CHECK(!f.swallow(1200 + 2 * DockGestureFilter::k_QuietMs));

    // Across the clock wrapping
    DockGestureFilter w;
    w.setArmed(true);
    CHECK(w.swallow(0xFFFFFF00u));
    w.setArmed(false);
    CHECK(w.swallow(0x00000010u));
}

static void testRecord()
{
    std::vector<Held> held = { { "edge", 3, 0 }, { "drag", 1, 0 } };
    std::string text = formatRecord(4242, held);
    CHECK(text == "4242:edge=3/0,drag=1/0");

    long pid = 0;
    std::vector<Held> parsed;
    CHECK(parseRecord(text, &pid, &parsed));
    CHECK(pid == 4242);
    CHECK(parsed.size() == 2);
    CHECK(parsed[0].name == "edge" && parsed[0].original == 3 && parsed[0].written == 0);
    CHECK(parsed[1].name == "drag" && parsed[1].original == 1 && parsed[1].written == 0);

    for (const char* bad : { "", "4242", "4242:", "x:edge=3/0", "4242:edge=3", "4242:edge=/0", "4242:=3/0",
                             "4242:edge=3/0,", "4242:ed ge=3/0", "4242:edge=3/a" }) {
        CHECK(!parseRecord(bad, &pid, &parsed));
    }
}

static void testHoldsOnlyWhatsOn()
{
    FakeSettings s;
    s.values = { { "edge", 3 }, { "drag", 0 } };  // three-finger drag is already off
    SettingsHold hold(s.backend(), k_Settings, 77);

    hold.want(true, 0);
    CHECK(hold.holding());
    CHECK(hold.held().size() == 1 && hold.held()[0].name == "edge");
    CHECK(s.values["edge"] == 0 && s.values["drag"] == 0);
    CHECK(s.record == "77:edge=3/0");

    // Wanting it again changes nothing
    int writes = s.writes;
    hold.want(true, 10);
    CHECK(s.writes == writes);

    hold.releaseNow();
    CHECK(!hold.holding());
    CHECK(s.values["edge"] == 3);
    CHECK(s.record.empty());
}

static void testNothingToHold()
{
    FakeSettings s;
    s.values = { { "edge", 0 } };  // and "drag" can't be read
    SettingsHold hold(s.backend(), k_Settings, 1);
    hold.want(true, 0);
    CHECK(!hold.holding());
    CHECK(s.record.empty());
    CHECK(s.writes == 0);
}

static void testWritesFail()
{
    FakeSettings s;
    s.values = { { "edge", 3 }, { "drag", 1 } };
    s.failWrites = true;
    SettingsHold hold(s.backend(), k_Settings, 1);
    hold.want(true, 0);
    CHECK(!hold.holding());
    CHECK(s.record.empty());  // written first, cleared when nothing changed
}

static void testDelayedRelease()
{
    FakeSettings s;
    s.values = { { "edge", 3 }, { "drag", 1 } };
    SettingsHold hold(s.backend(), k_Settings, 1);
    hold.want(true, 1000);
    CHECK(s.values["edge"] == 0 && s.values["drag"] == 0);

    // Leaving and coming straight back keeps holding
    hold.want(false, 2000);
    hold.tick(2000 + SettingsHold::k_ReleaseDelayMs - 1);
    CHECK(hold.holding());
    hold.want(true, 2500);
    hold.tick(2000 + SettingsHold::k_ReleaseDelayMs + 10);
    CHECK(hold.holding());

    // Leaving for longer puts them back
    hold.want(false, 6000);
    hold.want(false, 7000);  // the delay counts from the first
    hold.tick(6000 + SettingsHold::k_ReleaseDelayMs);
    CHECK(!hold.holding());
    CHECK(s.values["edge"] == 3 && s.values["drag"] == 1);
}

static void testUserChangedMeanwhile()
{
    FakeSettings s;
    s.values = { { "edge", 3 }, { "drag", 1 } };
    SettingsHold hold(s.backend(), k_Settings, 1);
    hold.want(true, 0);
    // The user turned three-finger drag back on in System Settings during the stream
    s.values["drag"] = 1;
    hold.releaseNow();
    CHECK(s.values["edge"] == 3);
    CHECK(s.values["drag"] == 1);

    // And one they set to something else stays that way too
    s.values = { { "edge", 3 }, { "drag", 1 } };
    SettingsHold again(s.backend(), k_Settings, 1);
    again.want(true, 0);
    s.values["edge"] = 2;
    again.releaseNow();
    CHECK(s.values["edge"] == 2);
}

static void testStartupRestore()
{
    FakeSettings s;
    auto running = [](long pid) { return pid == 500; };

    // No record
    CHECK(!restoreRecord("", s.backend(), running));

    // A copy that's still running keeps its record
    s.values = { { "edge", 0 } };
    s.record = "500:edge=3/0";
    CHECK(!restoreRecord(s.record, s.backend(), running));
    CHECK(s.values["edge"] == 0 && s.record == "500:edge=3/0");

    // A copy that's gone: put back and cleared
    s.record = "600:edge=3/0,drag=1/0";
    s.values = { { "edge", 0 }, { "drag", 1 } };  // the user already turned drag back on
    CHECK(restoreRecord(s.record, s.backend(), running));
    CHECK(s.values["edge"] == 3 && s.values["drag"] == 1);
    CHECK(s.record.empty());

    // A malformed record is cleared
    s.record = "garbage";
    CHECK(!restoreRecord(s.record, s.backend(), running));
    CHECK(s.record.empty());
}

int main()
{
    testDockFilter();
    testRecord();
    testHoldsOnlyWhatsOn();
    testNothingToHold();
    testWritesFail();
    testDelayedRelease();
    testUserChangedMeanwhile();
    testStartupRestore();

    if (s_Failures == 0) {
        std::printf("trackpadgestures: all tests passed\n");
        return 0;
    }
    std::printf("trackpadgestures: %d failure(s)\n", s_Failures);
    return 1;
}
