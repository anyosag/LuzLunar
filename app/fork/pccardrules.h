#pragma once

// [fork] What a PC's card in Your PCs says, from the facts LuzLunar has about the PC: its state
// (ComputerModel's "state" role), where it's reached, the note under its address, the apps on its
// card and the color it gets. Free of Qt, so tests build it alone (tests/fork/pccardrules_test.cpp).
#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

namespace PcCardRules
{
    // The card states of the canvas (card.md §9), plus "checking" for a PC that hasn't answered
    // since LuzLunar started (the canvas doesn't draw it)
    //   ready      reachable, paired, nothing running
    //   streaming  reachable, paired, an app runs
    //   waking     Wake PC was sent from this Mac less than k_WakeWaitSecs ago
    //   asleep     away, paired, can be woken
    //   off        this Mac shut it down and Wake PC can turn it on (the canvas's "Off, can turn on")
    //   offNoWake  this Mac shut it down and wake from off isn't set up
    //   pair       reachable, not paired
    //   lost       away, and Wake PC can't help: never paired from this Mac, or no MAC address known.
    //              (A wake that got no answer, or a PC last seen over the internet, is still "asleep":
    //              Wake PC stays available, as it is today.)
    //   checking   not polled yet
    struct Inputs {
        bool online = false;            // NvComputer::state == CS_ONLINE
        bool unknown = false;           // CS_UNKNOWN: not polled yet
        bool paired = false;            // pairState == PS_PAIRED
        bool knownPaired = false;       // paired, or not asked yet but with the certificate pinned by pairing from this Mac
        bool running = false;           // online and currentGameId != 0
        bool wakeable = false;          // a MAC address is known
        bool waking = false;            // Wake PC sent from this Mac less than k_WakeWaitSecs ago, no answer yet
        std::string powerAction;        // "sleep" or "off": this Mac's last accepted request, since the PC was last online
        long long powerActionAgeSecs = -1;  // how long ago; -1 unknown
        std::string wakeFromOff;        // Apollo's fromOff: ready, fixable, blocked, unknown; "" never told
    };

    // How long Wake PC waits for the PC to answer
    constexpr long long k_WakeWaitSecs = 180;

    // After Sleep PC or Shut Down PC is accepted, the card shows the result this long, while Moonlight
    // still finds the PC online (Apollo answers 202, then the PC goes down a few seconds later)
    constexpr long long k_GoingDownSecs = 60;

    inline std::string downState(const Inputs& in)
    {
        if (in.powerAction == "off") {
            return in.wakeFromOff == "ready" ? "off" : "offNoWake";
        }
        return "asleep";
    }

    inline std::string state(const Inputs& in)
    {
        if (in.online) {
            if (!in.paired) {
                return "pair";
            }
            if (!in.powerAction.empty() && in.powerActionAgeSecs >= 0 && in.powerActionAgeSecs < k_GoingDownSecs) {
                return downState(in);
            }
            return in.running ? "streaming" : "ready";
        }
        if (in.waking) {
            return "waking";
        }
        if (in.unknown) {
            return "checking";
        }
        if (!in.knownPaired || !in.wakeable) {
            return "lost";
        }
        return downState(in);
    }

    // Where an online PC is reached: "home" (its LAN address), "internet" (its outside address), ""
    inline std::string network(bool online, bool hasActive, bool activeIsLocal, bool activeIsRemote)
    {
        if (!online || !hasActive) {
            return "";
        }
        return activeIsLocal ? "home" : activeIsRemote ? "internet" : "";
    }

    // The note beside the IP chip: lastAddress, foundAutomatically, addedByAddress, outsideAddress,
    // reachableOutside, or "" for none
    inline std::string addressNote(bool online, bool knownPaired, const std::string& net,
                                   bool remoteWorked, bool foundAutomatically)
    {
        if (!online) {
            return "lastAddress";
        }
        if (!knownPaired) {
            return foundAutomatically ? "foundAutomatically" : "addedByAddress";
        }
        if (net == "internet") {
            return "outsideAddress";
        }
        if (net == "home" && remoteWorked) {
            return "reachableOutside";
        }
        return "";
    }

    // The colors, in the order they're handed to PCs (card.md §2.2): GonzaloPC indigo, Living Room
    // teal, Studio PC blue, Office PC pink
    inline const std::vector<std::string>& assignOrder()
    {
        static const std::vector<std::string> order = { "indigo", "teal", "blue", "pink", "purple",
                                                        "orange", "green", "red", "gold", "graphite" };
        return order;
    }

