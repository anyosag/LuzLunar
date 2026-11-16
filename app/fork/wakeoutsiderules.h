#pragma once

#include <string>
#include <vector>

// [fork] Wake PC from outside the PC's home network (forkwakeoutside.*, the PC card,
// ForkWakeOutsideDialog.qml and Set Up Wake from Off's last section).
//
// At home Wake PC is a broadcast on the PC's network, which reaches a sleeping network card
// whatever its address. Away, it can only go to the home's own address: the router has to pass it
// on to the PC's LAN address, and to do that it must find which card has that address, which only
// the sleeping card can tell it (ARP offload), and only for the address Windows handed it. These
// rules say where Wake PC goes from where this Mac is, what the card and the toast say, what the
// check from home found (the router passes its own address back in, so a request to it lands where
// one from outside would) and the steps. Free of Qt, so tests build it alone
// (tests/fork/wakeoutsiderules_test.cpp).
namespace WakeOutsideRules
{
    inline std::string fill(std::string text, const std::string& pcName)
    {
        const std::string mark = "%1";
        for (size_t pos = text.find(mark); pos != std::string::npos; pos = text.find(mark, pos + pcName.size())) {
            text.replace(pos, mark.size(), pcName);
        }
        return text;
    }

    // ---- Addresses

    // The four numbers of a dotted IPv4 address; false for anything else (a name, IPv6)
    inline bool ipv4Parts(const std::string& text, unsigned parts[4])
    {
        size_t pos = 0;
        for (int i = 0; i < 4; i++) {
            if (pos >= text.size() || text[pos] < '0' || text[pos] > '9') {
                return false;
            }
            unsigned value = 0;
            size_t digits = 0;
            while (pos < text.size() && text[pos] >= '0' && text[pos] <= '9') {
                value = value * 10 + unsigned(text[pos] - '0');
                pos++;
                if (++digits > 3 || value > 255) {
                    return false;
                }
            }
            parts[i] = value;
            if (i < 3) {
                if (pos >= text.size() || text[pos] != '.') {
                    return false;
                }
                pos++;
            }
        }
        return pos == text.size();
    }

    inline bool isIPv4(const std::string& text)
    {
        unsigned p[4];
        return ipv4Parts(text, p);
    }

