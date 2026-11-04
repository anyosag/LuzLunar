#pragma once

#include <string>
#include <vector>

// [fork] Set Up Wake from Off and Shut Down PC (forkhostpower.*, ForkWakeSetupDialog.qml), with
// anyosag/Apollo's /actions/wake (src/fork/wake_setup_policy.h): what the dialog's rows, its
// summary and its notes say, what Shut Down PC warns about, and the toasts once a fix ran or the PC
// came on after Wake PC. ForkHostPower reads Apollo's JSON into a Status; this decides the words.
// Free of Qt, so tests can build it alone (tests/fork/wakesetuprules_test.cpp).
namespace WakeSetupRules
{
    // One of Apollo's checks: id is link, magicPacket, shutdownWake, eee, fastStartup, macOverride
    // or bios; state is ok, fix, blocked, unknown, warn or manual
    struct Check {
        std::string id;
        std::string state;
        std::string reason;     // wifi, virtual, none, other, missing, ambiguous, policy, no_hibernation
        std::string keyword;
        std::string setting;    // the driver's name for it, as Device Manager shows it
        std::string current;    // its option now
        std::string target;     // the option Fix on PC sets
    };

    // How the last fix or undo went (Apollo's lastResult)
    struct Result {
        bool present = false;
        std::string action;     // fix or undo
        bool ok = false;
        bool restartNeeded = false;
        int changed = 0;
        std::vector<std::string> failed;
        std::string error;      // access_denied, journal, streaming, updating, "error <n>"
    };

    // GET /actions/wake's answer
    struct Status {
        bool known = false;     // Apollo answered
        std::string fromOff;    // ready, fixable, blocked, unknown
        std::string adapterName;
        std::string adapterDescription;
        std::string link;       // ethernet, wifi, virtual, other, none
        std::vector<Check> checks;
        std::string lastPowerOn; // lan, pme, powerSwitch, acRestored, other, unknown, ...
        long long uptimeSeconds = -1;
        bool undoable = false;
        bool applying = false;
        bool canFix = false;
        bool canUndo = false;
        std::string reason;     // none, streaming, updating, applying
        Result lastResult;
    };

    // A row of the dialog: kind is ok (a checkmark), warn (a warning sign) or info
    struct Row {
        std::string id;
        std::string kind;
        std::string title;
        std::string detail;
    };

    inline std::string fill(std::string text, const std::string& pcName)
    {
        const std::string mark = "%1";
        for (size_t pos = text.find(mark); pos != std::string::npos; pos = text.find(mark, pos + pcName.size())) {
            text.replace(pos, mark.size(), pcName);
        }
        return text;
    }

    inline std::string orElse(const std::string& text, const std::string& fallback)
    {
        return text.empty() ? fallback : text;
    }

    inline bool coldBootByLan(const std::string& lastPowerOn)
    {
        return lastPowerOn == "lan" || lastPowerOn == "pme";
    }

    // The BIOS settings only someone at the PC can check
    inline std::string biosText(const std::string& pcName)
    {
        return fill("In %1's BIOS, turn on Power On By PCI-E (also called Wake on LAN, or Resume by PCI-E Device), "
                    "and turn off ErP Ready (or Deep Sleep, or EuP). Network boot (PXE) isn't needed.", pcName);
    }

    // Turning the PC on from outside the home network, which nothing on the PC can fix
    inline std::string awayText(const std::string& pcName, const std::string& ip, const std::string& mac)
    {
        std::string address = ip.empty() ? std::string("its address") : ip;
        std::string hardware = mac.empty() ? std::string("its MAC address") : mac;
        return fill("When %1 is off, nothing answers your router for it, so a Wake PC from outside your home network "
                    "doesn't get there. In your router, bind " + address + " to " + hardware + " (IP & MAC binding, "
                    "or a static ARP entry). LuzLunar already sends Wake PC to the ports you forward for streaming. "
                    "Or wake %1 from a device at home that's always on.", pcName);
    }

