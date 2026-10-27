#pragma once

// Where Windows' pointer goes when the stream first takes the Mac's (SdlInputHandler::setCaptureActive()).
// Mac trackpad mode moves it by deltas only, so without this it stays wherever it was on the PC,
// often on another display, while the Mac's disappears. Kept free of Qt and SDL so it's tested on
// its own (tests/fork/pointersync_test.cpp).
namespace ForkPointerSync
{
    // In the window's points: the picture inside the stream window
    struct Rect {
        int x = 0, y = 0, w = 0, h = 0;
    };

    // In the picture's points, as LiSendMousePositionEvent() takes them with the picture's size
    struct Point {
        int x = 0, y = 0;
    };

    // The Mac pointer's place in the picture, from its place in the window; the picture's centre
    // when it's outside the picture (on another display, or in the notch's strip), which is where
    // macOS's relative mode parks it
    inline Point place(int mouseX, int mouseY, const Rect& picture)
    {
        bool inside = mouseX >= picture.x && mouseX < picture.x + picture.w &&
                      mouseY >= picture.y && mouseY < picture.y + picture.h;
        if (!inside) {
            return Point { picture.w / 2, picture.h / 2 };
        }
        return Point { mouseX - picture.x, mouseY - picture.y };
    }
}
