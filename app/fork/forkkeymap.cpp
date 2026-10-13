#include "forkkeymap.h"

#include <initializer_list>

namespace ForkKeymap
{

namespace
{
    Uint16 modifierBit(int kind, bool right)
    {
        switch (kind) {
        case PhysicalCtrl:
            return right ? KMOD_RCTRL : KMOD_LCTRL;
        case PhysicalAlt:
            return right ? KMOD_RALT : KMOD_LALT;
        case PhysicalGui:
            return right ? KMOD_RGUI : KMOD_LGUI;
        default:
            return 0;
        }
    }

    Uint16 targetBit(Target target, bool right)
    {
        switch (target) {
        case TargetCtrl:
            return modifierBit(PhysicalCtrl, right);
        case TargetAlt:
            return modifierBit(PhysicalAlt, right);
        case TargetWin:
            return modifierBit(PhysicalGui, right);
        default:
            return 0;
        }
    }
}

Map identity()
{
    return Map { { TargetCtrl, TargetAlt, TargetWin } };
}

bool isIdentity(const Map& map)
{
    return map.target[PhysicalCtrl] == TargetCtrl &&
           map.target[PhysicalAlt] == TargetAlt &&
           map.target[PhysicalGui] == TargetWin;
}

Physical classify(SDL_Scancode scancode, bool* right)
{
    switch (scancode) {
    case SDL_SCANCODE_LCTRL:
    case SDL_SCANCODE_RCTRL:
        *right = scancode == SDL_SCANCODE_RCTRL;
        return PhysicalCtrl;
    case SDL_SCANCODE_LALT:
    case SDL_SCANCODE_RALT:
        *right = scancode == SDL_SCANCODE_RALT;
        return PhysicalAlt;
    case SDL_SCANCODE_LGUI:
    case SDL_SCANCODE_RGUI:
        *right = scancode == SDL_SCANCODE_RGUI;
        return PhysicalGui;
    default:
        *right = false;
        return NotModifier;
    }
}

SDL_Scancode targetScancode(Target target, bool right)
{
    switch (target) {
    case TargetCtrl:
        return right ? SDL_SCANCODE_RCTRL : SDL_SCANCODE_LCTRL;
    case TargetAlt:
        return right ? SDL_SCANCODE_RALT : SDL_SCANCODE_LALT;
    case TargetWin:
        return right ? SDL_SCANCODE_RGUI : SDL_SCANCODE_LGUI;
    default:
        return SDL_SCANCODE_UNKNOWN;
    }
}

Uint16 remapModifiers(Uint16 mod, const Map& map)
{
    Uint16 out = mod & ~(KMOD_CTRL | KMOD_ALT | KMOD_GUI);

    for (int kind = PhysicalCtrl; kind <= PhysicalGui; kind++) {
        for (bool right : { false, true }) {
            if (mod & modifierBit(kind, right)) {
                out |= targetBit(map.target[kind], right);
            }
        }
    }

    return out;
}

bool heldNonGuiMappedToWin(Uint16 mod, const Map& map)
{
    for (int kind : { PhysicalCtrl, PhysicalAlt }) {
        if (map.target[kind] == TargetWin &&
                (mod & (modifierBit(kind, false) | modifierBit(kind, true)))) {
            return true;
        }
    }

    return false;
}

}
