// [fork] Upscaling's Quality engine: VideoToolbox's low-latency super resolution (macOS 26),
// which Apple made for video calls over bad networks: besides scaling, it "reduces coding
// artifacts and sharpens edges" (WWDC25 session 300). It takes the decoded CVPixelBuffer and
// gives a larger one, so it works the same before either renderer. See forkupscaling.h.
//
// Apple documents no supported chips, pixel formats, sizes or timings, so all of that is asked
// at run time and logged: isSupported, supportedScaleFactorsForFrameWidth:frameHeight:,
// frameSupportedPixelFormats and minimum/maximumDimensions.
#include "fork/forkupscaling.h"

#include "fork/upscalerules.h"
#include "streaming/streamutils.h"
#include "SDL_compat.h"

extern "C" {
#include <libavutil/buffer.h>
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}

#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <dispatch/dispatch.h>

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

// The macOS 26 SDK has the low-latency processors; CI builds with Xcode 26
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
#define FORK_HAVE_LOW_LATENCY_SUPER_RESOLUTION 1
#endif

namespace ForkUpscaling
{

namespace
{
    // A started processor, for one source size and pixel format and one scale factor
    struct Session
    {
        id processor = nil;     // VTFrameProcessor, retained
        id configuration = nil; // VTLowLatencySuperResolutionScalerConfiguration, retained
        CVPixelBufferPoolRef pool = nullptr;
        int width = 0;
        int height = 0;
        OSType format = 0;
        float scale = 0;
    };

    // What was last tried for a source size and format: the factors VideoToolbox offers for it,
    // and why no session came of it ("" when one did)
    struct Attempt
    {
        int width = 0;
        int height = 0;
        OSType format = 0;
        float scale = -1; // the factor asked for, so a different one tries again
        std::vector<float> factors;
        bool done = false;
        std::string failure;
    };

    // Under s_Lock: the render thread reads them each frame, the start queue sets them
    std::mutex s_Lock;
    Session s_Session;
    Attempt s_Attempt;
    bool s_Starting = false;
    unsigned s_Generation = 0; // bumped by resetSuperResolution(), so a late start is dropped
    bool s_Failed = false;     // processing failed: no more tries this stream
    std::string s_FailedReason;

    // Held across processing, so a reset doesn't end the session under it
    std::mutex s_ProcessLock;

    // The last two outputs, held as Pacer holds the decoder's frames, so the GPU never reads a
    // buffer the pool has handed out again (under s_Lock)
    CVPixelBufferRef s_Held[2] = {};
    int s_HeldNext = 0;

    std::atomic<bool> s_Active { false };
    int64_t s_FrameCount = 0; // under s_ProcessLock

    dispatch_queue_t startQueue()
    {
        static dispatch_queue_t queue = dispatch_queue_create("LuzLunar super resolution", DISPATCH_QUEUE_SERIAL);
        return queue;
    }

    void releaseSession(Session& session)
    {
        if (session.processor != nil) {
#ifdef FORK_HAVE_LOW_LATENCY_SUPER_RESOLUTION
            if (@available(macOS 26.0, *)) {
                [(VTFrameProcessor*)session.processor endSession];
            }
#endif
            [session.processor release];
        }
        [session.configuration release];
        if (session.pool != nullptr) {
            CVPixelBufferPoolRelease(session.pool);
        }
        session = Session();
    }

    std::string fourCc(OSType format)
    {
        char text[5] = { (char)(format >> 24), (char)(format >> 16), (char)(format >> 8), (char)format, 0 };
        for (int i = 0; i < 4; i++) {
            if (text[i] < 32 || text[i] > 126) {
                text[i] = '?';
            }
        }
        return text;
    }

