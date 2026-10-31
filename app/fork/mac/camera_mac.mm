// [fork] This Mac's camera for the PC (camera_mac.h). Manual retain and release, like the rest of
// LuzLunar's Objective-C++.
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

#include "camera_mac.h"

#include <atomic>
#include <cmath>

namespace
{
    std::string utf8(NSString* text)
    {
        return text != nil ? std::string([text UTF8String]) : std::string();
    }

    const uint8_t k_StartCode[] = {0, 0, 0, 1};

    void append(std::vector<uint8_t>& out, const uint8_t* data, size_t size)
    {
        out.insert(out.end(), data, data + size);
    }

    NSArray* deviceTypes()
    {
        NSMutableArray* types = [NSMutableArray arrayWithObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
        if (@available(macOS 14.0, *)) {
            [types addObject:AVCaptureDeviceTypeExternal];
            [types addObject:AVCaptureDeviceTypeContinuityCamera];
        }
        else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [types addObject:AVCaptureDeviceTypeExternalUnknown];
#pragma clang diagnostic pop
        }
        return types;
    }

    AVCaptureDevice* preferredDevice()
    {
        if (@available(macOS 13.0, *)) {
            AVCaptureDevice* preferred = AVCaptureDevice.systemPreferredCamera;
            if (preferred != nil) {
                return preferred;
            }
        }
        return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
}

std::vector<MacCamera::Device> MacCamera::devices()
{
    std::vector<Device> list;
    @autoreleasepool {
        AVCaptureDevice* preferred = preferredDevice();
        if (preferred != nil) {
            list.push_back({utf8(preferred.uniqueID), utf8(preferred.localizedName)});
        }
        AVCaptureDeviceDiscoverySession* discovery =
            [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes()
                                                                    mediaType:AVMediaTypeVideo
                                                                     position:AVCaptureDevicePositionUnspecified];
        for (AVCaptureDevice* device in discovery.devices) {
            if (preferred != nil && [device.uniqueID isEqualToString:preferred.uniqueID]) {
                continue;
            }
            list.push_back({utf8(device.uniqueID), utf8(device.localizedName)});
        }
    }
    return list;
}

MacCamera::Access MacCamera::access()
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
    case AVAuthorizationStatusAuthorized:
        return Access::Allowed;
    case AVAuthorizationStatusNotDetermined:
        return Access::Undetermined;
    default:
        return Access::Denied;
    }
}

// Encoder

struct MacCamera::Encoder::Impl {
    VTCompressionSessionRef session = nullptr;
    Sink sink;
    int width = 0;
    int height = 0;
    int fps = 30;
    bool lowLatency = false;
    std::atomic<bool> keyframe {false};

    static void output(void* refcon, void*, OSStatus status, VTEncodeInfoFlags, CMSampleBufferRef sample)
    {
        Impl* encoder = static_cast<Impl*>(refcon);
        if (status != noErr || sample == nullptr || !CMSampleBufferDataIsReady(sample)) {
            return;
        }

        // A sync sample, one without kCMSampleAttachmentKey_NotSync, is a keyframe
        bool isKeyframe = true;
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, false);
        if (attachments != nullptr && CFArrayGetCount(attachments) > 0) {
            CFDictionaryRef first = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(attachments, 0));
            isKeyframe = !CFDictionaryContainsKey(first, kCMSampleAttachmentKey_NotSync);
        }

        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        int lengthSize = 4;
        std::vector<uint8_t> annexB;
        if (format != nullptr) {
            size_t count = 0;
            int headerLength = 4;
            if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, nullptr, nullptr, &count, &headerLength) == noErr) {
                lengthSize = headerLength;
                if (isKeyframe) {
                    // The SPS and PPS before each keyframe, so the PC's decoder can start from it
                    for (size_t i = 0; i < count; i++) {
                        const uint8_t* set = nullptr;
                        size_t setSize = 0;
                        if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, i, &set, &setSize, nullptr, nullptr) == noErr) {
                            append(annexB, k_StartCode, sizeof(k_StartCode));
                            append(annexB, set, setSize);
                        }
                    }
                }
            }
        }

        // Length-prefixed NAL units to start codes
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
        size_t total = block != nullptr ? CMBlockBufferGetDataLength(block) : 0;
        std::vector<uint8_t> avcc(total);
        if (total == 0 || CMBlockBufferCopyDataBytes(block, 0, total, avcc.data()) != kCMBlockBufferNoErr) {
            return;
        }
        size_t at = 0;
        while (at + lengthSize <= total) {
            size_t nalSize = 0;
            for (int i = 0; i < lengthSize; i++) {
                nalSize = (nalSize << 8) | avcc[at + i];
            }
            at += lengthSize;
            if (nalSize == 0 || at + nalSize > total) {
                break;
            }
            append(annexB, k_StartCode, sizeof(k_StartCode));
            append(annexB, avcc.data() + at, nalSize);
            at += nalSize;
        }
        if (annexB.empty()) {
            return;
        }

        CMTime time = CMSampleBufferGetPresentationTimeStamp(sample);
        Frame frame;
        frame.data = annexB.data();
        frame.size = annexB.size();
        frame.keyframe = isKeyframe;
        frame.timeUs = CMTIME_IS_VALID(time) ? static_cast<uint64_t>(CMTimeConvertScale(time, 1000000, kCMTimeRoundingMethod_Default).value) : 0;
        frame.width = encoder->width;
        frame.height = encoder->height;
        if (encoder->sink) {
            encoder->sink(frame);
        }
    }

    void setRate(int kbps)
    {
        @autoreleasepool {
            VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, (CFNumberRef)@(kbps * 1000));
            // Bursts up to one and a half times the rate over a second, so a keyframe can't flood the link
            NSArray* limits = @[@(kbps * 1000 / 8 * 3 / 2), @1.0];
            VTSessionSetProperty(session, kVTCompressionPropertyKey_DataRateLimits, (CFArrayRef)limits);
        }
    }
};