    inline Row row(const Check& check, const Status& status, const std::string& pcName)
    {
        Row r;
        r.id = check.id;
        r.kind = check.state == "ok" ? "ok" : check.state == "manual" ? "info" : "warn";
        const std::string setting = orElse(check.setting, check.keyword);

        if (check.id == "link") {
            const std::string adapter = orElse(status.adapterDescription, status.adapterName);
            if (check.state == "ok") {
                r.title = "Connected by Ethernet";
                r.detail = adapter;
            }
            else if (check.reason == "wifi") {
                r.title = "Connected by Wi-Fi";
                r.detail = fill("A PC can't be turned on over Wi-Fi. Connect %1 by Ethernet.", pcName);
            }
            else if (check.reason == "virtual") {
                r.title = "Connected through a virtual adapter";
                r.detail = fill(adapter + ": LuzLunar reaches %1 through a virtual adapter (Hyper-V's switch, or a VPN), "
                                "so its wake settings belong to the network card behind it.", pcName);
            }
            else if (check.reason == "none") {
                r.title = "Network adapter not found";
                r.detail = fill("Apollo couldn't tell which adapter LuzLunar reaches %1 through.", pcName);
            }
            else {
                r.title = "Connected through " + orElse(adapter, "an unknown adapter");
                r.detail = fill("Apollo can't tell whether this adapter can turn %1 on.", pcName);
            }
        }
        else if (check.id == "magicPacket") {
            if (check.state == "ok") {
                r.title = "Wake on Magic Packet is on";
            }
            else if (check.state == "fix") {
                r.title = "Wake on Magic Packet is off";
                r.detail = "Fix on PC turns it on.";
            }
            else {
                r.title = "No Wake on Magic Packet setting";
                r.detail = "This driver doesn't have Windows' standard setting for it.";
            }
        }
        else if (check.id == "shutdownWake") {
            if (check.state == "ok") {
                r.title = setting + " is " + orElse(check.current, "on");
                r.detail = fill("It keeps the network card listening once %1 is off.", pcName);
            }
            else if (check.state == "fix") {
                r.title = setting + " is " + orElse(check.current, "off");
                r.detail = "Fix on PC sets it to " + orElse(check.target, "Enabled") + ".";
            }
            else if (check.reason == "ambiguous") {
                r.title = setting + " is " + orElse(check.current, "set");
                r.detail = "Apollo can't tell which option turns it on. Set it to Enabled in Device Manager, on the adapter's Advanced tab.";
            }
            else {
                r.title = "No setting for waking from off";
                r.detail = "This driver has no setting for staying awake once the PC is off. The network card maker's own driver "
                           "may add one (Realtek: Shutdown Wake-On-Lan; Intel: Wake on Magic Packet from power off state).";
            }
        }
        else if (check.id == "eee") {
            if (check.state == "ok") {
                r.title = "Energy-Efficient Ethernet is off";
            }
            else {
                r.title = "Energy-Efficient Ethernet is on";
                r.detail = "Intel's steps for waking from off turn it off. Fix on PC does.";
            }
        }
        else if (check.id == "fastStartup") {
            if (check.state == "fix") {
                r.title = "Fast Startup is on";
                r.detail = "Windows turns off wake-up when it shuts down this way. Fix on PC turns Fast Startup off; "
                           "starting from off then takes a few seconds longer.";
            }
            else if (check.state == "warn") {
                r.title = "Fast Startup is on (set by a policy)";
                r.detail = "Start menu shutdowns can't be woken. Shut Down PC from LuzLunar does a full shutdown, which can.";
            }
            else {
                r.title = check.reason == "policy" ? "Fast Startup is off (set by a policy)" : "Fast Startup is off";
                if (check.reason == "no_hibernation") {
                    r.detail = "Hibernation is off, so every shutdown is a full one.";
                }
            }
        }
        else if (check.id == "macOverride") {
            r.title = "Windows uses a changed MAC address";
            r.detail = fill("The adapter's Network Address setting is set. When %1 is off, the card may answer only to its own address.", pcName);
        }
        else if (check.id == "bios") {
            r.title = "Check the BIOS once";
            r.detail = biosText(pcName);
        }
        else {
            r.title = setting;
        }
        return r;
    }

