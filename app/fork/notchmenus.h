#pragma once

#include <algorithm>
#include <vector>

// [fork] The notch bar's menus without AppKit (mac/notchmenus_mac.mm draws them), so tests can build
// it alone: what the menus can do, how the keyboard moves through them, and how the bar's items share
// the strip beside the notch.
namespace NotchMenus
{
    // What a menu row or tile does. The bar hands these to the stream's event loop
    // (ForkStreamExtensions), which does them between events.
    enum class Action {
        None,
        Disconnect,                 // end the stream; the app keeps running on the PC, unless Settings quits it after a stream
        DisconnectAndQuitLuzLunar,  // the same, then quit LuzLunar
        QuitAppOnPc,                // end the stream and quit the app on the PC
        QuitAndSleepPc,             // end the stream, then the PC quits the app and sleeps
        ToggleMouseCapture,         // Ctrl+Option+Shift+Z
        ToggleSystemKeys,           // Ctrl+Option+Shift+K: Mac shortcuts go to the PC, or stay on the Mac
        MenusOpened,                // a menu opened: the pointer stays free while one is open
        MenusClosed,                // the last menu closed: the pointer goes back if opening freed it
        BarShownOrHidden,           // the bar came on screen or went: the pointer is held to the picture only without it
    };

    // The bar's menus, left to right as their items sit on the bar
    enum class Menu {
        None,
        Session,
        ControlCenter,
    };

    // The menus in the bar's order, for Left and Right between them
    inline const std::vector<Menu>& order()
    {
        static const std::vector<Menu> menus = { Menu::Session, Menu::ControlCenter };
        return menus;
    }

    // The menu step places from this one, wrapping; None for None
    inline Menu neighbour(Menu menu, int step)
    {
        const std::vector<Menu>& menus = order();
        auto it = std::find(menus.begin(), menus.end(), menu);
        if (it == menus.end() || menus.empty()) {
            return Menu::None;
        }
        int count = static_cast<int>(menus.size());
        int index = static_cast<int>(it - menus.begin());
        return menus[static_cast<size_t>(((index + step) % count + count) % count)];
    }

    // The next row the keyboard can select, from `from` in steps of `step` (+1 down, -1 up), wrapping.
    // from -1 starts before the first row going down, or after the last going up. -1 when no row can be
    // selected.
    template<typename Selectable>
    int nextSelectable(int count, int from, int step, Selectable&& selectable)
    {
        if (count <= 0 || step == 0) {
            return -1;
        }
        step = step > 0 ? 1 : -1;
        int start = from;
        if (start < 0 || start >= count) {
            start = step > 0 ? -1 : count;
        }
        for (int i = 1; i <= count; i++) {
            int index = ((start + step * i) % count + count) % count;
            if (selectable(index)) {
                return index;
            }
        }
        return -1;
    }

    // Items on the right of the notch, laid out from the screen's right edge towards the notch. Each
    // gets its natural width while they fit; when they don't, the shrinkable one (the stats) gives up
    // width first, and goes once it would be narrower than minShrunk; only then are the others cut
    // from the notch side.
    struct Placed {
        double x = 0;       // from the area's left edge
        double width = 0;   // 0: not shown
    };

    inline std::vector<Placed> layoutRight(double areaWidth, double margin, double gap,
                                           const std::vector<double>& widths, int shrinkable,
                                           double minShrunk = 24)
    {
        std::vector<Placed> placed(widths.size());
        int count = static_cast<int>(widths.size());
        double room = std::max(areaWidth - 2 * margin, 0.0);

        std::vector<double> given(widths.begin(), widths.end());
        auto total = [&]() {
            double sum = 0;
            int shown = 0;
            for (double width : given) {
                if (width > 0) {
                    sum += width;
                    shown++;
                }
            }
            return sum + gap * std::max(shown - 1, 0);
        };

        if (total() > room && shrinkable >= 0 && shrinkable < count) {
            double over = total() - room;
            given[static_cast<size_t>(shrinkable)] = std::max(given[static_cast<size_t>(shrinkable)] - over, 0.0);
            if (given[static_cast<size_t>(shrinkable)] < minShrunk) {
                given[static_cast<size_t>(shrinkable)] = 0;
            }
        }
        // Still too wide: drop items from the notch side (the first) until it fits
        for (int i = 0; i < count && total() > room; i++) {
            given[static_cast<size_t>(i)] = 0;
        }

        double x = margin + room;
        for (int i = count - 1; i >= 0; i--) {
            double width = given[static_cast<size_t>(i)];
            if (width <= 0) {
                continue;
            }
            x -= width;
            placed[static_cast<size_t>(i)] = { x, width };
            x -= gap;
        }
        return placed;
    }
}