    void releasePixelBuffer(void*, uint8_t* data)
    {
        CVPixelBufferRelease((CVPixelBufferRef)data);
    }

#ifdef FORK_HAVE_LOW_LATENCY_SUPER_RESOLUTION
    // On the start queue: asks what VideoToolbox offers for this source and starts a session for
    // the factor the area needs. Loading the model "may take longer than a frame time", Apple
    // says, so never on the render thread.
    API_AVAILABLE(macos(26.0))
    void start(unsigned generation, int width, int height, OSType format, int rectWidth, int rectHeight)
    { @autoreleasepool {
        Attempt attempt;
        attempt.width = width;
        attempt.height = height;
        attempt.format = format;
        attempt.scale = 0;
        attempt.done = true;
        Session session;

        if (!VTLowLatencySuperResolutionScalerConfiguration.isSupported) {
            attempt.failure = "Quality: not supported on this Mac";
        }
        else {
            CMVideoDimensions minimum = VTLowLatencySuperResolutionScalerConfiguration.minimumDimensions;
            CMVideoDimensions maximum = VTLowLatencySuperResolutionScalerConfiguration.maximumDimensions;
            for (NSNumber* factor in [VTLowLatencySuperResolutionScalerConfiguration supportedScaleFactorsForFrameWidth:width
                                                                                                         frameHeight:height]) {
                attempt.factors.push_back(factor.floatValue);
            }

            std::string offered;
            for (float factor : attempt.factors) {
                offered += (offered.empty() ? "" : ", ") + std::to_string(factor).substr(0, 4) + "x";
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Upscaling: VT super resolution takes %dx%d to %dx%d and offers %s for %dx%d '%s'",
                        minimum.width, minimum.height, maximum.width, maximum.height,
                        offered.empty() ? "no scale factors" : offered.c_str(), width, height, fourCc(format).c_str());

            attempt.scale = UpscaleRules::pickScaleFactor(width, height, rectWidth, rectHeight, attempt.factors);
            if (attempt.factors.empty()) {
                attempt.failure = "Quality: not offered at this size";
            }
            else if (attempt.scale <= 0) {
                attempt.failure = "Quality: no scale factor fits";
            }
            else {
                VTLowLatencySuperResolutionScalerConfiguration* configuration =
                    [[VTLowLatencySuperResolutionScalerConfiguration alloc] initWithFrameWidth:width
                                                                                   frameHeight:height
                                                                                   scaleFactor:attempt.scale];
                bool formatSupported = false;
                std::string formats;
                for (NSNumber* supported in configuration.frameSupportedPixelFormats) {
                    formats += (formats.empty() ? "'" : ", '") + fourCc(supported.unsignedIntValue) + "'";
                    if (supported.unsignedIntValue == format) {
                        formatSupported = true;
                    }
                }

                if (!formatSupported) {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                                "[fork] Upscaling: VT super resolution doesn't take '%s' frames (it takes %s)",
                                fourCc(format).c_str(), formats.c_str());
                    attempt.failure = "Quality: not for this pixel format";
                    [configuration release];
                }
                else {
                    VTFrameProcessor* processor = [[VTFrameProcessor alloc] init];
                    NSError* error = nil;
                    uint64_t startedAt = SDL_GetTicks64();
                    if (![processor startSessionWithConfiguration:configuration error:&error]) {
                        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                                    "[fork] Upscaling: VT super resolution didn't start: %s",
                                    error.description.UTF8String);
                        attempt.failure = "Quality: didn't start";
                        [processor release];
                        [configuration release];
                    }
                    else {
                        int outWidth = (int)lroundf(width * attempt.scale);
                        int outHeight = (int)lroundf(height * attempt.scale);

                        // The processor's own needs for its output, with what the renderers need
                        // to map it into Metal
                        NSDictionary* ours = @{
                            (id)kCVPixelBufferWidthKey: @(outWidth),
                            (id)kCVPixelBufferHeightKey: @(outHeight),
                            (id)kCVPixelBufferPixelFormatTypeKey: @(format),
                            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
                            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
                        };
                        CFDictionaryRef resolved = nullptr;
                        CVPixelBufferCreateResolvedAttributesDictionary(kCFAllocatorDefault,
                                                                        (__bridge CFArrayRef)@[ ours, configuration.destinationPixelBufferAttributes ],
                                                                        &resolved);
                        CVPixelBufferPoolRef pool = nullptr;
                        CVReturn status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nullptr,
                                                                  resolved != nullptr ? resolved : (__bridge CFDictionaryRef)ours, &pool);
                        if (resolved != nullptr) {
                            CFRelease(resolved);
                        }

                        // The renderers take the output as a frame of the decoder's own format
                        // (its hw_frames_ctx), so it has to be that format and size
                        CVPixelBufferRef probe = nullptr;
                        if (status == kCVReturnSuccess) {
                            status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &probe);
                        }
                        if (status != kCVReturnSuccess || probe == nullptr ||
                                CVPixelBufferGetPixelFormatType(probe) != format ||
                                (int)CVPixelBufferGetWidth(probe) != outWidth || (int)CVPixelBufferGetHeight(probe) != outHeight) {
                            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                                        "[fork] Upscaling: VT super resolution's output buffers aren't %dx%d '%s' (%d)",
                                        outWidth, outHeight, fourCc(format).c_str(), status);
                            attempt.failure = "Quality: unusable output";
                            [processor endSession];
                            [processor release];
                            [configuration release];
                            if (pool != nullptr) {
                                CVPixelBufferPoolRelease(pool);
                            }
                        }
                        else {
                            session.processor = processor;
                            session.configuration = configuration;
                            session.pool = pool;
                            session.width = width;
                            session.height = height;
                            session.format = format;
                            session.scale = attempt.scale;
                            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                                        "[fork] Upscaling: VT super resolution started for %dx%d -> %dx%d in %llu ms",
                                        width, height, outWidth, outHeight,
                                        (unsigned long long)(SDL_GetTicks64() - startedAt));
                        }
                        if (probe != nullptr) {
                            CVPixelBufferRelease(probe);
                        }
                    }
                }
            }
        }

        if (!attempt.failure.empty()) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Upscaling: %s for %dx%d", attempt.failure.c_str(), width, height);
        }

        std::lock_guard<std::mutex> lock(s_Lock);
        s_Starting = false;
        if (generation != s_Generation) {
            // The stream ended or a new one started meanwhile
            std::lock_guard<std::mutex> processLock(s_ProcessLock);
            releaseSession(session);
            return;
        }
        if (session.processor != nil) {
            std::lock_guard<std::mutex> processLock(s_ProcessLock);
            releaseSession(s_Session);
            s_Session = session;
        }
        s_Attempt = attempt;
    }}