    // The dialog's rows, in Apollo's order; a MAC address that wasn't changed has none
    inline std::vector<Row> rows(const Status& status, const std::string& pcName)
    {
        std::vector<Row> out;
        for (const Check& check : status.checks) {
            if (check.id == "macOverride" && check.state == "ok") {
                continue;
            }
            out.push_back(row(check, status, pcName));
        }
        if (status.known && !status.lastPowerOn.empty() && status.lastPowerOn != "unknown") {
            Row last;
            last.id = "lastPowerOn";
            last.kind = "info";
            last.title = status.lastPowerOn == "lan" || status.lastPowerOn == "pme" ? "Last turned on by Wake-on-LAN"
                       : status.lastPowerOn == "powerSwitch"                       ? "Last turned on with the power button"
                       : status.lastPowerOn == "acRestored"                        ? "Last turned on when power came back"
                                                                                   : "Last turned on by something else";
            out.push_back(last);
        }
        return out;
    }

    inline const Check* firstWith(const Status& status, const std::string& state, bool ignoreFastStartup = false)
    {
        for (const Check& check : status.checks) {
            if (check.state == state && !(ignoreFastStartup && check.id == "fastStartup")) {
                return &check;
            }
        }
        return nullptr;
    }

    // The line above the rows
    inline std::string summary(const Status& status, const std::string& pcName)
    {
        if (!status.known) {
            return fill("Asking %1…", pcName);
        }
        std::string text;
        if (status.fromOff == "ready") {
            text = "%1 is ready to turn on from off, as far as Windows goes. Check its BIOS once, below.";
        }
        else if (status.fromOff == "fixable") {
            text = "%1 needs a few changes to turn on from off.";
        }
        else if (status.fromOff == "blocked") {
            const Check* blocked = firstWith(status, "blocked");
            text = "%1 can't turn on from off: " + (blocked ? row(*blocked, status, pcName).title : std::string("see below")) + ".";
        }
        else {
            text = "Apollo can't tell whether %1 can turn on from off.";
        }
        if (status.reason == "streaming") {
            text += " Fix on PC waits until %1 stops streaming.";
        }
        else if (status.reason == "updating") {
            text += " Fix on PC waits until %1 has installed its Apollo update.";
        }
        else if (status.applying || status.reason == "applying") {
            text += " %1 is changing its settings now.";
        }
        return fill(text, pcName);
    }

    // What Fix on PC asks before it runs
    inline std::string fixConfirmation(const Status& status, const std::string& pcName)
    {
        std::string changes;
        bool fastStartup = false;
        bool adapter = false;
        for (const Check& check : status.checks) {
            if (check.state != "fix") {
                continue;
            }
            std::string item;
            if (check.id == "fastStartup") {
                fastStartup = true;
                item = "Fast Startup off";
            }
            else {
                adapter = true;
                item = orElse(check.setting, check.keyword) + " " + (check.id == "eee" ? "off" : "on");
            }
            changes += (changes.empty() ? "" : ", ") + item;
        }
        std::string text = "Fix on PC changes " + (changes.empty() ? std::string("nothing") : changes) + ".";
        if (adapter) {
            text += " %1's network adapter restarts, so it drops off the network for a few seconds.";
        }
        if (fastStartup) {
            text += " From then on Windows shuts %1 down fully, so it starts from off a few seconds slower.";
        }
        text += " Undo Changes puts it all back.";
        return fill(text, pcName);
    }

