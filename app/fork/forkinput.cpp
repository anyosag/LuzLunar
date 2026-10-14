#include "forkinput.h"

#include "forkkeymap.h"
#include "forkpreferences.h"

namespace ForkInput
{

bool preprocessKeyEvent(SDL_KeyboardEvent* event, bool& forceGui)
{
    forceGui = false;

    const ForkKeymap::Map& map = ForkPreferences::get()->keyMap();
    if (ForkKeymap::isIdentity(map)) {
        return false;
    }

    bool right;
    ForkKeymap::Physical key = ForkKeymap::classify(event->keysym.scancode, &right);
    if (key != ForkKeymap::NotModifier) {
        ForkKeymap::Target target = map.target[key];
        if (target == ForkKeymap::TargetNone) {
            return true;
        }

        event->keysym.scancode = ForkKeymap::targetScancode(target, right);

        // Decide from the key itself rather than the modifier mask: on key up the key's own bit
        // is already cleared, and the Windows key up must still be sent.
        forceGui = target == ForkKeymap::TargetWin && key != ForkKeymap::PhysicalGui;
    }
    else {
        forceGui = ForkKeymap::heldNonGuiMappedToWin(event->keysym.mod, map);
    }

    event->keysym.mod = ForkKeymap::remapModifiers(event->keysym.mod, map);
    return false;
}

}
