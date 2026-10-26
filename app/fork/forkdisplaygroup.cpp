#include "forkdisplaygroup.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <tuple>

namespace ForkDisplayGroup
{

namespace
{
    // Moonlight's and Apollo's limits for one stream
    constexpr int k_MinBitrateKbps = 2000;
    constexpr int k_MaxBitrateKbps = 500000;
    constexpr int k_MaxSide = 8192;

    // Displays whose edges are this close, in points, touch
    constexpr int k_TouchPoints = 1;

    int evenDown(int value)
    {
        return value & ~1;
    }

    enum class Side { None, Right, Left, Below, Above };

    int overlap(int start1, int length1, int start2, int length2)
    {
        return std::max(0, std::min(start1 + length1, start2 + length2) - std::max(start1, start2));
    }

    // Where d is next to p on the Mac, and how long their shared edge is
    Side touching(const Rect& d, const Rect& p, int& shared)
    {
        shared = 0;
        if (std::abs(d.x - (p.x + p.width)) <= k_TouchPoints) {
            shared = overlap(d.y, d.height, p.y, p.height);
            return shared > 0 ? Side::Right : Side::None;
        }
        if (std::abs(d.x + d.width - p.x) <= k_TouchPoints) {
            shared = overlap(d.y, d.height, p.y, p.height);
            return shared > 0 ? Side::Left : Side::None;
        }
        if (std::abs(d.y - (p.y + p.height)) <= k_TouchPoints) {
            shared = overlap(d.x, d.width, p.x, p.width);
            return shared > 0 ? Side::Below : Side::None;
        }
        if (std::abs(d.y + d.height - p.y) <= k_TouchPoints) {
            shared = overlap(d.x, d.width, p.x, p.width);
            return shared > 0 ? Side::Above : Side::None;
        }
        return Side::None;
    }

    bool overlaps(const Rect& a, const Rect& b)
    {
        return overlap(a.x, a.width, b.x, b.width) > 0 && overlap(a.y, a.height, b.y, b.height) > 0;
    }

