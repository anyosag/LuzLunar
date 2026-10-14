#include "forkinput.h"

#include "clipboardsync.h"
#include "forkkeymap.h"
#include "forkpreferences.h"
#include "forkstreamextensions.h"

namespace ForkInput
{

namespace
{
    bool matches(const SDL_KeyboardEvent* event, SDL_Keycode keyCode, SDL_Scancode scanCode)
    {
        return event->keysym.sym == keyCode || event->keysym.scancode == scanCode;
    }

    // The fork's own shortcuts. Like Moonlight's, they use the physical Ctrl+Option+Shift keys.
    bool handleForkKeyCombo(const SDL_KeyboardEvent* event)
    {
        if (event->state != SDL_PRESSED ||
                !(event->keysym.mod & KMOD_CTRL) || !(event->keysym.mod & KMOD_ALT) || !(event->keysym.mod & KMOD_SHIFT)) {
            return false;
        }

        ForkStreamExtensions* stream = ForkStreamExtensions::active();
        ClipboardSync* clipboard = stream != nullptr ? stream->clipboard() : nullptr;

        if (matches(event, SDLK_u, SDL_SCANCODE_U)) {
            // Send the local clipboard to the host
            if (clipboard != nullptr) {
                clipboard->sendToHost();
            }
            return true;
        }
        if (matches(event, SDLK_g, SDL_SCANCODE_G)) {
            // Get the host's clipboard
            if (clipboard != nullptr) {
                clipboard->receiveFromHost();
            }
            return true;
        }

        return false;
    }
}

bool preprocessKeyEvent(SDL_KeyboardEvent* event, bool& forceGui)
{
    forceGui = false;

    if (handleForkKeyCombo(event)) {
        return true;
    }

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