MacCamera::Encoder::Encoder(int width, int height, int fps, int kbps, Sink sink)
    : m_Impl(new Impl())
{
    m_Impl->sink = std::move(sink);
    m_Impl->width = width;
    m_Impl->height = height;
    m_Impl->fps = fps > 0 ? fps : 30;

    @autoreleasepool {
        OSStatus status = -1;
        if (@available(macOS 11.3, *)) {
            NSDictionary* specification = @{(id)kVTVideoEncoderSpecification_EnableLowLatencyRateControl: @YES};
            status = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, kCMVideoCodecType_H264, (CFDictionaryRef)specification,
                                                nullptr, nullptr, &Impl::output, m_Impl.get(), &m_Impl->session);
            m_Impl->lowLatency = status == noErr;
        }
        if (status != noErr) {
            // Without low-latency rate control, which only some encoders have
            m_Impl->session = nullptr;
            status = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, kCMVideoCodecType_H264, nullptr,
                                                nullptr, nullptr, &Impl::output, m_Impl.get(), &m_Impl->session);
        }
        if (status != noErr) {
            m_Impl->session = nullptr;
            return;
        }

        VTCompressionSessionRef session = m_Impl->session;
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ExpectedFrameRate, (CFNumberRef)@(m_Impl->fps));
        // A keyframe at least every 4 s, so a lost one doesn't leave the PC waiting long
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, (CFNumberRef)@(m_Impl->fps * 4));
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (CFNumberRef)@4.0);
        m_Impl->setRate(kbps);
        VTCompressionSessionPrepareToEncodeFrames(session);
    }
}

