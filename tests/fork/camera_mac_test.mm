// The Mac camera's encoder on the CI Mac (app/fork/mac/camera_mac.h): NV12 frames in, H.264 out as the PC's
// decoder takes it (Annex B, the SPS and PPS before each keyframe, a keyframe when asked), at both sizes.
// CI Macs have no camera, so capture itself isn't tried; the camera list and access only mustn't fail.
// Skips when VideoToolbox has no H.264 encoder here.
//   clang++ -std=c++17 -Iapp tests/fork/camera_mac_test.mm app/fork/mac/camera_mac.mm \
//     -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox -framework Foundation

#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

#include <cstdio>
#include <cstring>
#include <mutex>
#include <vector>

#include "fork/luzcamera.h"
#include "fork/mac/camera_mac.h"

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

struct Got {
    std::vector<uint8_t> data;
    bool keyframe;
    uint64_t timeUs;
    int width;
    int height;
};

// An NV12 frame with a pattern that moves with i, so each frame has something new to encode
static CVPixelBufferRef makeFrame(int width, int height, int i)
{
    NSDictionary* attributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVPixelBufferRef buffer = nullptr;
    if (CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            (CFDictionaryRef)attributes, &buffer) != kCVReturnSuccess) {
        return nullptr;
    }
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t* luma = static_cast<uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(buffer, 0));
    size_t lumaPitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            luma[y * lumaPitch + x] = static_cast<uint8_t>(16 + ((x + y + i * 8) % 200));
        }
    }
    uint8_t* chroma = static_cast<uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(buffer, 1));
    size_t chromaPitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
    for (int y = 0; y < height / 2; y++) {
        std::memset(chroma + y * chromaPitch, 128, width);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return buffer;
}

static bool encodeSize(int width, int height, int kbps)
{
    std::mutex lock;
    std::vector<Got> got;
    MacCamera::Encoder encoder(width, height, 30, kbps, [&](const MacCamera::Frame& frame) {
        std::lock_guard<std::mutex> guard(lock);
        got.push_back({std::vector<uint8_t>(frame.data, frame.data + frame.size), frame.keyframe, frame.timeUs, frame.width, frame.height});
    });
    if (!encoder.valid()) {
        std::printf("camera_mac_test: skipped, VideoToolbox has no H.264 encoder here\n");
        return false;
    }
    std::printf("camera_mac_test: %dx%d, %s rate control\n", width, height, encoder.lowLatency() ? "low-latency" : "the usual");

    const int frames = 40;
    for (int i = 0; i < frames; i++) {
        @autoreleasepool {
            if (i == 25) {
                encoder.requestKeyframe();
            }
            CVPixelBufferRef buffer = makeFrame(width, height, i);
            CHECK(buffer != nullptr);
            if (buffer != nullptr) {
                encoder.encode(buffer, 1000000ull + static_cast<uint64_t>(i) * 33333);
                CVPixelBufferRelease(buffer);
            }
        }
    }
    encoder.flush();

    std::lock_guard<std::mutex> guard(lock);
    CHECK(got.size() >= frames - 5);
    if (got.empty()) {
        return true;
    }
    // The first is a keyframe the PC's decoder can start from
    CHECK(got[0].keyframe);
    CHECK(luzcamera::is_decodable_keyframe(got[0].data.data(), got[0].data.size()));
    CHECK(got[0].width == width && got[0].height == height);
    CHECK(got[0].timeUs == 1000000);
    size_t keyframes = 0;
    bool askedKeyframe = false;
    for (size_t i = 0; i < got.size(); i++) {
        const Got& g = got[i];
        // Annex B throughout, with no reordering: the timestamps only go up
        CHECK(g.data.size() > 4 && g.data[0] == 0 && g.data[1] == 0 && g.data[2] == 0 && g.data[3] == 1);
        CHECK(luzcamera::for_each_nal(g.data.data(), g.data.size(), [](int, const uint8_t*, size_t) {}) >= 1);
        if (i > 0) {
            CHECK(g.timeUs > got[i - 1].timeUs);
        }
        if (g.keyframe) {
            keyframes++;
            CHECK(luzcamera::is_decodable_keyframe(g.data.data(), g.data.size()));
            if (g.timeUs == 1000000ull + 25ull * 33333) {
                askedKeyframe = true;
            }
        }
        // Each fits in a VIDEO message
        CHECK(luzcamera::k_video_prefix + g.data.size() <= luzcamera::k_max_video_payload);
    }
    // The one asked for, and not every frame
    CHECK(askedKeyframe);
    CHECK(keyframes >= 2 && keyframes < got.size() / 2);
    encoder.setBitrate(kbps / 2);
    return true;
}

int main()
{
    @autoreleasepool {
        // No camera on a CI Mac: these only mustn't fail
        std::vector<MacCamera::Device> devices = MacCamera::devices();
        std::printf("camera_mac_test: %zu camera(s), access %d\n", devices.size(), static_cast<int>(MacCamera::access()));
        for (const MacCamera::Device& device : devices) {
            CHECK(!device.id.empty());
        }

        if (encodeSize(1280, 720, 2500)) {
            encodeSize(1920, 1080, 5000);
        }

        // A capture made and dropped without starting doesn't hang or crash
        {
            MacCamera::Capture capture([](const MacCamera::Frame&) {}, [](MacCamera::State, const std::string&) {});
            capture.stop();
        }
    }
    if (s_Failures == 0) {
        std::printf("camera_mac_test: all passed\n");
        return 0;
    }
    std::printf("camera_mac_test: %d failed\n", s_Failures);
    return 1;
}
