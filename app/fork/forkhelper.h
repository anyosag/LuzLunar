#pragma once

#include <QString>

#include <Limelight.h>

#include "SDL_compat.h"

class QGuiApplication;

// A multi-display stream's helper process (forkmultidisplay.*): LuzLunar started again with
// --luz-helper by the main stream's coordinator (forkdisplaycoordinator.*), to stream one other slot
// of the group onto one display. It only shows video: no Qt window, no Dock icon, no input, no
// audio, no fork extras, and it never keeps the keyboard. It reads the saved settings but never
// writes them. It reports its state as JSON lines on stdout ({"state":"connecting"|"connected"|
// "shown"|"failed"|"ended","error"?}) and ends when its stdin closes or reads {"cmd":"quit"}.
//
//   LuzLunar --luz-helper --host <uuid> --address <addr> --port <http port> --app-id <id>
//            --app-name <name> --group <id> --slot <k> --display <CGDirectDisplayID>
//            --resolution <W>x<H> --fps <F> --bitrate <kbps> --video-codec <VideoCodecConfig> [--hdr]
namespace ForkHelper
{
    // Whether this process was started as a helper
    bool requested(int argc, char* argv[]);

    // The slot it streams, for its log file's name; -1 if it isn't a helper
    int slotFromArguments(int argc, char* argv[]);

    // Before QGuiApplication: Qt's offscreen platform, so Qt never touches AppKit
    void prepareProcess(int argc, char* argv[]);

    // Runs the helper's stream; returns the process's exit code
    int run(QGuiApplication& app);

    // Called by ForkStreamExtensions with the helper's stream window once it exists: places it over
    // its display without taking the keyboard
    void streamWindowCreated(SDL_Window* window);

    // Session's hooks; each does nothing outside a helper
    bool dropsEvent(const SDL_Event& event);           // input never reaches the host
    void silenceAudio(AUDIO_RENDERER_CALLBACKS& callbacks);
    bool windowFrame(int& x, int& y, int& width, int& height);
}
