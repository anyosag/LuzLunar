#pragma once

class QWindow;
class StreamingPreferences;
struct SDL_Window;

// The stream's fullscreen and scaling rules: where the fork departs from Moonlight's choices
// for how the video fills the screen. Session calls into here at the few points it decides.
namespace ForkVideoScaling
{
    // Whether the stream goes fullscreen in a macOS Space (video below the notch) rather than in
    // a borderless window the size of the screen (video under the notch). upstream is Moonlight's
    // choice; on a notched display the stream's aspect ratio and the notch bar decide instead (see
    // ForkPolicy::useSpacesFullscreen()). Uses the display the stream will open on, which is the
    // one qtWindow is on. Returns upstream where it can't tell, or off macOS.
    bool useSpacesFullscreen(bool upstream, const StreamingPreferences& prefs, QWindow* qtWindow);

    // The index of the display qtWindow is on (the primary one without a window), in the order
    // StreamUtils and ClientHardware use; -1 if it can't tell, or off macOS
    int displayIndexFor(QWindow* qtWindow);

    // Called by ForkStreamExtensions around a stream: window is the stream's window, and stretch is
    // the session's fullscreenStretch preference. Stretching is off outside that span.
    void activate(SDL_Window* window, bool stretch);
    void deactivate();

    // Whether the video fills the window, distorted, rather than fitting with black bars. True
    // while the session's stretch preference is on and the window is fullscreen (either kind), so
    // a windowed stream always fits. Cheap and thread safe: renderers call it from their render
    // threads and the main thread calls it for the mouse mapping. Logs when the value changes.
    bool stretchActive();
}
