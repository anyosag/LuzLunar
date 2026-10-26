#pragma once

#include "SDL_compat.h"

namespace ForkInput
{
    // Called from SdlInputHandler::handleKeyEvent() after Moonlight's own Ctrl+Alt+Shift
    // shortcuts were checked, so those keep working on the physical keys.
    //
    // Handles the fork's own Ctrl+Option+Shift shortcuts (U: send clipboard, G: get clipboard,
    // N: the notch bar's menus), gives the keys that move through an open notch bar menu to the menu,
    // then applies the modifier remapping by rewriting the event's scancode and modifier mask.
    // Sets forceGui when the result includes a Windows key that must be sent even though
    // system key capture is off (because it comes from Ctrl or Option, not Command).
    //
    // Returns true if the key was a fork shortcut or is mapped to "nothing", and must not be sent.
    bool preprocessKeyEvent(SDL_KeyboardEvent* event, bool& forceGui);
}
