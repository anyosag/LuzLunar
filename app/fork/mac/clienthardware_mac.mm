#include "fork/clienthardware.h"

#include "streaming/streamutils.h"

#include <cmath>

#include <sys/sysctl.h>

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>

namespace
{
    // The same limit as StreamUtils::getNativeDesktopMode()
    const uint32_t k_MaxDisplays = 16;

    QString chipName()
    {
        size_t size = 0;
        if (sysctlbyname("machdep.cpu.brand_string", nullptr, &size, nullptr, 0) != 0 || size == 0) {
            return QString();
        }

        QByteArray brand(static_cast<qsizetype>(size), '\0');
        if (sysctlbyname("machdep.cpu.brand_string", brand.data(), &size, nullptr, 0) != 0) {
            return QString();
        }
        return QString::fromUtf8(brand.constData()).trimmed();
    }

    // Keep in sync with VTBaseRenderer::checkDecoderCapabilities() in vt_base.mm: there's no API
    // to ask for HEVC Main10 hardware decoding, so it's judged from the GPU
    bool hasHevcMain10(id<MTLDevice> device)
    {
        if (device == nil || ![device supportsFamily:MTLGPUFamilyMac2]) {
            return false;
        }

        if ([device.name containsString:@"Intel"]) {
            // 500-series Intel GPUs are Skylake and don't support Main10 hardware decoding
            return ![device.name containsString:@" 5"];
        }
        if ([device.name containsString:@"AMD"]) {
            // FirePro D, M200 and M300 series GPUs don't support Main10 hardware decoding
            return !([device.name containsString:@"FirePro D"] ||
                     [device.name containsString:@" M2"] ||
                     [device.name containsString:@" M3"]);
        }
        return true;
    }

    // The screen with this display ID, nil if AppKit has none for it
    NSScreen* screenFor(CGDirectDisplayID displayId)
    {
        for (NSScreen* screen in NSScreen.screens) {
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == displayId) {
                return screen;
            }
        }
        return nil;
    }

    ClientHardware::Display readDisplay(int index, CGDirectDisplayID displayId)
    {
        ClientHardware::Display display;
        ForkHwRules::Display& rules = display.rules;

        // The same native and below-the-notch sizes the session uses, so they agree with its
        // notch handling and Settings' resolution list. Only the sizes are used: the refresh
        // rate it reports needs SDL's video system.
        SDL_DisplayMode nativeMode;
        SDL_Rect safeArea;
        SDL_zero(nativeMode);
        SDL_zero(safeArea);
        if (StreamUtils::getNativeDesktopMode(index, &nativeMode, &safeArea) && nativeMode.w > 0 && nativeMode.h > 0) {
            rules.nativeWidth = nativeMode.w;
            rules.nativeHeight = nativeMode.h;
            rules.safeWidth = safeArea.w;
            rules.safeHeight = safeArea.h;
        }
        else if (CGDisplayModeRef current = CGDisplayCopyDisplayMode(displayId)) {
            // No mode is marked native (a virtual display, say): the current mode's pixels
            rules.nativeWidth = rules.safeWidth = static_cast<int>(CGDisplayModeGetPixelWidth(current));
            rules.nativeHeight = rules.safeHeight = static_cast<int>(CGDisplayModeGetPixelHeight(current));
            CFRelease(current);
        }

        display.isBuiltin = CGDisplayIsBuiltin(displayId);

        // From the display's EDID; zero when it has none
        CGSize sizeMm = CGDisplayScreenSize(displayId);
        rules.widthMm = static_cast<int>(std::lround(sizeMm.width));
        rules.heightMm = static_cast<int>(std::lround(sizeMm.height));

        CGRect bounds = CGDisplayBounds(displayId);
        display.pointWidth = static_cast<int>(std::lround(bounds.size.width));
        display.pointHeight = static_cast<int>(std::lround(bounds.size.height));
        display.originX = static_cast<int>(std::lround(bounds.origin.x));
        display.originY = static_cast<int>(std::lround(bounds.origin.y));

        display.displayId = displayId;
        display.vendor = CGDisplayVendorNumber(displayId);
        display.model = CGDisplayModelNumber(displayId);
        display.serial = CGDisplaySerialNumber(displayId);
        display.isMain = CGDisplayIsMain(displayId);
        display.isMirror = CGDisplayMirrorsDisplay(displayId) != kCGNullDirectDisplay;

        // DisplayExtend's virtual display has vendor 'DM' and product 1 (its VirtualDisplayShim.m);
        // its serial changes for test runs, so it isn't checked
        display.isDisplayExtend = display.vendor == 0x444D && display.model == 1;

        NSScreen* screen = screenFor(displayId);
        if (screen != nil) {
            rules.name = screen.localizedName.UTF8String;
            rules.scale = screen.backingScaleFactor;
            rules.hasNotch = screen.safeAreaInsets.top > 0;
            rules.maxRefresh = static_cast<int>(screen.maximumFramesPerSecond);

            // Above 1 means the panel can show brighter than SDR white, which is HDR (EDR on a Mac)
            rules.hdr = screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0;
            rules.edrPotential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
            rules.edrCurrent = screen.maximumExtendedDynamicRangeColorComponentValue;
            rules.edrReference = screen.maximumReferenceExtendedDynamicRangeColorComponentValue;
            rules.p3 = [screen canRepresentDisplayGamut:NSDisplayGamutP3];

            // ProMotion's slowest rate; a fixed-rate screen reports the same as its fastest
            if (screen.maximumRefreshInterval > 0) {
                rules.minRefresh = static_cast<int>(std::lround(1.0 / screen.maximumRefreshInterval));
            }
        }
        else {
            rules.name = "Display " + std::to_string(index + 1);
        }

        return display;
    }
}

ClientHardware::Snapshot ClientHardwarePlatform::read()
{
    ClientHardware::Snapshot snapshot;
    snapshot.chip = chipName();

    @autoreleasepool {
        // MTLCreateSystemDefaultDevice() is nil without a GPU, like in some CI VMs
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device != nil) {
            snapshot.gpu = QString::fromNSString(device.name);
        }

        snapshot.decoders.h264 = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264);
        snapshot.decoders.hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
        snapshot.decoders.hevcMain10 = snapshot.decoders.hevc && hasHevcMain10(device);
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000
        snapshot.decoders.av1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
#endif
        [device release];

        // The order StreamUtils::getNativeDesktopMode() takes its display index in
        CGDirectDisplayID displayIds[k_MaxDisplays];
        uint32_t displayCount = 0;
        if (CGGetActiveDisplayList(k_MaxDisplays, displayIds, &displayCount) != kCGErrorSuccess) {
            displayCount = 0;
        }
        for (uint32_t i = 0; i < displayCount; i++) {
            snapshot.displays.push_back(readDisplay(static_cast<int>(i), displayIds[i]));
        }
    }

    return snapshot;
}

void ClientHardwarePlatform::watchDisplays(std::function<void()> onChange)
{
    // Lives as long as the app, so the observer is never removed. The main queue is Qt's GUI thread.
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidChangeScreenParametersNotification
                                                      object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification*) {
        onChange();
    }];
}