#endif
}

bool superResolutionSupported()
{
#ifdef FORK_HAVE_LOW_LATENCY_SUPER_RESOLUTION
    if (@available(macOS 26.0, *)) {
        return VTLowLatencySuperResolutionScalerConfiguration.isSupported;
    }
#endif
    return false;
}

bool superResolutionActive()
{
    return s_Active.load();
}

void resetSuperResolution()
{
    std::lock_guard<std::mutex> lock(s_Lock);
    s_Generation++;
    {
        std::lock_guard<std::mutex> processLock(s_ProcessLock);
        releaseSession(s_Session);
        s_FrameCount = 0;
    }
    s_Attempt = Attempt();
    s_Failed = false;
    s_FailedReason.clear();
    for (CVPixelBufferRef& held : s_Held) {
        if (held != nullptr) {
            CVPixelBufferRelease(held);
            held = nullptr;
        }
    }
    s_HeldNext = 0;
    s_Active.store(false);
}

AVFrame* superResolve(const AVFrame* frame, int drawableWidth, int drawableHeight)
{
    if (mode() != UpscaleRules::Mode::Quality) {
        s_Active.store(false);
        return nullptr;
    }

#ifdef FORK_HAVE_LOW_LATENCY_SUPER_RESOLUTION
    if (@available(macOS 26.0, *)) {
        if (frame->format != AV_PIX_FMT_VIDEOTOOLBOX || frame->data[3] == nullptr) {
            s_Active.store(false);
            setQualityNote("Quality: needs hardware decoding");
            return nullptr;
        }

        CVPixelBufferRef source = (CVPixelBufferRef)frame->data[3];
        int width = (int)CVPixelBufferGetWidth(source);
        int height = (int)CVPixelBufferGetHeight(source);
        OSType format = CVPixelBufferGetPixelFormatType(source);

        SDL_Rect src = { 0, 0, frame->width, frame->height };
        SDL_Rect dst = { 0, 0, drawableWidth, drawableHeight };
        StreamUtils::scaleSourceToDestinationSurface(&src, &dst);
        if (!UpscaleRules::needsUpscale(frame->width, frame->height, dst.w, dst.h)) {
            s_Active.store(false);
            setQualityNote(nullptr);
            return nullptr;
        }

        // A buffer larger than the picture (padding, a crop) would scale the wrong area
        if (width != frame->width || height != frame->height ||
                frame->crop_left != 0 || frame->crop_right != 0 || frame->crop_top != 0 || frame->crop_bottom != 0) {
            s_Active.store(false);
            setQualityNote("Quality: padded frames");
            return nullptr;
        }

        id processor = nil;
        CVPixelBufferPoolRef pool = nullptr;
        {
            std::lock_guard<std::mutex> lock(s_Lock);
            if (s_Failed) {
                s_Active.store(false);
                setQualityNote(s_FailedReason.c_str());
                return nullptr;
            }

            bool attempted = s_Attempt.done && s_Attempt.width == width && s_Attempt.height == height &&
                             s_Attempt.format == format;
            float wanted = attempted ? UpscaleRules::pickScaleFactor(width, height, dst.w, dst.h, s_Attempt.factors) : -1;

            bool ready = s_Session.processor != nil && s_Session.width == width && s_Session.height == height &&
                         s_Session.format == format && wanted > 0 && s_Session.scale == wanted;
            if (!ready) {
                s_Active.store(false);
                if (attempted && wanted == s_Attempt.scale) {
                    // Tried already, for this factor or for none: what came of it stands
                    setQualityNote(s_Attempt.failure.empty() ? "Quality: no scale factor fits" : s_Attempt.failure.c_str());
                    return nullptr;
                }
                if (!s_Starting) {
                    s_Starting = true;
                    unsigned generation = s_Generation;
                    int rectWidth = dst.w;
                    int rectHeight = dst.h;
                    dispatch_async(startQueue(), ^{
                        start(generation, width, height, format, rectWidth, rectHeight);
                    });
                }
                setQualityNote("Quality: starting");
                return nullptr;
            }

            processor = [s_Session.processor retain];
            pool = CVPixelBufferPoolRetain(s_Session.pool);
        }

        AVFrame* result = nullptr;
        CVPixelBufferRef output = nullptr;
        bool failed = false;
        @autoreleasepool {
            std::lock_guard<std::mutex> processLock(s_ProcessLock);

            if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output) == kCVReturnSuccess) {
                // Color space, transfer function and HDR metadata
                CVBufferPropagateAttachments(source, output);

                CMTime time = CMTimeMake(s_FrameCount++, 1000);
                VTFrameProcessorFrame* sourceFrame = [[[VTFrameProcessorFrame alloc] initWithBuffer:source presentationTimeStamp:time] autorelease];
                VTFrameProcessorFrame* outputFrame = [[[VTFrameProcessorFrame alloc] initWithBuffer:output presentationTimeStamp:time] autorelease];
                VTLowLatencySuperResolutionScalerParameters* parameters =
                    sourceFrame != nil && outputFrame != nil
                        ? [[[VTLowLatencySuperResolutionScalerParameters alloc] initWithSourceFrame:sourceFrame
                                                                                   destinationFrame:outputFrame] autorelease]
                        : nil;

                NSError* error = nil;
                uint64_t startedAt = SDL_GetPerformanceCounter();
                BOOL processed = parameters != nil && [(VTFrameProcessor*)processor processWithParameters:parameters error:&error];
                double ms = (SDL_GetPerformanceCounter() - startedAt) * 1000.0 / SDL_GetPerformanceFrequency();

                if (processed) {
                    result = av_frame_alloc();
                    if (result != nullptr && av_frame_copy_props(result, frame) == 0) {
                        result->format = frame->format;
                        result->width = (int)CVPixelBufferGetWidth(output);
                        result->height = (int)CVPixelBufferGetHeight(output);
                        result->buf[0] = av_buffer_create((uint8_t*)output, sizeof(output), releasePixelBuffer, nullptr, 0);
                        if (frame->hw_frames_ctx != nullptr) {
                            result->hw_frames_ctx = av_buffer_ref(frame->hw_frames_ctx);
                        }
                    }
                    if (result == nullptr || result->buf[0] == nullptr) {
                        av_frame_free(&result);
                    }
                    else {
                        result->data[3] = (uint8_t*)output;
                        report(UpscaleRules::Engine::SuperResolution, width, height, result->width, result->height, ms);
                    }
                }
                else {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                                "[fork] Upscaling: VT super resolution failed, off for this stream: %s",
                                error != nil ? error.description.UTF8String : "no parameters");
                    failed = true;
                }
            }
        }

        [processor release];
        CVPixelBufferPoolRelease(pool);

        if (failed) {
            // After the process lock: s_Lock is always taken first
            std::lock_guard<std::mutex> lock(s_Lock);
            s_Failed = true;
            s_FailedReason = "Quality: failed";
        }

        if (result == nullptr) {
            // The frame owns the buffer only once it's made
            if (output != nullptr) {
                CVPixelBufferRelease(output);
            }
            s_Active.store(false);
            return nullptr;
        }

        {
            std::lock_guard<std::mutex> lock(s_Lock);
            if (s_Held[s_HeldNext] != nullptr) {
                CVPixelBufferRelease(s_Held[s_HeldNext]);
            }
            s_Held[s_HeldNext] = CVPixelBufferRetain(output);
            s_HeldNext = (s_HeldNext + 1) % 2;
        }

        s_Active.store(true);
        setQualityNote(nullptr);
        return result;
    }
#endif

    (void)frame;
    (void)drawableWidth;
    (void)drawableHeight;
    s_Active.store(false);
    setQualityNote("Quality: needs macOS 26");
    return nullptr;
}

}
