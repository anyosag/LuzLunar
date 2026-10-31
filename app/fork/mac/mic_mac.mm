#include "mic_mac.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <time.h>

#include <SDL.h>

#import <AVFoundation/AVFoundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>

// [fork] This file is built without ARC, like the fork's other Objective-C++: every alloc is
// released or autoreleased.

namespace ForkMicMac
{
namespace
{
    constexpr UInt32 fourCc(char a, char b, char c, char d)
    {
        return (static_cast<UInt32>(a) << 24) | (static_cast<UInt32>(b) << 16) | (static_cast<UInt32>(c) << 8) | static_cast<UInt32>(d);
    }

    // The built-in output's data source when headphones are in its jack
    constexpr UInt32 k_HeadphonesSource = fourCc('h', 'd', 'p', 'n');
    constexpr double k_Rate = luzmic::k_sample_rate;

    AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal)
    {
        // Element 0: kAudioObjectPropertyElementMain (macOS 12), kAudioObjectPropertyElementMaster before
        return { selector, scope, 0 };
    }

    UInt32 uint32Property(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope, UInt32 fallback)
    {
        AudioObjectPropertyAddress where = address(selector, scope);
        UInt32 value = fallback;
        UInt32 size = sizeof(value);
        if (!AudioObjectHasProperty(object, &where) || AudioObjectGetPropertyData(object, &where, 0, nullptr, &size, &value) != noErr) {
            return fallback;
        }
        return value;
    }

    std::string stringProperty(AudioObjectID object, AudioObjectPropertySelector selector)
    {
        AudioObjectPropertyAddress where = address(selector);
        CFStringRef value = nullptr;
        UInt32 size = sizeof(value);
        if (AudioObjectGetPropertyData(object, &where, 0, nullptr, &size, &value) != noErr || value == nullptr) {
            return {};
        }
        char buffer[512];
        std::string result;
        if (CFStringGetCString(value, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
            result = buffer;
        }
        CFRelease(value);
        return result;
    }

    std::vector<AudioDeviceID> allDevices()
    {
        AudioObjectPropertyAddress where = address(kAudioHardwarePropertyDevices);
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &where, 0, nullptr, &size) != noErr || size == 0) {
            return {};
        }
        std::vector<AudioDeviceID> devices(size / sizeof(AudioDeviceID));
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &where, 0, nullptr, &size, devices.data()) != noErr) {
            return {};
        }
        devices.resize(size / sizeof(AudioDeviceID));
        return devices;
    }

    bool hasInput(AudioDeviceID device)
    {
        AudioObjectPropertyAddress where = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput);
        UInt32 size = 0;
        return AudioObjectGetPropertyDataSize(device, &where, 0, nullptr, &size) == noErr && size > 0;
    }

    AudioDeviceID inputForUid(const std::string& uid)
    {
        for (AudioDeviceID device : allDevices()) {
            if (hasInput(device) && stringProperty(device, kAudioDevicePropertyDeviceUID) == uid) {
                return device;
            }
        }
        return kAudioObjectUnknown;
    }

    MicRules::Transport transportOf(UInt32 type)
    {
        using MicRules::Transport;
        switch (type) {
        case kAudioDeviceTransportTypeBuiltIn:
            return Transport::BuiltIn;
        case kAudioDeviceTransportTypeBluetooth:
            return Transport::Bluetooth;
        case kAudioDeviceTransportTypeBluetoothLE:
            return Transport::BluetoothLE;
        case kAudioDeviceTransportTypeUSB:
            return Transport::Usb;
        case kAudioDeviceTransportTypeHDMI:
            return Transport::Hdmi;
        case kAudioDeviceTransportTypeDisplayPort:
            return Transport::DisplayPort;
        case kAudioDeviceTransportTypeAirPlay:
            return Transport::AirPlay;
        case kAudioDeviceTransportTypeThunderbolt:
            return Transport::Thunderbolt;
        case kAudioDeviceTransportTypeVirtual:
            return Transport::Virtual;
        case kAudioDeviceTransportTypeAggregate:
            return Transport::Aggregate;
        default:
            return Transport::Unknown;
        }
    }

    std::mutex s_WatchMutex;
    dispatch_source_t s_WatchTimer = nullptr;
}

struct Engine::Impl
{
    dispatch_queue_t queue = nullptr;
    std::shared_ptr<MicRules::PcmRing> ring;
    FrameSink sink;
    std::atomic<bool> playbackFailed { false };
    // False once the Engine is going: blocks still on their way to the queue then do nothing
    std::shared_ptr<std::atomic<bool>> alive = std::make_shared<std::atomic<bool>>(true);

