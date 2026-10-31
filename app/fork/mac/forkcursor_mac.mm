#include "forkcursor_mac.h"

#include <cmath>
#include <cstdint>
#include <vector>

#include <SDL_syswm.h>

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

// [fork] See forkcursor_mac.h. Manual retain and release, as the rest of app/fork/mac.

namespace
{
    // As Apollo pulses the PC's own pointer (its cursor_pulse.h), and the notch bar over the picture
    const double k_PulseMs = 170;
    const double k_PeakScale = 1.35;

    // SDL 2's SDL_Cursor (its src/events/SDL_mouse_c.h), the same through 2.x: the Cocoa video
    // driver keeps the NSCursor in driverdata, retained, and releases it in SDL_FreeCursor()
    struct SdlCursorLayout {
        void* next;
        void* driverdata;
    };

    NSWindow* cocoaWindow(SDL_Window* window)
    {
        SDL_SysWMinfo info;
        SDL_VERSION(&info.version);
        if (window == nullptr || !SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) {
            return nil;
        }
        return info.info.cocoa.window;
    }

    NSColor* accent()
    {
        return [NSColor colorWithSRGBRed:0x9f / 255.0 green:0xb4 / 255.0 blue:1 alpha:1];
    }

    // The shape as the Mac draws it, every pixel of it, in sRGB; CGImageRelease() it
    CGImageRef makeImage(const luzcursor::shape_t& shape)
    {
        std::vector<std::uint8_t> bgra = luzcursor::display_pixels(shape);
        std::size_t width = static_cast<std::size_t>(shape.width);
        std::size_t height = static_cast<std::size_t>(shape.height);
        CFIndex length = static_cast<CFIndex>(width * height * 4);
        CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, length);
        if (data == nullptr) {
            return nullptr;
        }
        CFDataSetLength(data, length);
        UInt8* rgba = CFDataGetMutableBytePtr(data);
        // Core Graphics takes its alpha premultiplied
        for (std::size_t i = 0; i < width * height; i++) {
            unsigned alpha = bgra[i * 4 + 3];
            rgba[i * 4 + 0] = static_cast<UInt8>((bgra[i * 4 + 2] * alpha + 127) / 255);
            rgba[i * 4 + 1] = static_cast<UInt8>((bgra[i * 4 + 1] * alpha + 127) / 255);
            rgba[i * 4 + 2] = static_cast<UInt8>((bgra[i * 4 + 0] * alpha + 127) / 255);
            rgba[i * 4 + 3] = static_cast<UInt8>(alpha);
        }
        CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
        CFRelease(data);
        if (provider == nullptr) {
            return nullptr;
        }
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, space,
                                         (CGBitmapInfo)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault),
                                         provider, nullptr, false, kCGRenderingIntentDefault);
        CGColorSpaceRelease(space);
        CGDataProviderRelease(provider);
        return image;
    }

    // The shape at its size in points, from all of its pixels, so Retina draws it sharp; release it
    NSImage* makeNSImage(const luzcursor::shape_t& shape, double pointsPerPixel)
    {
        CGImageRef image = makeImage(shape);
        if (image == nullptr) {
            return nil;
        }
        NSImage* nsImage = [[NSImage alloc] initWithCGImage:image
                                                       size:NSMakeSize(shape.width * pointsPerPixel, shape.height * pointsPerPixel)];
        CGImageRelease(image);
        return nsImage;
    }
}