MacCamera::Encoder::~Encoder()
{
    if (m_Impl->session != nullptr) {
        // The frames in flight come out (or are dropped) before the session goes
        VTCompressionSessionCompleteFrames(m_Impl->session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(m_Impl->session);
        CFRelease(m_Impl->session);
        m_Impl->session = nullptr;
    }
}

bool MacCamera::Encoder::valid() const
{
    return m_Impl->session != nullptr;
}

bool MacCamera::Encoder::lowLatency() const
{
    return m_Impl->lowLatency;
}

void MacCamera::Encoder::encode(void* pixelBuffer, std::uint64_t timeUs)
{
    if (m_Impl->session == nullptr || pixelBuffer == nullptr) {
        return;
    }
    @autoreleasepool {
        CMTime time = CMTimeMake(static_cast<int64_t>(timeUs), 1000000);
        CFDictionaryRef options = nullptr;
        if (m_Impl->keyframe.exchange(false)) {
            options = (CFDictionaryRef) @{(id)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};
        }
        VTCompressionSessionEncodeFrame(m_Impl->session, static_cast<CVImageBufferRef>(pixelBuffer), time, kCMTimeInvalid, options, nullptr, nullptr);
    }
}

void MacCamera::Encoder::requestKeyframe()
{
    m_Impl->keyframe = true;
}

void MacCamera::Encoder::setBitrate(int kbps)
{
    if (m_Impl->session != nullptr && kbps > 0) {
        m_Impl->setRate(kbps);
    }
}

void MacCamera::Encoder::flush()
{
    if (m_Impl->session != nullptr) {
        VTCompressionSessionCompleteFrames(m_Impl->session, kCMTimeInvalid);
    }
}

// Capture

@interface LuzCameraDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {
@public
    MacCamera::Capture::Impl* impl;  // cleared on the video queue before the capture goes
}
@end

struct MacCamera::Capture::Impl {
    Encoder::Sink frames;
    StateSink state;
    dispatch_queue_t control = nullptr;     // start and stop, in order
    dispatch_queue_t video = nullptr;       // frames into the encoder
    AVCaptureSession* session = nil;
    LuzCameraDelegate* delegate = nil;
    std::unique_ptr<Encoder> encoder;       // on the video queue
    bool liveReported = false;              // on the video queue
    int generation = 0;                     // on the control queue: a start or stop since an access request

    ~Impl()
    {
        dispatch_release(control);
        dispatch_release(video);
    }

    void report(State newState, const std::string& detail)
    {
        if (state) {
            state(newState, detail);
        }
    }

    // On the video queue
    void frame(CMSampleBufferRef sample)
    {
        CVImageBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
        if (pixels == nullptr || !encoder) {
            return;
        }
        CMTime time = CMSampleBufferGetPresentationTimeStamp(sample);
        uint64_t timeUs = CMTIME_IS_VALID(time) ? static_cast<uint64_t>(CMTimeConvertScale(time, 1000000, kCMTimeRoundingMethod_Default).value) : 0;
        encoder->encode(pixels, timeUs);
        if (!liveReported) {
            liveReported = true;
            report(State::Live, std::string());
        }
    }

    // On the control queue
    void stopNow(bool tell)
    {
        generation++;
        bool wasRunning = session != nil;
        if (session != nil) {
            [session stopRunning];
            for (AVCaptureOutput* output in session.outputs) {
                if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                    [(AVCaptureVideoDataOutput*)output setSampleBufferDelegate:nil queue:nil];
                }
            }
            [session release];
            session = nil;
        }
        LuzCameraDelegate* oldDelegate = delegate;
        delegate = nil;
        dispatch_sync(video, ^{
            if (oldDelegate != nil) {
                oldDelegate->impl = nullptr;
            }
            encoder.reset();
            liveReported = false;
        });
        [oldDelegate release];
        if (wasRunning && tell) {
            report(State::Stopped, std::string());
        }
    }

    // On the control queue, with access
    void startNow(int width, int height, int fps, int kbps, const std::string& deviceId)
    {
        AVCaptureDevice* device = nil;
        if (!deviceId.empty()) {
            device = [AVCaptureDevice deviceWithUniqueID:[NSString stringWithUTF8String:deviceId.c_str()]];
        }
        if (device == nil) {
            // The camera chosen in Settings isn't connected: the one macOS prefers
            device = preferredDevice();
        }
        if (device == nil) {
            report(State::Unavailable, "this Mac has no camera");
            return;
        }

        NSError* error = nil;
        AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        if (input == nil) {
            report(State::Unavailable, error != nil ? utf8(error.localizedDescription) : std::string("the camera didn't open"));
            return;
        }

        AVCaptureSession* newSession = [[AVCaptureSession alloc] init];
        [newSession beginConfiguration];
        NSString* preset = height >= 1080 ? AVCaptureSessionPreset1920x1080 : AVCaptureSessionPreset1280x720;
        if ([newSession canSetSessionPreset:preset]) {
            newSession.sessionPreset = preset;
        }
        else if ([newSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
            newSession.sessionPreset = AVCaptureSessionPresetHigh;
        }
        if (![newSession canAddInput:input]) {
            [newSession commitConfiguration];
            [newSession release];
            report(State::Unavailable, "the camera is in use by another app");
            return;
        }
        [newSession addInput:input];

        // NV12 at the size the PC's app asked for: macOS scales what the camera gives
        AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
        output.videoSettings = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
        };
        output.alwaysDiscardsLateVideoFrames = YES;
        LuzCameraDelegate* newDelegate = [[LuzCameraDelegate alloc] init];
        newDelegate->impl = this;
        [output setSampleBufferDelegate:newDelegate queue:video];
        bool added = [newSession canAddOutput:output];
        if (added) {
            [newSession addOutput:output];
        }
        [output release];
        [newSession commitConfiguration];
        if (!added) {
            [newSession release];
            [newDelegate release];
            report(State::Unavailable, "the camera can't give NV12 frames");
            return;
        }

        // The rate Apollo asked for, where the camera's format has it
        if ([device lockForConfiguration:nil]) {
            CMTime duration = CMTimeMake(1, fps);
            for (AVFrameRateRange* range in device.activeFormat.videoSupportedFrameRateRanges) {
                if (range.minFrameRate <= fps && fps <= range.maxFrameRate) {
                    device.activeVideoMinFrameDuration = duration;
                    device.activeVideoMaxFrameDuration = duration;
                    break;
                }
            }
            [device unlockForConfiguration];
        }

        Encoder* newEncoder = new Encoder(width, height, fps, kbps, frames);
        if (!newEncoder->valid()) {
            delete newEncoder;
            [newSession release];
            [newDelegate release];
            report(State::Unavailable, "VideoToolbox has no H.264 encoder");
            return;
        }
        dispatch_sync(video, ^{
            encoder.reset(newEncoder);
            liveReported = false;
        });

        delegate = newDelegate;
        session = newSession;
        [session startRunning];
        if (!session.running) {
            stopNow(false);
            report(State::Unavailable, "the camera didn't start");
        }
    }
};