    // The first color nobody uses; when all ten are taken, start again by how many PCs have one
    inline std::string nextColor(const std::vector<std::string>& used)
    {
        for (const std::string& id : assignOrder()) {
            if (std::find(used.begin(), used.end(), id) == used.end()) {
                return id;
            }
        }
        return assignOrder()[used.size() % assignOrder().size()];
    }

    inline bool isColor(const std::string& id)
    {
        const std::vector<std::string>& order = assignOrder();
        return std::find(order.begin(), order.end(), id) != order.end();
    }

    // The card's color: a PC that isn't paired is gray; a paired one has its own (an unknown stored id
    // counts as unset)
    inline std::string hue(bool knownPaired, const std::string& stored)
    {
        if (!knownPaired) {
            return "gray";
        }
        return isColor(stored) ? stored : "indigo";
    }

    struct App {
        int id = 0;
        std::string name;
        bool hidden = false;
    };

    inline std::string lower(std::string text)
    {
        std::transform(text.begin(), text.end(), text.begin(),
                       [](unsigned char c) { return (char)std::tolower(c); });
        return text;
    }

    // The apps shown on the card, as indexes into the list: the running app first, then the recent
    // ones (names, newest first), then the built-ins in the canvas's order, then by name. Hidden
    // apps are left out unless one runs. The multi-display app is for the caller to leave out of
    // `apps` beforehand when it can't be streamed.
    inline std::vector<int> previewOrder(const std::vector<App>& apps, int runningId,
                                         const std::vector<std::string>& recent, size_t limit = 3)
    {
        auto builtin = [](const std::string& name) {
            const std::string n = lower(name);
            return n == "desktop" ? 0
                 : n == "desktop (multiple displays)" ? 1
                 : n == "steam big picture" ? 2
                 : n == "virtual display" ? 3
                 : 100;
        };
        auto recentRank = [&recent](const std::string& name) {
            for (size_t i = 0; i < recent.size(); i++) {
                if (lower(recent[i]) == lower(name)) {
                    return (int)i;
                }
            }
            return 1000;
        };

        std::vector<int> picked;
        for (size_t i = 0; i < apps.size(); i++) {
            if (!apps[i].hidden || (runningId != 0 && apps[i].id == runningId)) {
                picked.push_back((int)i);
            }
        }
        std::stable_sort(picked.begin(), picked.end(), [&](int a, int b) {
            const App& x = apps[a];
            const App& y = apps[b];
            const int rx = runningId != 0 && x.id == runningId ? 0 : 1;
            const int ry = runningId != 0 && y.id == runningId ? 0 : 1;
            if (rx != ry) return rx < ry;
            const int ax = recentRank(x.name), ay = recentRank(y.name);
            if (ax != ay) return ax < ay;
            const int bx = builtin(x.name), by = builtin(y.name);
            if (bx != by) return bx < by;
            return lower(x.name) < lower(y.name);
        });
        if (picked.size() > limit) {
            picked.resize(limit);
        }
        return picked;
    }

    // The app the card's main button starts (as an index into `apps`, -1 for none): the running app,
    // else the one set for direct launch, else "Desktop", else the first of the preview
    inline int mainApp(const std::vector<App>& apps, const std::vector<bool>& directLaunch, int runningId,
                       const std::vector<std::string>& recent)
    {
        if (runningId != 0) {
            for (size_t i = 0; i < apps.size(); i++) {
                if (apps[i].id == runningId) return (int)i;
            }
        }
        for (size_t i = 0; i < apps.size(); i++) {
            if (!apps[i].hidden && i < directLaunch.size() && directLaunch[i]) return (int)i;
        }
        for (size_t i = 0; i < apps.size(); i++) {
            if (!apps[i].hidden && lower(apps[i].name) == "desktop") return (int)i;
        }
        const std::vector<int> preview = previewOrder(apps, runningId, recent, 1);
        return preview.empty() ? -1 : preview[0];
    }

    // The middle value of the samples (latency in ms), -1 for none
    inline int median(std::vector<int> samples)
    {
        if (samples.empty()) {
            return -1;
        }
        std::sort(samples.begin(), samples.end());
        return samples[samples.size() / 2];
    }
}