    // An IPv4 address the internet can reach: not private (10/8, 172.16/12, 192.168/16), shared
    // (carrier-grade NAT, 100.64/10), loopback, link-local, 0/8, 192.0.0/24 (where macOS puts its
    // 464XLAT address) or multicast and above
    inline bool isPublicIPv4(const std::string& text)
    {
        unsigned p[4];
        if (!ipv4Parts(text, p)) {
            return false;
        }
        return !(p[0] == 0 || p[0] == 10 || p[0] == 127 || p[0] >= 224 ||
                 (p[0] == 100 && p[1] >= 64 && p[1] <= 127) ||
                 (p[0] == 169 && p[1] == 254) ||
                 (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
                 (p[0] == 192 && p[1] == 168) ||
                 (p[0] == 192 && p[1] == 0 && p[2] == 0));
    }

    // A global unicast IPv6 address (2000::/3), as text, maybe in brackets
    inline bool isGlobalIPv6(std::string text)
    {
        if (text.size() > 2 && text.front() == '[' && text.back() == ']') {
            text = text.substr(1, text.size() - 2);
        }
        if (text.find(':') == std::string::npos || text.empty()) {
            return false;
        }
        const char c = text[0];
        return c == '2' || c == '3';
    }

    // The home's address to name and check: the PC's remote address (what Moonlight learned is its
    // address from outside), else the one it was added by when that isn't a local IPv4 address
    // (a public address or a name for it); "" for none
    inline std::string outsideAddress(const std::string& remote, const std::string& manual)
    {
        if (isPublicIPv4(remote)) {
            return remote;
        }
        if (!manual.empty() && (isPublicIPv4(manual) || (!isIPv4(manual) && manual.find(':') == std::string::npos))) {
            return manual;
        }
        return {};
    }

    // ---- Where Wake PC goes

    struct Where {
        bool onLink = false;            // the PC's LAN address is on the link that reaches it (not a VPN)
        bool networkRemembered = false; // that network carried a LAN stream of the PC (forknetworklink)
        bool anyRemembered = false;     // some network did; with none, being on the link has to do
        std::string outsideAddress;     // the home's address from outside (the PC's remote or manual IPv4); "" none
        std::string ipv6Address;        // the PC's global IPv6 address; "" none
    };

    // "home": this Mac is on the PC's home network, so Wake PC is a broadcast there;
    // "outside": away, so it goes to the home's address (and the PC's IPv6) for the router to pass on;
    // "none": away, with no address for the home
    inline std::string route(const Where& w)
    {
        if (w.onLink && (w.networkRemembered || !w.anyRemembered)) {
            return "home";
        }
        if (!w.outsideAddress.empty() || !w.ipv6Address.empty()) {
            return "outside";
        }
        return "none";
    }

    // The address the card names for an outside wake: the IPv4 one, else the IPv6 one
    inline std::string shownAddress(const Where& w)
    {
        return !w.outsideAddress.empty() ? w.outsideAddress : w.ipv6Address;
    }

    // A PC woken from sleep answers within seconds (9 s at home on 2026-11-15); one that was shut
    // down boots first. After this long without an answer, the card says why from outside.
    constexpr long long k_HintSecs = 45;
    constexpr long long k_HintSecsFromOff = 120;

    inline long long hintSecs(bool wasOff)
    {
        return wasOff ? k_HintSecsFromOff : k_HintSecs;
    }

    // ---- The card (one line of about 58 characters on the big card, which adds no period)

    // The waking card's chip; "" keeps the card's own ("Sent from this Mac")
    inline std::string wakingChip(const std::string& route)
    {
        return route == "outside" || route == "none" ? "Away from home" : std::string();
    }

    // The waking card's line; "" keeps the card's own. quiet: no answer for hintSecs().
    inline std::string wakingLine(const std::string& route, const std::string& address, bool quiet)
    {
        if (route == "outside") {
            if (quiet) {
                return "No answer yet. Your router has to pass Wake PC on";
            }
            return "Sent to " + (address.empty() ? std::string("your home's address") : address) + ", for your router to pass on";
        }
        if (route == "none") {
            return "No address for its home from this network";
        }
        return {};
    }

    // A Wake PC away from home that got no answer: the asleep card says so (until the PC answers,
    // Wake PC is sent again, or k_MissedKeepSecs pass), and a toast once
    constexpr long long k_MissedKeepSecs = 15 * 60;

    inline bool missable(const std::string& route)
    {
        return route == "outside" || route == "none";
    }

    // The asleep card's line; "" for a route that keeps the card's own
    inline std::string missedLine(const std::string& route)
    {
        if (route == "outside") {
            return "Wake PC from outside got no answer";
        }
        if (route == "none") {
            return "No address for its home from this network";
        }
        return {};
    }

    // The toast; "" for none
    inline std::string missedToast(const std::string& route, const std::string& pcName)
    {
        if (route == "outside") {
            return fill("%1 didn't answer Wake PC from outside your home network", pcName);
        }
        if (route == "none") {
            return fill("%1 didn't answer: LuzLunar has no address for its home from this network", pcName);
        }
        return {};
    }

    // ---- The check from home

    // What LuzLunar found when it asked the PC through the home's own address from home
    struct Check {
        long long atSecs = 0;               // when (seconds since the epoch); 0 never
        std::string address;                // the home's address it asked through
        bool reached = false;               // the PC answered there
        std::string forwardedTo;            // the LAN address the request reached the PC on (serverinfo's LocalIP)
    };

    // A tag's text in Apollo's serverinfo XML (<uniqueid>, <LocalIP>); "" when it isn't there
    inline std::string xmlValue(const std::string& xml, const std::string& tag)
    {
        const std::string open = "<" + tag + ">";
        const std::string close = "</" + tag + ">";
        const size_t start = xml.find(open);
        if (start == std::string::npos) {
            return {};
        }
        const size_t from = start + open.size();
        const size_t end = xml.find(close, from);
        return end == std::string::npos ? std::string() : xml.substr(from, end - from);
    }

    inline std::string lower(std::string text)
    {
        for (char& c : text) {
            if (c >= 'A' && c <= 'Z') {
                c = char(c - 'A' + 'a');
            }
        }
        return text;
    }

    // Whether serverinfo came from this PC (its uniqueid is LuzLunar's uuid for it)
    inline bool samePc(const std::string& xml, const std::string& uuid)
    {
        return !uuid.empty() && lower(xmlValue(xml, "uniqueid")) == lower(uuid);
    }

    // Whether the check is due: never ran, or ran more than 12 hours ago (30 minutes after one where
    // the home's address didn't reach the PC, which may have been passing), or the PC's LAN address
    // changed since
    constexpr long long k_CheckEverySecs = 12 * 3600;
    constexpr long long k_RecheckMissSecs = 30 * 60;

    inline bool checkDue(const Check& last, long long nowSecs, const std::string& lanAddress, const std::string& lastLanAddress)
    {
        const long long every = last.reached ? k_CheckEverySecs : k_RecheckMissSecs;
        return last.atSecs <= 0 || nowSecs - last.atSecs >= every || lanAddress != lastLanAddress;
    }

    // ---- The steps

    struct Facts {
        std::string pcName;
        std::string lanAddress;     // LuzLunar's LAN address for the PC
        std::string mac;            // aa:bb:cc:dd:ee:ff; "" unknown
        std::string adapter;        // Apollo's name for the network card; "" unknown
        std::string link;           // Apollo's link: ethernet, wifi, virtual, other, none; "" unknown
        std::string outsideAddress; // the home's address; "" none known
        bool atHome = false;        // this Mac is on the PC's home network now
        bool online = false;        // the PC answers now
        std::string checkedWhen;    // "today at 21:52", for the check's row; "" with no check
        Check check;
    };

    struct Row {
        std::string id;
        std::string kind;       // ok (a checkmark), warn (a warning sign) or info
        std::string title;
        std::string detail;
    };

    // The address the router has to find while the PC sleeps: where the check saw it pass the
    // home's address on to, else LuzLunar's LAN address for the PC
    inline std::string target(const Facts& f)
    {
        return f.check.reached && !f.check.forwardedTo.empty() ? f.check.forwardedTo : f.lanAddress;
    }

    inline std::string orElse(const std::string& text, const std::string& fallback)
    {
        return text.empty() ? fallback : text;
    }

    // The line above the steps
    inline std::string intro(const Facts& f)
    {
        if (f.outsideAddress.empty()) {
            return fill("Away from home, Wake PC goes to your home's address, and your router passes it on to %1. "
                        "LuzLunar doesn't know that address yet: it learns it while this Mac and %1 are both at home.", f.pcName);
        }
        return fill("Away from home, Wake PC goes to your home's address, " + f.outsideAddress +
                    ", and your router has to pass it on to %1 while it sleeps. That takes:", f.pcName);
    }

    // The steps, with what LuzLunar knows of each
    inline std::vector<Row> rows(const Facts& f)
    {
        std::vector<Row> out;
        const std::string to = orElse(target(f), "its address");
        const std::string card = orElse(f.adapter, "the network card");
        const std::string ports = "LuzLunar also sends Wake PC to the ports you forward for streaming (UDP 47998 to 48010).";

        // A port forward that reaches the PC
        Row forward;
        forward.id = "forward";
        if (f.check.atSecs > 0 && f.check.reached) {
            forward.kind = "ok";
            forward.title = "Your router passes " + f.check.address + " on to " + orElse(f.check.forwardedTo, f.pcName);
            forward.detail = "Checked from home " + orElse(f.checkedWhen, "earlier") + ". Forward UDP port 9 to " + to +
                             " too, for Wake PC. " + ports;
        }
        else if (f.check.atSecs > 0) {
            forward.kind = "warn";
            forward.title = f.check.address + " didn't reach %1";
            forward.detail = "Checked from home " + orElse(f.checkedWhen, "earlier") + ". In your router, forward UDP port 9 and "
                             "Apollo's ports (TCP 47984, 47989 and 48010, UDP 47998 to 48010) to " + to + ". " +
                             "Some routers don't let devices at home use the home's own address, and then this check can't tell.";
        }
        else {
            forward.kind = "info";
            forward.title = "A port forward to " + to;
            forward.detail = "In your router, forward UDP port 9 to " + to + ". " + ports +
                             " LuzLunar checks the forward when it's at home with %1 on.";
        }
        out.push_back(forward);

        // The sleeping card answers for that address
        Row answer;
        answer.id = "answer";
        if (f.link == "wifi") {
            answer.kind = "warn";
            answer.title = "%1 is on Wi-Fi";
            answer.detail = "A sleeping PC's Wi-Fi is off, so no Wake PC reaches it, from home or from outside. Connect %1 by Ethernet.";
        }
        else if (f.check.reached && !f.check.forwardedTo.empty() && !f.lanAddress.empty() && f.check.forwardedTo != f.lanAddress) {
            // Both answered as this PC: the router's forward lands on one address, LuzLunar finds it at another
            answer.kind = "warn";
            answer.title = "%1's network card has more than one address";
            answer.detail = "Your router passes Wake PC on to " + f.check.forwardedTo + ", and LuzLunar finds %1 at home at " +
                            f.lanAddress + ". Asleep, a card answers your router for only one or two of its addresses, so your "
                            "router may not find " + f.check.forwardedTo + ". Give " + card + " just " + f.check.forwardedTo +
                            ", the address your router passes Wake PC on to, and set its ARP Offload to Enabled (Device "
                            "Manager, the card's Advanced tab).";
        }
        else {
            answer.kind = "info";
            answer.title = "%1's network card answers for " + to + " while it sleeps";
            answer.detail = "In Device Manager, on " + card + "'s Advanced tab, set ARP Offload (and NS Offload) to Enabled. "
                            "Give the card just that one IPv4 address: asleep, a card answers your router for only one or two.";
        }
        out.push_back(answer);

        // Sleep, not off
        Row sleep;
        sleep.id = "sleep";
        sleep.kind = "info";
        sleep.title = "Sleep, not Shut Down, while you're away";
        sleep.detail = "Once %1 is off, or hibernating, its card answers nobody, so your router can pass Wake PC on only if it binds " +
                       to + " to " + orElse(f.mac, "its MAC address") + " (a static ARP entry, which most internet providers' "
                       "routers can't do). Otherwise only a device at home that's always on can turn it on.";
        out.push_back(sleep);

        for (Row& r : out) {
            r.title = fill(r.title, f.pcName);
            r.detail = fill(r.detail, f.pcName);
        }
        return out;
    }

    // The line beside Check Again: why it can't run now; "" when it can
    inline std::string checkBlocker(const Facts& f)
    {
        if (f.outsideAddress.empty()) {
            return fill("LuzLunar needs your home's address first.", f.pcName);
        }
        if (!f.atHome) {
            return fill("LuzLunar checks this from home, with %1 on.", f.pcName);
        }
        if (!f.online) {
            return fill("LuzLunar checks this with %1 on.", f.pcName);
        }
        return {};
    }

    // Shut Down PC's warning while this Mac is away from the PC's home; "" at home
    inline std::string shutDownWarning(const std::string& route, const std::string& pcName)
    {
        if (route == "home") {
            return {};
        }
        return fill("You're away from %1's home network. Once it's off, Wake PC from here can't turn it on again unless your "
                    "router binds its address to its MAC address. Sleep PC can be woken from outside.", pcName);
    }

    // The log line for a Wake PC (the debug channel's log: luz-debug.py luz log -g Wake)
    inline std::string logLine(const std::string& route, const Where& w, const std::string& pcName)
    {
        if (route == "home") {
            return fill("Wake PC to %1: on its home network, a broadcast there", pcName);
        }
        if (route == "none") {
            return fill("Wake PC to %1: away from its home network, with no address for it from outside", pcName);
        }
        std::string via = w.outsideAddress;
        if (!w.ipv6Address.empty()) {
            via += (via.empty() ? "" : " and ") + w.ipv6Address;
        }
        return fill("Wake PC to %1: away from its home network, so through " + via + " for the router to pass on", pcName);
    }
}
