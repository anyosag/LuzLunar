#include "clientdisplay.h"

#include <cmath>
#include <cstdio>

namespace ClientDisplay
{

namespace
{
    // The MacBook Pro's Liquid Retina XDR panel, from Apple's specifications: 1,000 nits sustained
    // full-screen and 1,600 nits peak (HDR content only). Its black level isn't published; mini-LED
    // dimming zones get close to black, and 0.005 nits is an estimate.
    constexpr int k_XdrPeakNits = 1600;
    constexpr int k_XdrFullFrameNits = 1000;
    constexpr int k_XdrMinLuminance = 50;

    // A built-in panel this far above SDR white is an XDR panel. The threshold is a guess until it's
    // checked against what macOS reports on a MacBook Pro, which ForkLaunchArgs logs at each launch.
    constexpr double k_XdrPotential = 15.5;

    // UTF-8 keeps whole characters when cut at a byte that doesn't continue one
    std::string truncateUtf8(const std::string& text, size_t maxBytes)
    {
        if (text.size() <= maxBytes) {
            return text;
        }
        size_t end = maxBytes;
        while (end > 0 && (static_cast<unsigned char>(text[end]) & 0xc0) == 0x80) {
            end--;
        }
        return text.substr(0, end);
    }
}

Description describe(const ForkHwRules::Display& display, bool builtin, int peakNitsOverride)
{
    Description d;
    d.widthMm = display.widthMm;
    d.heightMm = display.heightMm;
    d.panelWidth = display.nativeWidth;
    d.panelHeight = display.nativeHeight;
    d.safeWidth = display.safeWidth ? display.safeWidth : display.nativeWidth;
    d.safeHeight = display.safeHeight ? display.safeHeight : display.nativeHeight;
    d.maxRefresh = display.maxRefresh;
    d.p3 = display.p3;
    d.hdr = display.hdr;
    d.edrPotential = display.edrPotential;
    d.name = truncateUtf8(display.name, 63);

    if (d.hdr) {
        if (peakNitsOverride > 0) {
            d.peakNits = d.fullFrameNits = peakNitsOverride;
        }
        else if (builtin && display.edrPotential >= k_XdrPotential) {
            d.peakNits = k_XdrPeakNits;
            d.fullFrameNits = k_XdrFullFrameNits;
            d.minLuminance = k_XdrMinLuminance;
        }
    }

    return d;
}

std::string percentEncode(const std::string& text)
{
    static const char hex[] = "0123456789ABCDEF";
    std::string out;
    for (unsigned char c : text) {
        bool unreserved = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
                          c == '-' || c == '.' || c == '_' || c == '~';
        if (unreserved) {
            out.push_back(static_cast<char>(c));
        }
        else {
            out.push_back('%');
            out.push_back(hex[c >> 4]);
            out.push_back(hex[c & 0xf]);
        }
    }
    return out;
}

std::string queryArgs(const Description& d)
{
    if (d.panelWidth <= 0 || d.panelHeight <= 0) {
        return {};
    }

    char buffer[256];
    std::string args = "&luzDisplay=1";

    if (d.widthMm > 0 && d.heightMm > 0) {
        std::snprintf(buffer, sizeof(buffer), "&luzMm=%dx%d", d.widthMm, d.heightMm);
        args += buffer;
    }

    std::snprintf(buffer, sizeof(buffer), "&luzPanel=%dx%d&luzSafe=%dx%d", d.panelWidth, d.panelHeight, d.safeWidth, d.safeHeight);
    args += buffer;

    if (d.maxRefresh > 0) {
        std::snprintf(buffer, sizeof(buffer), "&luzHz=%d", d.maxRefresh);
        args += buffer;
    }

    args += d.p3 ? "&luzGamut=p3" : "&luzGamut=srgb";

    // none, unknown (the host picks), or peak,full-screen,black in 1/10000 nits
    if (!d.hdr) {
        args += "&luzHdr=none";
    }
    else if (d.peakNits <= 0) {
        args += "&luzHdr=unknown";
    }
    else {
        std::snprintf(buffer, sizeof(buffer), "&luzHdr=%d,%d,%d", d.peakNits, d.fullFrameNits, d.minLuminance);
        args += buffer;
    }

    std::snprintf(buffer, sizeof(buffer), "&luzEdr=%d", static_cast<int>(std::lround(d.edrPotential * 100)));
    args += buffer;

    if (!d.name.empty()) {
        args += "&luzName=" + percentEncode(d.name);
    }

    return args;
}

std::string primaryArg(bool primary)
{
    return primary ? "&luzPrimary=1" : std::string();
}

}
