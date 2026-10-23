#pragma once

#include <functional>
#include <memory>

#include <QString>

#include "SDL_compat.h"

class NvComputer;

// [fork] This Mac as a network drive on the PC, for one stream (ForkStreamExtensions owns it, while
// Settings › This Mac › "Show this Mac's disk on the PC" is on). When the stream goes over the LAN,
// as ForkNetworkLink decides, Apollo is asked through /actions/drive to map this Mac's disk with the
// account's password from the keychain, and its answer shows beside the notch. Apollo removes the
// drive by itself once the streams end. The rules are macdriverules.h's; macOS's side is
// mac/macdrivesetup.h's. Lives on the SDL main thread; the requests run on a worker thread and come
// back as an SDL event, because the Qt event loop is paused while streaming.
class MacDrive
{
public:
    explicit MacDrive(NvComputer* computer);
    ~MacDrive();

    MacDrive(const MacDrive&) = delete;
    MacDrive& operator=(const MacDrive&) = delete;

    // For ForkNetworkLink::start(): hears whether the stream goes over the LAN, on the probe's
    // thread. Safe to call after this is gone.
    std::function<void(bool viaLan)> linkListener() const;

    // True when the drive tile has something new to show (mapping())
    bool handleEvent(const SDL_Event& event);

    // Whether this Mac is a drive on the PC now, for Stream Control Center. Main thread.
    struct Mapping {
        bool mapped = false;
        QString letter;
        bool homeFolder = false;    // only the home folder could be shared
    };
    Mapping mapping() const;

    // Messages go to the sink, like LuzLunar's notch bar; without one they're only logged, and
    // Settings shows the last
    void setMessageSink(std::function<bool(const QString&)> sink);

    struct Shared;

private:
    std::shared_ptr<Shared> m_Shared;
    std::function<bool(const QString&)> m_MessageSink;
    Mapping m_Mapping;
};
