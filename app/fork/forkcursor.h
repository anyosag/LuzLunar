#pragma once

#include <memory>
#include <optional>
#include <utility>

#include <QString>

#include "SDL_compat.h"
#include "cursorrules.h"
#include "luzcursor.h"

class ForkBarReach;
class NvComputer;
class SdlInputHandler;
class StreamingPreferences;

namespace ForkCursorMac
{
    class Sprite;
}

// [fork] The PC's pointer drawn by this Mac, in its Windows shape (the I-beam's inverting pixels white
// with a dark outline), as big as the picture shows it, and with none of the stream's latency.
// "Draw the PC's pointer on this Mac" in Settings › Mouse & trackpad, with an Apollo whose
// /serverinfo says <LuzCursor>2: the stream launches with luzCursor=1, Apollo leaves the pointer out
// of the picture, and sends its shapes and where it is (luzcursor.h) on the control stream.
// - Remote desktop mode: the Mac's own cursor over the picture has the PC's shape
//   (ForkCursorMac::createCursor()).
// - Mac trackpad mode: a sprite just above the stream window, moved by the moves sent to the PC
//   (CursorRules::Tracker), each STATE correcting it.
// - Other modes (Mac mouse held for games, Windows touchpad): Apollo draws it, as before, asked with
//   POST /actions/cursor {"draw": "host"}; and back with "client".
// Apollo draws it too on UAC and the lock screen, with Windows Graphics Capture, or with an older
// Apollo, which never gets asked. A multi-display stream draws it on slot 0's window only.
class ForkCursor
{
public:
    // Session, on the main thread before the stream starts: whether to ask, from the setting, what
    // the PC's Apollo can do and the stream's mouse; helperWindow is a multi-display stream's other
    // window, which never draws it
    static void prepare(NvComputer* computer, const StreamingPreferences& prefs, bool helperWindow);

    // On the thread that starts the stream: what the launch adds ("&luzCursor=1"), or nothing
    static QString launchArgument();

    // Session, around the stream's connection (with ForkHostMessages): the cache and the moves start
    // over, and Apollo's messages are read on moonlight-common-c's receive thread
    static void connectionStarting();
    static void connectionStopped();

    // Every move that went to the PC (LiSendMouseMoveEvent() returned 0), on any thread
    static void sentMove(int dx, int dy);

    // ForkStreamExtensions owns one for a stream that asked
    static bool asked();
    ForkCursor(NvComputer* computer, SDL_Window* window, int streamWidth, int streamHeight);
    ~ForkCursor();

    ForkCursor(const ForkCursor&) = delete;
    ForkCursor& operator=(const ForkCursor&) = delete;

    // Apollo's messages and the timers' ticks arrive as SDL events; true when the event was one
    bool handleEvent(const SDL_Event& event);

    // The notch bar's reach (Mac trackpad mode) follows the same pointer
    void setBarReach(ForkBarReach* reach) { m_BarReach = reach; }

    // The notch bar's pulses, on the sprite in the PC's shape; false when the Mac doesn't draw it now
    bool pulse(int count, bool reduceMotion);
    void settlePulse();

    // Where the sprite has the PC's pointer, in the window's points, while it shows
    std::optional<std::pair<double, double>> pointerInWindow() const;

    struct Shared;

private:

    CursorRules::Mode currentMode() const;
    void checkMode();
    void tell(bool macDraws);
    void stateArrived();
    void refresh();
    CursorRules::Rect displayRect() const;
    void applyCursor(SDL_Cursor* cursor);
    void dropCursor();

    std::shared_ptr<Shared> m_Shared;
    SDL_Window* m_Window;
    int m_StreamWidth;
    int m_StreamHeight;
    ForkBarReach* m_BarReach = nullptr;

    CursorRules::Mode m_Mode = CursorRules::Mode::None;
    bool m_ToldMacDraws;            // what Apollo was last told: the Mac draws, or it does
    bool m_StateKnown = false;
    luzcursor::state_t m_State;
    std::shared_ptr<const luzcursor::shape_t> m_Shape;
    bool m_ShapeUsable = false;
    bool m_WasDrawing = false;      // for the log
    bool m_ScreenshotTools = false;
    bool m_CantDraw = false;        // this Mac couldn't make the PC's shape a cursor: the PC draws it

    // Remote desktop mode: the PC's shape as SDL's cursor, for the hash and size it was made for
    SDL_Cursor* m_Cursor = nullptr;
    std::uint64_t m_CursorHash = 0;
    double m_CursorScale = 0;
    SDL_Cursor* m_CursorApplied = nullptr;

    // Mac trackpad mode
    std::unique_ptr<ForkCursorMac::Sprite> m_Sprite;
    std::optional<std::pair<double, double>> m_SpriteAt;
    SDL_TimerID m_EaseTimer = 0;
};
