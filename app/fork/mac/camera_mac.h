#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

// [fork] This Mac's camera for the PC's "Mac Camera" (fork/camera.h). AVFoundation captures the chosen
// camera in NV12 at the size Apollo asks for, about 30 fps, and VideoToolbox encodes it as H.264 for
// real time: low-latency rate control where the Mac has it, no frame reordering, a keyframe when
// asked, into Annex B access units with the SPS and PPS before each keyframe. The camera runs only
// between start() and stop(), so macOS's green light means an app on the PC is using it.
// Thread-safe: each object does its work on dispatch queues of its own.
namespace MacCamera
{
    struct Device {
        std::string id;     // AVCaptureDevice's uniqueID
        std::string name;
    };

    // The Mac's cameras, the one macOS prefers first (which follows Continuity Camera)
    std::vector<Device> devices();

    enum class Access { Allowed, Denied, Undetermined };
    Access access();

    // An encoded frame
    struct Frame {
        const std::uint8_t* data = nullptr;  // one access unit in Annex B, valid during the call
        std::size_t size = 0;
        bool keyframe = false;
        std::uint64_t timeUs = 0;            // when it was captured
        int width = 0;
        int height = 0;
    };

    // H.264 for real time, from NV12 pixel buffers. Frames come out on a VideoToolbox thread.
    class Encoder
    {
    public:
        using Sink = std::function<void(const Frame&)>;

        Encoder(int width, int height, int fps, int kbps, Sink sink);
        ~Encoder();

        Encoder(const Encoder&) = delete;
        Encoder& operator=(const Encoder&) = delete;

        bool valid() const;
        bool lowLatency() const;    // with low-latency rate control

        // pixelBuffer: a CVPixelBufferRef
        void encode(void* pixelBuffer, std::uint64_t timeUs);

        // The next frame is a keyframe; from any thread
        void requestKeyframe();

        void setBitrate(int kbps);

        // Waits for the frames given so far to come out
        void flush();

        struct Impl;

    private:
        std::unique_ptr<Impl> m_Impl;
    };

    enum class State {
        Live,           // capturing
        Stopped,
        Denied,         // macOS doesn't let LuzLunar use the camera
        Unavailable,    // no camera, or it didn't start (the detail says why)
    };

    class Capture
    {
    public:
        using StateSink = std::function<void(State, const std::string& detail)>;

        // frames: on a VideoToolbox thread; state: on the capture's queue
        Capture(Encoder::Sink frames, StateSink state);
        ~Capture();

        Capture(const Capture&) = delete;
        Capture& operator=(const Capture&) = delete;

        // Starts the camera (deviceId empty for the one macOS prefers), or starts it again at another
        // size. Asks macOS for access the first time, which shows its prompt.
        void start(int width, int height, int fps, int kbps, const std::string& deviceId);
        void stop();
        void requestKeyframe();
        void setBitrate(int kbps);

        struct Impl;

    private:
        std::shared_ptr<Impl> m_Impl;  // also held by an access request waiting for macOS's answer
    };
}