    // Shut Down PC's warning when Wake PC may not turn the PC on again; empty when there's nothing
    // to say. Shut Down PC does a full shutdown, so Fast Startup doesn't matter to it.
    inline std::string shutDownWarning(const Status& status, const std::string& pcName)
    {
        if (!status.known) {
            return {};
        }
        if (const Check* blocked = firstWith(status, "blocked", true)) {
            if (blocked->id == "link" && blocked->reason == "wifi") {
                return fill("%1 is on Wi-Fi, so Wake PC can't turn it on again; someone will have to press its power button.", pcName);
            }
            return fill("Wake PC may not turn %1 on again: " + row(*blocked, status, pcName).title + ".", pcName);
        }
        if (const Check* fix = firstWith(status, "fix", true)) {
            return fill("Wake PC may not turn %1 on again: " + row(*fix, status, pcName).title + ". Set Up Wake from Off can fix it.", pcName);
        }
        for (const Check& check : status.checks) {
            if (check.state == "unknown" && (check.id == "link" || check.id == "magicPacket" || check.id == "shutdownWake")) {
                return fill("Wake PC may not turn %1 on again: " + row(check, status, pcName).title + ".", pcName);
            }
        }
        return {};
    }

    // The toast once a PC Wake PC was sent to comes online. secondsSinceWake: since Wake PC was
    // sent. A PC that started after that was off, not asleep.
    inline std::string poweredOnText(const Status& status, long long secondsSinceWake, const std::string& pcName)
    {
        if (!status.known || status.uptimeSeconds < 0 || secondsSinceWake < 0) {
            return fill("%1 is awake", pcName);
        }
        const bool coldBoot = status.uptimeSeconds <= secondsSinceWake + 30;
        if (coldBoot && coldBootByLan(status.lastPowerOn)) {
            return fill("%1 turned on by Wake-on-LAN", pcName);
        }
        if (coldBoot) {
            return fill("%1 is on", pcName);
        }
        return fill("%1 is awake", pcName);
    }

    // The toast once a fix or undo ran
    inline std::string resultText(const Result& result, const std::string& pcName)
    {
        const bool fix = result.action != "undo";
        if (result.ok) {
            if (result.changed == 0) {
                return fill(fix ? "%1's wake settings were already right" : "%1's wake settings were already back", pcName);
            }
            std::string text = fix ? "Changed %1's wake settings" : "Put %1's wake settings back";
            if (result.restartNeeded) {
                text += ". Restart %1 for them to apply.";
            }
            return fill(text, pcName);
        }
        if (result.error == "access_denied") {
            return fill("Apollo on %1 couldn't change its settings. It has to run as its service.", pcName);
        }
        if (result.error == "journal") {
            return fill("Apollo on %1 couldn't save what it would change, so it changed nothing.", pcName);
        }
        if (result.error == "streaming") {
            return fill("%1 started streaming, so nothing changed", pcName);
        }
        if (result.error == "updating") {
            return fill("%1 started installing an Apollo update, so nothing changed", pcName);
        }
        std::string failed;
        for (const std::string& keyword : result.failed) {
            failed += (failed.empty() ? "" : ", ") + keyword;
        }
        if (!failed.empty()) {
            return fill("Couldn't change " + failed + " on %1", pcName);
        }
        return fill(fix ? "%1's wake settings didn't change. Try again." : "%1's wake settings didn't go back. Try again.", pcName);
    }

    // When Apollo refuses a request, or doesn't answer (httpStatus 0)
    inline std::string refusalText(int httpStatus, const std::string& error, const std::string& pcName)
    {
        if (httpStatus == 401) {
            return fill("This Mac doesn't have the Sleep and Shut Down PC permission on %1", pcName);
        }
        if (httpStatus == 404) {
            return fill("%1's Apollo can't set up wake from off", pcName);
        }
        if (httpStatus == 403) {
            return fill("%1 didn't take the request. Try again.", pcName);
        }
        if (httpStatus == 409) {
            if (error == "streaming") {
                return fill("%1 is streaming, so its settings stay as they are", pcName);
            }
            if (error == "updating") {
                return fill("%1 is installing an Apollo update", pcName);
            }
            if (error == "applying") {
                return fill("%1 is already changing its settings", pcName);
            }
            if (error == "nothing") {
                return fill("Nothing to change on %1", pcName);
            }
        }
        if (httpStatus == 0) {
            return fill("%1 didn't answer", pcName);
        }
        return fill("%1 couldn't change its settings", pcName);
    }
}
