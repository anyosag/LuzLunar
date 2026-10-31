#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "luzcamera.h"

// [fork] The Mac's camera on the PC (camera.h), apart from any I/O: how the camera's bitrate follows
// the connection, which frames go when the connection can't keep up, and what Apollo's answer to the
// connection request means. Plain C++, tested by tests/fork/camerarules_test.cpp.
namespace CameraRules
{
    // Apollo's Camera permission (PERM::client_camera), in serverinfo's <Permission>
    constexpr std::uint32_t k_CameraPermission = 0x00004000;

    // Whether to connect, from what serverinfo says: <LuzCamera>1, and the permission (-1 for an
    // answer without <Permission>, which isn't Apollo's)
    enum class Offer { Connect, NoCamera, NoPermission };
    Offer offer(bool answered, bool camera, long long permissions);

    // The bitrate the encoder gets. START (or BITRATE) sets the most; while more than k_SlowMs of
    // video waits to be sent, the bitrate drops by a third, at most once a second, down to a quarter
    // of the most; once the queue stays under k_FastMs for k_RecoverMs, it rises by a quarter.
    class Bitrate
    {
    public:
        static constexpr int k_SlowMs = 300;
        static constexpr int k_FastMs = 50;
        static constexpr std::int64_t k_StepMs = 1000;
        static constexpr std::int64_t k_RecoverMs = 5000;
        static constexpr std::uint32_t k_FloorKbps = 300;

        // A new most, which is also where it starts
        void start(std::uint32_t kbps, std::int64_t nowMs);

        // BITRATE: a new most; the bitrate now goes down to it if it's above
        void limit(std::uint32_t kbps);

        // How much is queued now; true when current() changed
        bool update(std::size_t queuedBytes, std::int64_t nowMs);

        std::uint32_t current() const { return m_Current; }
        std::uint32_t ceiling() const { return m_Ceiling; }

    private:
        std::uint32_t floor() const;

        std::uint32_t m_Ceiling = 0;
        std::uint32_t m_Current = 0;
        std::int64_t m_LastChangeMs = 0;
        std::int64_t m_FastSinceMs = -1;  // since when the queue has been short; -1 while it isn't
    };

    // How many milliseconds of video a queue holds at a bitrate
    std::int64_t queuedMs(std::size_t queuedBytes, std::uint32_t kbps);

    // Which frames are sent. With more than k_DropMs of video waiting, frames are dropped until the
    // queue is back under k_ResumeMs; the decoder then needs a keyframe, which is asked of the
    // encoder once, and frames before it are dropped too.
    class Queue
    {
    public:
        static constexpr int k_DropMs = 1000;
        static constexpr int k_ResumeMs = 300;

        enum class Verdict {
            Send,
            Drop,
            DropAndAskKeyframe,  // drop it, and have the encoder make the next frame a keyframe
        };

        Verdict frame(bool keyframe, std::size_t queuedBytes, std::uint32_t kbps);

        // The encoder starts again (START): its first frame is a keyframe anyway
        void reset();

    private:
        bool m_Dropping = false;
        bool m_NeedKeyframe = false;
        bool m_Asked = false;
    };

    // What Apollo's answer to the upgrade request means for the stream's connection
    enum class Answer {
        Upgraded,       // 101: the camera's connection
        RetrySoon,      // 403 not_streaming: the stream may not be set up on the PC yet
        RetryLater,     // 409 in_use (another Mac's camera), or a network error
        NoPermission,   // 401: Apollo doesn't give this Mac the Camera permission
        Unsupported,    // 404: an Apollo without the camera, or with it off
    };

    // The status line and body of Apollo's answer ("HTTP/1.1 101 Switching Protocols")
    Answer answer(const std::string& statusLine, const std::string& body);

    // How long to wait before connecting again after the attempt-th failure in a row (from 1)
    int retryDelayMs(Answer answer, int attempt);
}
