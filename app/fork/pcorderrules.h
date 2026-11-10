#pragma once

// [fork] The order of the PCs in Your PCs: the PC kept first, then the order the person dragged them
// into, then the rest by name. Free of Qt, so tests build it alone (tests/fork/pcorderrules_test.cpp).
#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>
#include <utility>
#include <vector>

namespace PcOrderRules
{
    inline std::string lower(std::string text)
    {
        std::transform(text.begin(), text.end(), text.begin(),
                       [](unsigned char c) { return (char)std::tolower(c); });
        return text;
    }

    // The uuids of `pcs` (uuid, name pairs) in display order: the PC kept first if it is among them,
    // then the ones in `order`, then the rest by name without regard to case, ties in input order.
    // Uuids in `order` that aren't in `pcs`, and repeats, are ignored.
    inline std::vector<std::string> sorted(const std::vector<std::pair<std::string, std::string>>& pcs,
                                           const std::string& keepFirst,
                                           const std::vector<std::string>& order)
    {
        auto find = [&pcs](const std::string& uuid) {
            for (size_t i = 0; i < pcs.size(); i++) {
                if (pcs[i].first == uuid) {
                    return (int)i;
                }
            }
            return -1;
        };

        std::vector<std::string> result;
        std::vector<bool> placed(pcs.size(), false);
        auto place = [&](const std::string& uuid) {
            const int i = find(uuid);
            if (i >= 0 && !placed[i]) {
                placed[i] = true;
                result.push_back(pcs[i].first);
            }
        };

        if (!keepFirst.empty()) {
            place(keepFirst);
        }
        for (const std::string& uuid : order) {
            place(uuid);
        }

        std::vector<size_t> rest;
        for (size_t i = 0; i < pcs.size(); i++) {
            if (!placed[i]) {
                rest.push_back(i);
            }
        }
        std::stable_sort(rest.begin(), rest.end(), [&pcs](size_t a, size_t b) {
            return lower(pcs[a].second) < lower(pcs[b].second);
        });
        for (size_t i : rest) {
            result.push_back(pcs[i].first);
        }
        return result;
    }

    // The list with list[from] moved to position `to`; out of range returns it unchanged
    inline std::vector<std::string> moved(const std::vector<std::string>& list, size_t from, size_t to)
    {
        if (from >= list.size() || to >= list.size()) {
            return list;
        }
        std::vector<std::string> result = list;
        const std::string item = result[from];
        result.erase(result.begin() + (std::ptrdiff_t)from);
        result.insert(result.begin() + (std::ptrdiff_t)to, item);
        return result;
    }

    // A new order whose first PC isn't the one kept first ends "keep it first"
    inline bool dropsKeepFirst(const std::vector<std::string>& newOrder, const std::string& keepFirst)
    {
        return !keepFirst.empty() && !newOrder.empty() && newOrder[0] != keepFirst;
    }
}