    // On the queue
    AVAudioEngine* engine = nil;
    id observer = nil;                   // the engine's configuration changes
    bool rebuildPending = false;
    uint64_t lastRebuildNs = 0;
    uint64_t startedNs = 0;              // the last start, whose own changes (voice processing's) don't count
    bool configured = false;
    bool playback = false;
    bool capture = false;
    std::string inputUid;

    // The microphone's samples, on the engine's audio thread while it runs
    double inputRate = 0;
    AVAudioConverter* converter = nil;   // to 48 kHz, when the input runs at another rate
    AVAudioPCMBuffer* converterIn = nil;
    AVAudioPCMBuffer* converterOut = nil;
    std::vector<float> pending;          // 48 kHz mono, short of a frame
    size_t pendingAt = 0;

    void apply(bool wantPlayback, bool wantCapture, const std::string& uid);
    bool build(const std::string& uid);
    void teardown();
    void captured(const AudioBufferList* list, AVAudioFrameCount frames);
    void append(const float* samples, size_t count);
    void configurationChanged();
};

// A device came or went, or changed its format: AVAudioEngine stopped itself, so it starts again
// with the same configuration; at most once every 2 s, in case starting changes it again
void Engine::Impl::configurationChanged()
{
    constexpr uint64_t k_MinGapNs = 2000000000ull;
    constexpr uint64_t k_SettleNs = 1000000000ull;
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (rebuildPending || engine == nil || now - startedNs < k_SettleNs) {
        return;
    }
    rebuildPending = true;
    uint64_t wait = now - lastRebuildNs < k_MinGapNs ? k_MinGapNs - (now - lastRebuildNs) : 0;
    Impl* impl = this;
    std::shared_ptr<std::atomic<bool>> stillAlive = alive;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(wait)), queue, ^{
        if (!*stillAlive) {
            return;
        }
        impl->rebuildPending = false;
        if (!impl->playback && !impl->capture) {
            return;
        }
        impl->lastRebuildNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: the audio devices changed; starting the engine again");
        impl->configured = false;
        impl->apply(impl->playback, impl->capture, impl->inputUid);
    });
}

void Engine::Impl::append(const float* samples, size_t count)
{
    pending.insert(pending.end(), samples, samples + count);
    while (pending.size() - pendingAt >= static_cast<size_t>(luzmic::k_frame_samples)) {
        sink(pending.data() + pendingAt);
        pendingAt += luzmic::k_frame_samples;
    }
    if (pendingAt > 0 && pendingAt * 2 >= pending.size()) {
        pending.erase(pending.begin(), pending.begin() + static_cast<std::ptrdiff_t>(pendingAt));
        pendingAt = 0;
    }
}

void Engine::Impl::captured(const AudioBufferList* list, AVAudioFrameCount frames)
{
    if (list == nullptr || list->mNumberBuffers == 0 || list->mBuffers[0].mData == nullptr || frames == 0) {
        return;
    }
    // The first channel: voice processing's output, or the microphone's first
    const float* first = static_cast<const float*>(list->mBuffers[0].mData);
    if (converter == nil) {
        append(first, frames);
        return;
    }

    frames = std::min(frames, converterIn.frameCapacity);
    std::memcpy(converterIn.floatChannelData[0], first, frames * sizeof(float));
    converterIn.frameLength = frames;
    converterOut.frameLength = 0;
    __block BOOL given = NO;
    AVAudioPCMBuffer* input = converterIn;
    NSError* error = nil;
    AVAudioConverterOutputStatus status =
        [converter convertToBuffer:converterOut
                             error:&error
                withInputFromBlock:^AVAudioBuffer*(AVAudioPacketCount, AVAudioConverterInputStatus* inputStatus) {
                    if (given) {
                        *inputStatus = AVAudioConverterInputStatus_NoDataNow;
                        return nil;
                    }
                    given = YES;
                    *inputStatus = AVAudioConverterInputStatus_HaveData;
                    return input;
                }];
    if (status != AVAudioConverterOutputStatus_Error && converterOut.frameLength > 0) {
        append(converterOut.floatChannelData[0], converterOut.frameLength);
    }
}