SDL_Cursor* ForkCursorMac::createCursor(const luzcursor::shape_t& shape, double pointsPerPixel)
{
    @autoreleasepool {
        if (!luzcursor::well_formed(shape) || !(pointsPerPixel > 0)) {
            return nullptr;
        }
        // Only SDL 2 has the layout above
        SDL_version linked;
        SDL_GetVersion(&linked);
        if (linked.major != 2) {
            return nullptr;
        }

        NSImage* image = makeNSImage(shape, pointsPerPixel);
        if (image == nil) {
            return nullptr;
        }
        NSCursor* nsCursor = [[NSCursor alloc] initWithImage:image
                                                     hotSpot:NSMakePoint(shape.hotspot_x * pointsPerPixel, shape.hotspot_y * pointsPerPixel)];
        [image release];
        if (nsCursor == nil) {
            return nullptr;
        }

        // An SDL cursor whose NSCursor is this one, so the cursor rects SDL keeps over the stream use it
        SDL_Surface* surface = SDL_CreateRGBSurfaceWithFormat(0, 1, 1, 32, SDL_PIXELFORMAT_ARGB8888);
        if (surface == nullptr) {
            [nsCursor release];
            return nullptr;
        }
        SDL_memset(surface->pixels, 0, static_cast<size_t>(surface->pitch));
        SDL_Cursor* cursor = SDL_CreateColorCursor(surface, 0, 0);
        SDL_FreeSurface(surface);
        if (cursor == nullptr) {
            [nsCursor release];
            return nullptr;
        }
        SdlCursorLayout* raw = reinterpret_cast<SdlCursorLayout*>(cursor);
        id own = (id)raw->driverdata;
        if (own == nil || ![own isKindOfClass:[NSCursor class]]) {
            // Not the layout above after all
            [nsCursor release];
            SDL_FreeCursor(cursor);
            return nullptr;
        }
        [own release];
        raw->driverdata = (void*)nsCursor;
        return cursor;
    }
}

// Never key, so the stream keeps focus
@interface ForkCursorPanel : NSPanel
@end

@implementation ForkCursorPanel
- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}
@end

struct ForkCursorMac::Sprite::Impl
{
    NSWindow* window = nil;     // the stream's, retained
    ForkCursorPanel* panel = nil;
    CALayer* layer = nil;       // the shape, its anchor at the hotspot
    CALayer* tint = nil;        // the accent over it, in its shape, for the pulses
    CALayer* tintMask = nil;
    NSImage* image = nil;
    std::shared_ptr<const luzcursor::shape_t> shape;
    double pointsPerPixel = 0;

