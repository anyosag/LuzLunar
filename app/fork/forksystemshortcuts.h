#pragma once

#include "SDL_compat.h"

// While system key capture is on, takes only the Mac shortcuts chosen in Settings from macOS and
// sends them to the host, instead of SDL's keyboard grab, which turns off every system shortcut
// (screenshots included). The groups and ids are in forkmacshortcuts.*.
namespace ForkSystemShortcuts
{
    // Called by ForkStreamExtensions around a stream
    void activate(SDL_Window* window);
    void deactivate();
    void handleEvent(const SDL_Event& event);

    // The keyboard grab to ask SDL for, given upstream's decision (SdlInputHandler::updateKeyboardGrabState).
    // On macOS it's false unless every shortcut goes to the host: the chosen shortcuts are taken here.
    bool keyboardGrab(bool shouldGrab);
}