void Engine::Impl::teardown()
{
    @autoreleasepool {
        if (observer != nil) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            [observer release];
            observer = nil;
        }
        if (engine != nil) {
            [engine stop];
            [engine release];
            engine = nil;
        }
        [converter release];
        converter = nil;
        [converterIn release];
        converterIn = nil;
        [converterOut release];
        converterOut = nil;
        pending.clear();
        pendingAt = 0;
    }
}

bool Engine::Impl::build(const std::string& uid)
{
    engine = [[AVAudioEngine alloc] init];

    if (capture) {
        AVAudioInputNode* input = engine.inputNode;
        if (playback) {
            // The stream plays through this engine too, so voice processing hears what it must cancel
            NSError* error = nil;
            if (![input setVoiceProcessingEnabled:YES error:&error]) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: no voice processing (%s); the PC may hear the stream's echo",
                            error.localizedDescription.UTF8String);
            }
        }
        if (!uid.empty()) {
            AudioDeviceID device = inputForUid(uid);
            OSStatus status = device == kAudioObjectUnknown ? kAudioHardwareBadDeviceError :
                              AudioUnitSetProperty(input.audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                   &device, sizeof(device));
            if (status != noErr) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: couldn't record from the chosen microphone (%d); recording from macOS's default", static_cast<int>(status));
            }
        }

        AVAudioFormat* format = [input outputFormatForBus:0];
        if (format.sampleRate <= 0 || format.channelCount == 0) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: no input to record from");
            return false;
        }
        inputRate = format.sampleRate;
        if (inputRate != k_Rate) {
            AVAudioFormat* monoIn = [[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:inputRate channels:1 interleaved:NO] autorelease];
            AVAudioFormat* mono48 = [[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:k_Rate channels:1 interleaved:NO] autorelease];
            converter = [[AVAudioConverter alloc] initFromFormat:monoIn toFormat:mono48];
            converterIn = [[AVAudioPCMBuffer alloc] initWithPCMFormat:monoIn frameCapacity:8192];
            converterOut = [[AVAudioPCMBuffer alloc] initWithPCMFormat:mono48 frameCapacity:static_cast<AVAudioFrameCount>(8192 * k_Rate / inputRate) + 64];
            if (converter == nil || converterIn == nil || converterOut == nil) {
                return false;
            }
        }
        Impl* impl = this;
        AVAudioSinkNode* sinkNode = [[[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(const AudioTimeStamp*, AVAudioFrameCount frames, const AudioBufferList* list) {
            // The converter's objects are autoreleased, and this thread has no pool of its own
            @autoreleasepool {
                impl->captured(list, frames);
            }
            return noErr;
        }] autorelease];
        [engine attachNode:sinkNode];
        [engine connect:input to:sinkNode format:format];
    }

    if (playback) {
        AVAudioFormat* stereo = [[[AVAudioFormat alloc] initStandardFormatWithSampleRate:k_Rate channels:2] autorelease];
        std::shared_ptr<MicRules::PcmRing> pcm = ring;
        AVAudioSourceNode* source = [[[AVAudioSourceNode alloc] initWithFormat:stereo
                                                                   renderBlock:^OSStatus(BOOL* isSilence, const AudioTimeStamp*, AVAudioFrameCount frames, AudioBufferList* out) {
                                                                       if (out->mNumberBuffers < 2) {
                                                                           for (UInt32 i = 0; i < out->mNumberBuffers; i++) {
                                                                               std::memset(out->mBuffers[i].mData, 0, out->mBuffers[i].mDataByteSize);
                                                                           }
                                                                           *isSilence = YES;
                                                                           return noErr;
                                                                       }
                                                                       int got = pcm->pull(static_cast<float*>(out->mBuffers[0].mData),
                                                                                           static_cast<float*>(out->mBuffers[1].mData), static_cast<int>(frames));
                                                                       if (got == 0) {
                                                                           *isSilence = YES;
                                                                       }
                                                                       return noErr;
                                                                   }] autorelease];
        [engine attachNode:source];
        [engine connect:source to:engine.mainMixerNode format:stereo];
    }

    [engine prepare];
    NSError* error = nil;
    if (![engine startAndReturnError:&error]) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: the audio engine didn't start: %s", error.localizedDescription.UTF8String);
        return false;
    }

    startedNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    Impl* impl = this;
    dispatch_queue_t engineQueue = queue;
    std::shared_ptr<std::atomic<bool>> stillAlive = alive;
    observer = [[[NSNotificationCenter defaultCenter] addObserverForName:AVAudioEngineConfigurationChangeNotification
                                                                  object:engine
                                                                   queue:nil
                                                              usingBlock:^(NSNotification*) {
                                                                  dispatch_async(engineQueue, ^{
                                                                      if (*stillAlive) {
                                                                          impl->configurationChanged();
                                                                      }
                                                                  });
                                                              }] retain];
    return true;
}