    // A click-through panel over the stream window's content, held just above it as its child, so
    // it goes where the window goes (another Space, full screen) and stays under what's above it
    bool prepare()
    {
        if (window == nil) {
            return false;
        }
        NSRect frame = [window contentRectForFrameRect:window.frame];
        if (panel == nil) {
            panel = [[ForkCursorPanel alloc] initWithContentRect:frame
                                                       styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
            panel.releasedWhenClosed = NO;
            panel.opaque = NO;
            panel.backgroundColor = NSColor.clearColor;
            panel.hasShadow = NO;
            panel.ignoresMouseEvents = YES;
            panel.hidesOnDeactivate = NO;
            panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
            panel.contentView.wantsLayer = YES;

            layer = [[CALayer layer] retain];
            layer.hidden = YES;
            tint = [[CALayer layer] retain];
            tint.opacity = 0;
            tint.backgroundColor = accent().CGColor;
            tintMask = [[CALayer layer] retain];
            tint.mask = tintMask;
            [layer addSublayer:tint];
            [panel.contentView.layer addSublayer:layer];
            applyShape();
        }
        else if (!NSEqualRects(panel.frame, frame)) {
            [panel setFrame:frame display:NO];
        }
        if (panel.parentWindow != window) {
            panel.level = window.level;
            [window addChildWindow:panel ordered:NSWindowAbove];
        }
        return true;
    }

    void applyShape()
    {
        if (layer == nil || shape == nullptr || image == nil) {
            return;
        }
        CGFloat scale = window.backingScaleFactor > 0 ? window.backingScaleFactor : 2;
        id contents = [image layerContentsForContentsScale:scale];
        CGFloat contentsScale = [image recommendedLayerContentsScale:scale];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.bounds = CGRectMake(0, 0, shape->width * pointsPerPixel, shape->height * pointsPerPixel);
        // From the image's top left; the layer's y goes up
        layer.anchorPoint = CGPointMake(static_cast<double>(shape->hotspot_x) / shape->width,
                                        1 - static_cast<double>(shape->hotspot_y) / shape->height);
        layer.contents = contents;
        layer.contentsScale = contentsScale;
        layer.contentsGravity = kCAGravityResize;
        tint.frame = layer.bounds;
        tintMask.frame = tint.bounds;
        tintMask.contents = contents;
        tintMask.contentsScale = contentsScale;
        tintMask.contentsGravity = kCAGravityResize;
        [CATransaction commit];
    }

    void close()
    {
        if (panel != nil) {
            if (panel.parentWindow != nil) {
                [panel.parentWindow removeChildWindow:panel];
            }
            [panel orderOut:nil];
            [panel close];
            [panel release];
            panel = nil;
        }
        [tintMask release];
        tintMask = nil;
        [tint release];
        tint = nil;
        [layer release];
        layer = nil;
    }
};

ForkCursorMac::Sprite::Sprite(SDL_Window* window)
    : m_Impl(new Impl)
{
    m_Impl->window = [cocoaWindow(window) retain];
}

ForkCursorMac::Sprite::~Sprite()
{
    @autoreleasepool {
        m_Impl->close();
        [m_Impl->image release];
        [m_Impl->window release];
    }
    delete m_Impl;
}

void ForkCursorMac::Sprite::setShape(const std::shared_ptr<const luzcursor::shape_t>& shape, double pointsPerPixel)
{
    @autoreleasepool {
        Impl& m = *m_Impl;
        if (shape == m.shape && pointsPerPixel == m.pointsPerPixel) {
            return;
        }
        m.shape = shape;
        m.pointsPerPixel = pointsPerPixel;
        [m.image release];
        m.image = shape != nullptr && pointsPerPixel > 0 ? makeNSImage(*shape, pointsPerPixel) : nil;
        m.applyShape();
    }
}

void ForkCursorMac::Sprite::show(double x, double y)
{
    @autoreleasepool {
        Impl& m = *m_Impl;
        if (m.shape == nullptr || m.image == nil || !m.prepare()) {
            return;
        }
        CGFloat height = m.panel.contentView.bounds.size.height;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        m.layer.position = CGPointMake(x, height - y);
        m.layer.hidden = NO;
        [CATransaction commit];
    }
}

void ForkCursorMac::Sprite::hide()
{
    @autoreleasepool {
        Impl& m = *m_Impl;
        if (m.layer == nil || m.layer.hidden) {
            return;
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        m.layer.hidden = YES;
        [CATransaction commit];
    }
}

void ForkCursorMac::Sprite::pulse(int count, bool reduceMotion)
{
    @autoreleasepool {
        Impl& m = *m_Impl;
        if (m.layer == nil || count <= 0) {
            return;
        }
        // Up and back down each pulse, as Apollo's: the larger size and the accent at its middle
        NSMutableArray* times = [NSMutableArray array];
        NSMutableArray* scales = [NSMutableArray array];
        NSMutableArray* tints = [NSMutableArray array];
        NSMutableArray* curves = [NSMutableArray array];
        CAMediaTimingFunction* curve = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        for (int i = 0; i <= count * 2; i++) {
            bool peak = i % 2 == 1;
            [times addObject:@(static_cast<double>(i) / (count * 2))];
            [scales addObject:@(peak ? k_PeakScale : 1.0)];
            [tints addObject:@(peak ? 1.0 : 0.0)];
            if (i > 0) {
                [curves addObject:curve];
            }
        }
        CFTimeInterval duration = count * k_PulseMs / 1000.0;

        [m.layer removeAnimationForKey:@"forkPulse"];
        [m.tint removeAnimationForKey:@"forkPulse"];
        if (!reduceMotion) {
            CAKeyframeAnimation* grow = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            grow.values = scales;
            grow.keyTimes = times;
            grow.timingFunctions = curves;
            grow.duration = duration;
            [m.layer addAnimation:grow forKey:@"forkPulse"];
        }
        CAKeyframeAnimation* color = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        color.values = tints;
        color.keyTimes = times;
        color.timingFunctions = curves;
        color.duration = duration;
        [m.tint addAnimation:color forKey:@"forkPulse"];
    }
}

void ForkCursorMac::Sprite::settle()
{
    @autoreleasepool {
        Impl& m = *m_Impl;
        [m.layer removeAnimationForKey:@"forkPulse"];
        [m.tint removeAnimationForKey:@"forkPulse"];
    }
}
