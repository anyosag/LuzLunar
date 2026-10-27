#pragma once

#include <cstdint>
#include <string>

#include <sys/types.h>

struct SDL_Window;

// The Cocoa side of multi-display streams (forkmultidisplay.*, forkhelper.*)
namespace MultiDisplayMac
{
    // System Settings › Desktop & Dock › "Displays have separate Spaces"
    bool screensHaveSeparateSpaces();

    // Where a helper's window goes: its display, below the notch on a notched one, in global
    // points with the main display's top-left corner at 0,0 (SDL's and CoreGraphics' coordinates).
    // False if the display is gone.
    bool helperFrame(uint32_t displayId, int& x, int& y, int& width, int& height);

    // For a helper process, before SDL starts its video: no Dock icon, and never the active app.
    // If a click on its window still makes it active, it hands activation straight back to the
    // process that started it (the main stream), so the keyboard stays there.
    void becomeBackgroundApp();

    // The active app's process ID; 0 if none
    pid_t activePid();

    // The active app for the log, "Name (pid 123)"
    std::string activeAppName();

    // Puts a helper's stream window over its display: above the menu bar and the Dock, on every
    // Space, out of Mission Control and the window cycle, without taking the keyboard
    bool placeHelperWindow(SDL_Window* window, uint32_t displayId);
}
