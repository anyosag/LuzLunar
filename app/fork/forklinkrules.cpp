#include "forklinkrules.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace ForkLinkRules
{
namespace
{
    const char* kindName(Kind kind)
    {
        switch (kind) {
        case Kind::Ethernet:
            return "Ethernet";
        case Kind::WiFi:
            return "Wi-Fi";
        case Kind::ThunderboltBridge:
            return "Thunderbolt Bridge";
        case Kind::Vpn:
            return "VPN";
        case Kind::Other:
        case Kind::Unknown:
            break;
        }
        return "";
    }

    void append(std::string& text, const std::string& part)
    {
        if (!part.empty()) {
            text += (text.empty() ? "" : " ") + part;
        }
    }
}

std::string bandText(double ghz)
{
    if (!(ghz > 0)) {
        return std::string();
    }
    char text[16];
    if (std::fabs(ghz - std::round(ghz)) < 0.05) {
        std::snprintf(text, sizeof(text), "%.0f GHz", ghz);
    }
    else {
        std::snprintf(text, sizeof(text), "%.1f GHz", ghz);
    }
    return text;
}

bool viaLan(Reachability reachability, bool onLink, Kind routeKind)
{
    if (routeKind == Kind::Vpn || reachability == Reachability::Vpn) {
        return false;
    }
    if (reachability == Reachability::Lan) {
        return true;
    }
    return onLink;
}

bool shouldShow(bool viaLan, bool networkRemembered)
{
    return viaLan || networkRemembered;
}

bool lanAddressFirst(bool onLink, Kind routeKind, bool networkRemembered)
{
    return onLink && routeKind != Kind::Vpn && networkRemembered;
}

std::string speedText(double mbps)
{
    if (!(mbps > 0)) {
        return std::string();
    }
    char text[24];
    if (mbps >= 1000) {
        double gbps = mbps / 1000;
        if (std::fabs(gbps - std::round(gbps)) < 0.05) {
            std::snprintf(text, sizeof(text), "%.0f Gb/s", gbps);
        }
        else {
            std::snprintf(text, sizeof(text), "%.1f Gb/s", gbps);
        }
    }
    else {
        std::snprintf(text, sizeof(text), "%.0f Mb/s", std::max(1.0, std::round(mbps)));
    }
    return text;
}

std::string badge(const Link& link, bool notViaLan)
{
    std::string text;
    switch (link.kind) {
    case Kind::Unknown:
        return std::string();
    case Kind::Ethernet:
    case Kind::ThunderboltBridge:
        text = kindName(link.kind);
        append(text, speedText(link.mbps));
        break;
    case Kind::WiFi:
        text = kindName(link.kind);
        append(text, bandText(link.bandGHz));
        append(text, speedText(link.mbps));
        break;
    case Kind::Vpn:
        text = kindName(link.kind);
        if (link.underlying != Kind::Unknown && link.underlying != Kind::Vpn && link.underlying != Kind::Other) {
            text += std::string(" over ") + kindName(link.underlying);
        }
        break;
    case Kind::Other:
        text = link.name.empty() ? std::string("Network") : link.name;
        append(text, speedText(link.mbps));
        break;
    }
    if (notViaLan) {
        text += " · not via LAN";
    }
    return text;
}

std::string connectionText(const Link& link, bool viaLan)
{
    std::string text;
    switch (link.kind) {
    case Kind::Unknown:
        return std::string();
    case Kind::Ethernet:
    case Kind::ThunderboltBridge:
        text = kindName(link.kind);
        break;
    case Kind::WiFi:
        text = kindName(link.kind);
        append(text, bandText(link.bandGHz));
        break;
    case Kind::Vpn:
        text = kindName(link.kind);
        if (link.underlying != Kind::Unknown && link.underlying != Kind::Vpn && link.underlying != Kind::Other) {
            text += std::string(" over ") + kindName(link.underlying);
        }
        break;
    case Kind::Other:
        text = link.name.empty() ? std::string("Network") : link.name;
        break;
    }
    return text + (viaLan ? " · LAN" : " · not via LAN");
}

std::vector<std::string> remember(std::vector<std::string> ids, const std::string& id, std::size_t max)
{
    if (id.empty() || max == 0) {
        return ids;
    }
    ids.erase(std::remove(ids.begin(), ids.end(), id), ids.end());
    ids.insert(ids.begin(), id);
    if (ids.size() > max) {
        ids.resize(max);
    }
    return ids;
}

bool remembered(const std::vector<std::string>& ids, const std::string& id)
{
    return !id.empty() && std::find(ids.begin(), ids.end(), id) != ids.end();
}
}