void Engine::Impl::apply(bool wantPlayback, bool wantCapture, const std::string& uid)
{
    if (configured && wantPlayback == playback && wantCapture == capture && (!wantCapture || uid == inputUid)) {
        return;
    }
    teardown();
    configured = true;
    playback = wantPlayback;
    capture = wantCapture;
    inputUid = uid;
    playbackFailed = false;
    if (!playback && !capture) {
        return;
    }

    bool started = false;
    @autoreleasepool {
        @try {
            started = build(uid);
        }
        @catch (NSException* exception) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: the audio engine failed: %s", exception.reason.UTF8String);
            started = false;
        }
    }
    if (!started) {
        teardown();
        playbackFailed = playback;
        return;
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Microphone: %s%s%s", playback ? "the stream's sound through this Mac's speakers" : "",
                playback && capture ? ", " : "",
                capture ? (playback ? "recording with voice processing" : "recording") : "");
}

Engine::Engine(std::shared_ptr<MicRules::PcmRing> ring, FrameSink sink)
    : m(new Impl)
{
    m->queue = dispatch_queue_create("LuzLunar.microphone", DISPATCH_QUEUE_SERIAL);
    m->ring = std::move(ring);
    m->sink = std::move(sink);
}

Engine::~Engine()
{
    Impl* impl = m.get();
    dispatch_sync(impl->queue, ^{
        *impl->alive = false;
        impl->teardown();
    });
    dispatch_release(impl->queue);
}

void Engine::configure(bool playback, bool capture, const std::string& inputUid)
{
    Impl* impl = m.get();
    std::string uid = inputUid;
    dispatch_async(impl->queue, ^{
        impl->apply(playback, capture, uid);
    });
}

bool Engine::playbackFailed() const
{
    return m->playbackFailed;
}

MicRules::Output currentOutput()
{
    AudioObjectPropertyAddress where = address(kAudioHardwarePropertyDefaultOutputDevice);
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &where, 0, nullptr, &size, &device) != noErr || device == kAudioObjectUnknown) {
        return MicRules::Output::Speakers;
    }
    MicRules::Transport transport = transportOf(uint32Property(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, 0));
    bool headphones = transport == MicRules::Transport::BuiltIn &&
                      uint32Property(device, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput, 0) == k_HeadphonesSource;
    return MicRules::classifyOutput(transport, headphones);
}

void watchOutput(std::function<void(MicRules::Output)> changed)
{
    std::lock_guard<std::mutex> lock(s_WatchMutex);
    if (s_WatchTimer != nullptr) {
        dispatch_source_cancel(s_WatchTimer);
        dispatch_release(s_WatchTimer);
        s_WatchTimer = nullptr;
    }
    if (!changed) {
        return;
    }

    auto last = std::make_shared<std::atomic<int>>(static_cast<int>(currentOutput()));
    s_WatchTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(s_WatchTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(s_WatchTimer, ^{
        MicRules::Output now = currentOutput();
        if (last->exchange(static_cast<int>(now)) != static_cast<int>(now)) {
            changed(now);
        }
    });
    dispatch_resume(s_WatchTimer);
}

std::vector<MicRules::Input> inputs()
{
    std::vector<MicRules::Input> result;
    for (AudioDeviceID device : allDevices()) {
        if (!hasInput(device)) {
            continue;
        }
        MicRules::Input input;
        input.uid = stringProperty(device, kAudioDevicePropertyDeviceUID);
        input.name = stringProperty(device, kAudioObjectPropertyName);
        input.builtIn = uint32Property(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, 0) == kAudioDeviceTransportTypeBuiltIn;
        if (!input.uid.empty()) {
            result.push_back(input);
        }
    }
    return result;
}

MicRules::Access access()
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
    case AVAuthorizationStatusAuthorized:
        return MicRules::Access::Granted;
    case AVAuthorizationStatusNotDetermined:
        return MicRules::Access::Undetermined;
    default:
        return MicRules::Access::Denied;
    }
}

void requestAccess(std::function<void(bool granted)> done)
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                             completionHandler:^(BOOL granted) {
                                 done(granted == YES);
                             }];
}
}