    std::string sizeText(int width, int height)
    {
        char buffer[32];
        std::snprintf(buffer, sizeof(buffer), "%dx%d", width, height);
        return buffer;
    }
}

int mainIndex(const std::vector<MacDisplay>& displays)
{
    if (displays.empty()) {
        return -1;
    }

    for (size_t i = 0; i < displays.size(); i++) {
        if (displays[i].isMain && !displays[i].isDisplayExtend) {
            return static_cast<int>(i);
        }
    }
    for (size_t i = 0; i < displays.size(); i++) {
        if (displays[i].isBuiltin && !displays[i].isDisplayExtend) {
            return static_cast<int>(i);
        }
    }
    for (size_t i = 0; i < displays.size(); i++) {
        if (!displays[i].isDisplayExtend) {
            return static_cast<int>(i);
        }
    }
    return 0;
}

Plan plan(const std::vector<MacDisplay>& displays, const Stream& stream, int maxSlots, const std::string& id)
{
    Plan result;
    result.id = id;

    int first = mainIndex(displays);
    if (displays.size() < 2 || maxSlots < 2 || first < 0 || stream.width <= 0 || stream.height <= 0 || stream.fps <= 0) {
        return result;
    }

    // Slot 0 first, then the rest in an order that doesn't change between launches, so each display
    // keeps its slot (Apollo derives a display's identity, and Windows its settings, from the slot).
    // DisplayExtend's display goes last.
    std::vector<size_t> order;
    for (size_t i = 0; i < displays.size(); i++) {
        if (static_cast<int>(i) != first) {
            order.push_back(i);
        }
    }
    std::stable_sort(order.begin(), order.end(), [&displays](size_t a, size_t b) {
        const MacDisplay& da = displays[a];
        const MacDisplay& db = displays[b];
        return std::make_tuple(da.isDisplayExtend, !da.isBuiltin, da.vendor, da.model, da.serial, da.y, da.x) <
               std::make_tuple(db.isDisplayExtend, !db.isBuiltin, db.vendor, db.model, db.serial, db.y, db.x);
    });
    order.insert(order.begin(), static_cast<size_t>(first));
    if (static_cast<int>(order.size()) > maxSlots) {
        order.resize(static_cast<size_t>(maxSlots));
    }

    const double pixelRate0 = static_cast<double>(stream.width) * stream.height * stream.fps;

    for (size_t k = 0; k < order.size(); k++) {
        const MacDisplay& display = displays[order[k]];
        Slot slot;
        slot.slot = static_cast<int>(k);
        slot.displayId = display.id;
        slot.name = display.name;
        slot.external = display.isDisplayExtend;
        slot.screen = display.screen;

        if (k == 0) {
            slot.width = stream.width;
            slot.height = stream.height;
            slot.fps = stream.fps;
            slot.bitrateKbps = stream.bitrateKbps;
            slot.hdr = stream.hdr;
        }
        else {
            slot.width = std::min(evenDown(display.width), k_MaxSide);
            slot.height = std::min(evenDown(display.height), k_MaxSide);
            slot.fps = display.maxRefresh > 0 ? std::min(stream.fps, display.maxRefresh) : stream.fps;
            slot.hdr = stream.hdr && display.hdr;

            double pixelRate = static_cast<double>(slot.width) * slot.height * slot.fps;
            long scaled = std::lround(stream.bitrateKbps * pixelRate / pixelRate0);
            slot.bitrateKbps = static_cast<int>(std::clamp<long>(scaled, k_MinBitrateKbps, k_MaxBitrateKbps));
        }

        if (slot.width <= 0 || slot.height <= 0) {
            // A display whose size can't be read can't be streamed
            continue;
        }
        slot.slot = static_cast<int>(result.slotList.size());
        result.slotList.push_back(slot);
    }

    if (result.slotList.size() < 2) {
        result.slotList.clear();
        return result;
    }

    // Arrange the Windows displays like the Mac's
    std::vector<Rect> mac, pixels;
    for (const Slot& slot : result.slotList) {
        for (const MacDisplay& display : displays) {
            if (display.id == slot.displayId) {
                mac.push_back({ display.x, display.y, display.pointWidth, display.pointHeight });
                break;
            }
        }
        pixels.push_back({ 0, 0, slot.width, slot.height });
    }
    std::vector<Rect> layout = windowsLayout(mac, pixels, 0);
    for (size_t k = 0; k < result.slotList.size(); k++) {
        result.slotList[k].x = layout[k].x;
        result.slotList[k].y = layout[k].y;
    }

    return result;
}

std::vector<Rect> windowsLayout(const std::vector<Rect>& mac, const std::vector<Rect>& pixels, size_t first)
{
    const size_t n = std::min(mac.size(), pixels.size());
    std::vector<Rect> placed(n);
    std::vector<bool> done(n, false);
    if (first >= n) {
        return placed;
    }

    placed[first] = { 0, 0, pixels[first].width, pixels[first].height };
    done[first] = true;

    auto rowEnd = [&]() {
        int right = 0;
        for (size_t i = 0; i < n; i++) {
            if (done[i]) {
                right = std::max(right, placed[i].x + placed[i].width);
            }
        }
        return right;
    };

    auto fits = [&](const Rect& candidate) {
        for (size_t i = 0; i < n; i++) {
            if (done[i] && overlaps(candidate, placed[i])) {
                return false;
            }
        }
        return true;
    };

    for (;;) {
        // The next display: one touching a placed display, the longest shared edge first
        size_t best = n, neighbour = n;
        Side bestSide = Side::None;
        int bestShared = 0;
        for (size_t d = 0; d < n; d++) {
            if (done[d]) {
                continue;
            }
            for (size_t p = 0; p < n; p++) {
                if (!done[p]) {
                    continue;
                }
                int shared = 0;
                Side side = touching(mac[d], mac[p], shared);
                if (side != Side::None && shared > bestShared) {
                    best = d;
                    neighbour = p;
                    bestSide = side;
                    bestShared = shared;
                }
            }
        }
        if (best == n) {
            break;
        }

        const Rect& d = mac[best];
        const Rect& p = mac[neighbour];
        const Rect& at = placed[neighbour];
        Rect candidate { 0, 0, pixels[best].width, pixels[best].height };

        if (bestSide == Side::Right || bestSide == Side::Left) {
            double fraction = p.height > 0 ? static_cast<double>(d.y - p.y) / p.height : 0;
            candidate.x = bestSide == Side::Right ? at.x + at.width : at.x - candidate.width;
            candidate.y = at.y + static_cast<int>(std::lround(fraction * at.height));
            // Still touching after the scale changes
            candidate.y = std::clamp(candidate.y, at.y - candidate.height + 1, at.y + at.height - 1);
        }
        else {
            double fraction = p.width > 0 ? static_cast<double>(d.x - p.x) / p.width : 0;
            candidate.y = bestSide == Side::Below ? at.y + at.height : at.y - candidate.height;
            candidate.x = at.x + static_cast<int>(std::lround(fraction * at.width));
            candidate.x = std::clamp(candidate.x, at.x - candidate.width + 1, at.x + at.width - 1);
        }

        if (!fits(candidate)) {
            candidate.x = rowEnd();
            candidate.y = 0;
        }
        placed[best] = candidate;
        done[best] = true;
    }

    // Displays that touch nothing placed (can't happen on a Mac, whose displays always touch)
    for (size_t i = 0; i < n; i++) {
        if (!done[i]) {
            placed[i] = { rowEnd(), 0, pixels[i].width, pixels[i].height };
            done[i] = true;
        }
    }

    // Slot 0 stays at 0,0: Windows makes the display there the primary one
    return placed;
}

std::string jsonString(const std::string& text)
{
    std::string out = "\"";
    for (unsigned char c : text) {
        switch (c) {
        case '"':
            out += "\\\"";
            break;
        case '\\':
            out += "\\\\";
            break;
        case '\n':
            out += "\\n";
            break;
        case '\r':
            out += "\\r";
            break;
        case '\t':
            out += "\\t";
            break;
        default:
            if (c < 0x20) {
                char buffer[8];
                std::snprintf(buffer, sizeof(buffer), "\\u%04x", c);
                out += buffer;
            }
            else {
                out.push_back(static_cast<char>(c));
            }
        }
    }
    out += "\"";
    return out;
}

std::string screenJson(const ClientDisplay::Description& d)
{
    std::string out = "{";
    if (d.widthMm > 0 && d.heightMm > 0) {
        out += "\"mm\":" + jsonString(sizeText(d.widthMm, d.heightMm)) + ",";
    }
    out += "\"panel\":" + jsonString(sizeText(d.panelWidth, d.panelHeight));
    out += ",\"safe\":" + jsonString(sizeText(d.safeWidth, d.safeHeight));
    if (d.maxRefresh > 0) {
        out += ",\"hz\":" + jsonString(std::to_string(d.maxRefresh));
    }
    out += std::string(",\"gamut\":") + (d.p3 ? "\"p3\"" : "\"srgb\"");

    if (!d.hdr) {
        out += ",\"hdr\":\"none\"";
    }
    else if (d.peakNits <= 0) {
        out += ",\"hdr\":\"unknown\"";
    }
    else {
        char buffer[64];
        std::snprintf(buffer, sizeof(buffer), "%d,%d,%d", d.peakNits, d.fullFrameNits, d.minLuminance);
        out += ",\"hdr\":" + jsonString(buffer);
    }

    if (!d.name.empty()) {
        out += ",\"name\":" + jsonString(d.name);
    }
    out += "}";
    return out;
}

std::string declarationJson(const Plan& plan)
{
    std::string out = "{\"v\":1,\"id\":" + jsonString(plan.id) + ",\"slots\":[";
    for (size_t i = 0; i < plan.slotList.size(); i++) {
        const Slot& slot = plan.slotList[i];
        char buffer[160];
        if (i > 0) {
            out += ",";
        }

        if (slot.slot == 0) {
            // Slot 0's mode and screen come with its launch's usual arguments
            std::snprintf(buffer, sizeof(buffer), "{\"slot\":0,\"x\":%d,\"y\":%d}", slot.x, slot.y);
            out += buffer;
            continue;
        }

        std::snprintf(buffer, sizeof(buffer),
                      "{\"slot\":%d,\"w\":%d,\"h\":%d,\"fps\":%d,\"x\":%d,\"y\":%d,\"external\":%s,\"hdr\":%s,\"screen\":",
                      slot.slot, slot.width, slot.height, slot.fps, slot.x, slot.y,
                      slot.external ? "true" : "false", slot.hdr ? "true" : "false");
        out += buffer;
        out += screenJson(slot.screen);
        out += "}";
    }
    out += "]}";
    return out;
}

std::string base64Url(const std::string& bytes)
{
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string out;
    size_t i = 0;
    for (; i + 2 < bytes.size(); i += 3) {
        uint32_t chunk = (static_cast<unsigned char>(bytes[i]) << 16) | (static_cast<unsigned char>(bytes[i + 1]) << 8) |
                         static_cast<unsigned char>(bytes[i + 2]);
        out.push_back(alphabet[(chunk >> 18) & 0x3f]);
        out.push_back(alphabet[(chunk >> 12) & 0x3f]);
        out.push_back(alphabet[(chunk >> 6) & 0x3f]);
        out.push_back(alphabet[chunk & 0x3f]);
    }
    if (i + 1 == bytes.size()) {
        uint32_t chunk = static_cast<unsigned char>(bytes[i]) << 16;
        out.push_back(alphabet[(chunk >> 18) & 0x3f]);
        out.push_back(alphabet[(chunk >> 12) & 0x3f]);
    }
    else if (i + 2 == bytes.size()) {
        uint32_t chunk = (static_cast<unsigned char>(bytes[i]) << 16) | (static_cast<unsigned char>(bytes[i + 1]) << 8);
        out.push_back(alphabet[(chunk >> 18) & 0x3f]);
        out.push_back(alphabet[(chunk >> 12) & 0x3f]);
        out.push_back(alphabet[(chunk >> 6) & 0x3f]);
    }
    return out;
}

std::string launchArgs(const Plan& plan)
{
    if (plan.slotList.size() < 2) {
        return {};
    }
    return "&luzGroup=" + base64Url(declarationJson(plan));
}

std::string joinArgs(const std::string& id, int slot)
{
    // The id is hex digits, so it needs no encoding
    return "&luzGroupId=" + id + "&luzSlot=" + std::to_string(slot);
}

}
