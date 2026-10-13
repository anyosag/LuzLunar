#pragma once

#include "SDL_compat.h"

// Modifier remapping, e.g. Mac Command -> Ctrl and Control -> Windows key.
// Pure functions on SDL scancodes and modifier masks, so they're easy to test.
namespace ForkKeymap
{
    // What a physical modifier key sends to the host
    enum Target {
        TargetNone = 0,
        TargetCtrl = 1,
        TargetAlt = 2,
        TargetWin = 3,
    };

    // Physical modifier keys that can be remapped (Option is Alt, Command is GUI)
    enum Physical {
        NotModifier = -1,
        PhysicalCtrl = 0,
        PhysicalAlt = 1,
        PhysicalGui = 2,
    };

    struct Map {
        Target target[3]; // indexed by Physical
    };

    // The mapping that sends every key as itself
    Map identity();

    bool isIdentity(const Map& map);

    // Which remappable modifier this scancode is, and whether it's the right-hand one
    Physical classify(SDL_Scancode scancode, bool* right);

    // The scancode to send for a target, keeping the left/right side
    SDL_Scancode targetScancode(Target target, bool right);

    // Rewrites the Ctrl/Alt/GUI bits of an SDL modifier mask according to the map.
    // Shift, Caps Lock, Num Lock and Mode are left alone.
    Uint16 remapModifiers(Uint16 mod, const Map& map);

    // True if a held Ctrl or Option key is mapped to the Windows key, so the Windows
    // modifier must be sent even when system key capture is off.
    bool heldNonGuiMappedToWin(Uint16 mod, const Map& map);
}