@implementation LuzCameraDelegate

- (void)captureOutput:(AVCaptureOutput*)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection
{
    (void)output;
    (void)connection;
    if (impl != nullptr) {
        impl->frame(sampleBuffer);
    }
}

@end

MacCamera::Capture::Capture(Encoder::Sink frames, StateSink state)
    : m_Impl(std::make_shared<Impl>())
{
    m_Impl->frames = std::move(frames);
    m_Impl->state = std::move(state);
    m_Impl->control = dispatch_queue_create("com.luzlunar.camera.control", DISPATCH_QUEUE_SERIAL);
    m_Impl->video = dispatch_queue_create("com.luzlunar.camera.video", DISPATCH_QUEUE_SERIAL);
}

MacCamera::Capture::~Capture()
{
    // The camera goes and nothing more is reported. An access request still waiting for its answer
    // holds the rest, and finds through its generation that it's no longer wanted.
    std::shared_ptr<Impl> impl = m_Impl;
    dispatch_sync(impl->control, ^{
        @autoreleasepool {
            impl->stopNow(false);
            impl->state = nullptr;
            impl->frames = nullptr;
        }
    });
}

void MacCamera::Capture::start(int width, int height, int fps, int kbps, const std::string& deviceId)
{
    std::shared_ptr<Impl> impl = m_Impl;
    std::string id = deviceId;
    dispatch_async(impl->control, ^{
        @autoreleasepool {
            impl->stopNow(false);
            switch (access()) {
            case Access::Allowed:
                impl->startNow(width, height, fps, kbps, id);
                break;
            case Access::Denied:
                impl->report(State::Denied, std::string());
                break;
            case Access::Undetermined: {
                // macOS's prompt; the camera starts once it's allowed, unless something else happened meanwhile
                int generation = impl->generation;
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                    dispatch_async(impl->control, ^{
                        @autoreleasepool {
                            if (impl->generation == generation) {
                                if (granted) {
                                    impl->startNow(width, height, fps, kbps, id);
                                }
                                else {
                                    impl->report(State::Denied, std::string());
                                }
                            }
                        }
                    });
                }];
                break;
            }
            }
        }
    });
}

void MacCamera::Capture::stop()
{
    std::shared_ptr<Impl> impl = m_Impl;
    dispatch_async(impl->control, ^{
        @autoreleasepool {
            impl->stopNow(true);
        }
    });
}

void MacCamera::Capture::requestKeyframe()
{
    std::shared_ptr<Impl> impl = m_Impl;
    dispatch_async(impl->video, ^{
        if (impl->encoder) {
            impl->encoder->requestKeyframe();
        }
    });
}

void MacCamera::Capture::setBitrate(int kbps)
{
    std::shared_ptr<Impl> impl = m_Impl;
    dispatch_async(impl->video, ^{
        if (impl->encoder) {
            impl->encoder->setBitrate(kbps);
        }
    });
}
