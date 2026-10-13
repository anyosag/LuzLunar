#pragma once

#include "SDL_compat.h"

namespace ForkInput
{
    // Called from SdlInputHandler::handleKeyEvent() after Moonlight's own Ctrl+Alt+Shift
    // shortcuts were checked, so those keep working on the physical keys.
    //
    // Applies the modifier remapping by rewriting the event's scancode and modifier mask.
    // Sets forceGui when the result includes a Windows key that must be sent even though
    // system key capture is off (because it comes from Ctrl or Option, not Command).
    //
    // Returns true if the key is mapped to "nothing" and must not be sent.
    bool preprocessKeyEvent(SDL_KeyboardEvent* event, bool& forceGui);
}
