#pragma once

class QWindow;
class StreamingPreferences;

// The stream's fullscreen and scaling rules: where the fork departs from Moonlight's choices
// for how the video fills the screen. Session calls into here at the few points it decides.
namespace ForkVideoScaling
{
    // Whether the stream goes fullscreen in a macOS Space (video below the notch) rather than in
    // a borderless window the size of the screen. upstream is Moonlight's choice, which is kept
    // unless the notch bar needs a Space (see ForkPolicy::useSpacesFullscreen()). Uses the display
    // the stream will open on, which is the one qtWindow is on. Returns upstream where it can't
    // tell, or off macOS.
    bool useSpacesFullscreen(bool upstream, const StreamingPreferences& prefs, QWindow* qtWindow);
}
