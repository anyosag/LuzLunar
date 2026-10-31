#pragma once

#include <functional>
#include <memory>

#include <QString>

#include "SDL_compat.h"

class NvComputer;

// [fork] This Mac's camera as the PC's "Mac Camera", for one stream. ForkStreamExtensions makes one while
// Settings › This Mac › "Use this Mac's camera on the PC" is on and the PC's Apollo offers the camera
// (luzcamera::k_host_feature_flag in the stream's features). It keeps a connection to Apollo for the
// stream (luzcamera.h: a request on the HTTPS port upgraded, with the paired client certificate) on a
// thread of its own with an event loop, since the Qt event loop is paused while streaming. Apollo
// starts the camera (mac/camera_mac.h) when an app on the PC opens Mac Camera, at the size it asked
// for, and stops it a few seconds after the last app closes it; the bitrate follows the connection
// (camerarules.h). What changes (the camera on or off, macOS not allowing it, Apollo refusing) comes
// to the main thread as an SDL event.
class ForkCamera
{
public:
    explicit ForkCamera(NvComputer* computer);
    ~ForkCamera();

    ForkCamera(const ForkCamera&) = delete;
    ForkCamera& operator=(const ForkCamera&) = delete;

    // True when live() changed or a message came; main thread
    bool handleEvent(const SDL_Event& event);

    // The camera is on for the PC now, for the notch bar's dot
    bool live() const { return m_Live; }

    // Messages go to the sink, like LuzLunar's notch bar; without one they're only logged
    void setMessageSink(std::function<bool(const QString&)> sink);

    struct Shared;

private:
    std::shared_ptr<Shared> m_Shared;
    std::function<bool(const QString&)> m_MessageSink;
    bool m_Live = false;
};
