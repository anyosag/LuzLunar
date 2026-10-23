#import "notchreach_mac.h"

#import <QuartzCore/QuartzCore.h>

#include <cmath>

// [fork] The notch bar's astral projection, as the design canvas has it (the timings, the curves and
// the look): a ghost of the pointer and three afterimages on a click-through panel over the stream
// and the bar, moved by a timer at the display's pace so the ghost sucked home can follow the PC's
// pointer if it moves meanwhile.

namespace
{
    // Up: the ghost floats up into the strip, then fades as the Mac's pointer shows
    const double k_RiseMs = 220;
    const double k_LandMs = 120;
    // Home: a lurch, as if caught, then sucked in faster and faster along a shallow arc
    const double k_LurchMs = 160;
    const double k_PullMs = 520;
    const double k_ArrivingMs = 460;    // the PC's pulse is asked for then, so it shows as the ghost gets there
    // Afterimages, behind the ghost
    const double k_TrailGapMs = 30;
    const double k_TrailOpacity[3] = { 0.32, 0.2, 0.1 };
    // Pulses drawn here, for a PC that can't pulse its pointer
    const double k_PulseMs = 170;
    const double k_SettleMs = 150;
    const double k_PeakScale = 1.35;

    NSColor* accent()
    {
        return [NSColor colorWithSRGBRed:0x9f / 255.0 green:0xb4 / 255.0 blue:1 alpha:1];
    }

    double clamp01(double v)
    {
        return v < 0 ? 0 : v > 1 ? 1 : v;
    }

    // CSS's cubic-bezier(x1, y1, x2, y2) at t: x(s) = t solved by bisection, then y(s)
    double bezier(double x1, double y1, double x2, double y2, double t)
    {
        t = clamp01(t);
        auto curve = [](double a, double b, double s) {
            double r = 1 - s;
            return 3 * r * r * s * a + 3 * r * s * s * b + s * s * s;
        };
        double lo = 0;
        double hi = 1;
        double s = t;
        for (int i = 0; i < 24; i++) {
            s = (lo + hi) / 2;
            if (curve(x1, x2, s) < t) {
                lo = s;
            }
            else {
                hi = s;
            }
        }
        return curve(y1, y2, s);
    }

    NSPoint lerp(NSPoint a, NSPoint b, double t)
    {
        return NSMakePoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
    }

    // Stretched along angle, not turned
    CATransform3D stretch(double angle, double along, double across)
    {
        CATransform3D t = CATransform3DMakeRotation(angle, 0, 0, 1);
        t = CATransform3DScale(t, along, across, 1);
        return CATransform3DRotate(t, -angle, 0, 0, 1);
    }

    // The PC's arrow, as Windows draws its standard one, height points tall and filled with fill:
    // for a PC that can't pulse its own
    NSImage* pcArrow(CGFloat height, NSColor* fill)
    {
        CGFloat k = height / 20;
        return [NSImage imageWithSize:NSMakeSize(13 * k, 20 * k) flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
            (void)dstRect;
            NSBezierPath* path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(1 * k, 1 * k)];
            [path lineToPoint:NSMakePoint(1 * k, 16 * k)];
            [path lineToPoint:NSMakePoint(4.8 * k, 12.4 * k)];
            [path lineToPoint:NSMakePoint(7.4 * k, 18.2 * k)];
            [path lineToPoint:NSMakePoint(9.6 * k, 17.2 * k)];
            [path lineToPoint:NSMakePoint(7.1 * k, 11.5 * k)];
            [path lineToPoint:NSMakePoint(12 * k, 11.5 * k)];
            [path closePath];
            path.lineJoinStyle = NSLineJoinStyleRound;
            path.lineWidth = 1.1 * k;
            [fill setFill];
            [path fill];
            [[NSColor colorWithWhite:0.07 alpha:1] setStroke];
            [path stroke];
            return YES;
        }];
    }
}

typedef NS_ENUM(NSInteger, ForkReachKind) {
    ForkReachNone,
    ForkReachUp,
    ForkReachHome,
    ForkReachPulse,
    ForkReachSettle,
};

// Never key, so the stream keeps focus
@interface ForkReachPanel : NSPanel
@end

@implementation ForkReachPanel
- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}
@end

@implementation ForkReachOverlay
{
    NSWindow* m_StreamWindow;
    ForkReachPanel* m_Panel;
    CALayer* m_Ghost;
    CALayer* m_Trails[3];
    CALayer* m_Pulse;       // the PC's arrow, and the same in the accent over it
    CALayer* m_PulseTint;
    NSTimer* m_Timer;

    // The ghost's animation and the pulse's run side by side, as the PC's pointer pulses while the
    // ghost gets there
    ForkReachKind m_Kind;
    CFTimeInterval m_Start;
    ForkReachKind m_PulseKind;
    CFTimeInterval m_PulseStart;
    NSPoint m_From;         // in the panel's coordinates
    NSPoint m_To;
    std::function<std::optional<NSPoint>()> m_Target;
    std::function<void()> m_Arriving;
    BOOL m_Arrived;
    BOOL m_InTick;          // arriving can start a pulse from inside a tick
    BOOL m_CursorHidden;
    BOOL m_ReduceMotion;
    int m_PulseCount;
    double m_PulseScale;    // as the pulse drawn here has it now, to settle back from
    double m_PulseTintNow;
    double m_SettleScale;
    double m_SettleTint;
}

- (instancetype)initWithStreamWindow:(NSWindow*)window
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    m_StreamWindow = [window retain];
    m_PulseScale = 1;
    return self;
}

- (void)dealloc
{
    [self invalidate];
    [super dealloc];
}

- (void)makePanel:(NSScreen*)screen
{
    m_Panel = [[ForkReachPanel alloc] initWithContentRect:screen.frame
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    m_Panel.releasedWhenClosed = NO;
    m_Panel.opaque = NO;
    m_Panel.backgroundColor = NSColor.clearColor;
    m_Panel.hasShadow = NO;
    m_Panel.ignoresMouseEvents = YES;
    m_Panel.hidesOnDeactivate = NO;
    // Over the bar and its menus
    m_Panel.level = NSMainMenuWindowLevel + 4;
    m_Panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary |
                                 NSWindowCollectionBehaviorIgnoresCycle;
    m_Panel.contentView.wantsLayer = YES;
    [self makeLayers:screen.backingScaleFactor];
}

// The panel over the stream window's screen, in front, made again when the screen changed
- (BOOL)preparePanel
{
    NSScreen* screen = m_StreamWindow.screen;
    if (screen == nil) {
        return NO;
    }
    if (m_Panel != nil && !NSEqualRects(m_Panel.frame, screen.frame)) {
        [self closePanel];
    }
    if (m_Panel == nil) {
        [self makePanel:screen];
    }
    [m_Panel orderFrontRegardless];
    if (!m_Panel.isOnActiveSpace) {
        // As the bar's (notchbar.mm): once its first fullscreen Space is gone, a panel goes back to
        // the desktop's whenever it's ordered in, and a new one joins the active Space
        [self closePanel];
        [self makePanel:screen];
        [m_Panel orderFrontRegardless];
    }
    return YES;
}

- (void)makeLayers:(CGFloat)scale
{
    CALayer* root = m_Panel.contentView.layer;

    // The Mac's own arrow, so the ghost can become the real pointer
    NSCursor* arrow = NSCursor.arrowCursor;
    NSImage* image = arrow.image;
    id contents = [image layerContentsForContentsScale:scale];
    CGFloat contentsScale = [image recommendedLayerContentsScale:scale];
    NSSize size = image.size;
    // From the image's top left
    NSPoint hot = arrow.hotSpot;
    CGPoint anchor = CGPointMake(size.width > 0 ? hot.x / size.width : 0, size.height > 0 ? 1 - hot.y / size.height : 1);

    auto make = [&](BOOL tinted) {
        CALayer* layer = [CALayer layer];
        layer.bounds = CGRectMake(0, 0, size.width, size.height);
        layer.anchorPoint = anchor;
        layer.opacity = 0;
        if (tinted) {
            // The arrow's shape in the accent
            layer.backgroundColor = accent().CGColor;
            CALayer* mask = [CALayer layer];
            mask.frame = layer.bounds;
            mask.contents = contents;
            mask.contentsScale = contentsScale;
            layer.mask = mask;
        }
        else {
            layer.contents = contents;
            layer.contentsScale = contentsScale;
        }
        [root addSublayer:layer];
        return layer;
    };
    for (int i = 2; i >= 0; i--) {
        m_Trails[i] = [make(YES) retain];
    }
    m_Ghost = [make(NO) retain];

    m_Pulse = [[CALayer layer] retain];
    m_Pulse.opacity = 0;
    [root addSublayer:m_Pulse];
    // Faded in over it: white to the accent, as Apollo tints the PC's own
    m_PulseTint = [[CALayer layer] retain];
    m_PulseTint.opacity = 0;
    [m_Pulse addSublayer:m_PulseTint];
}

- (void)closePanel
{
    [m_Ghost release];
    m_Ghost = nil;
    for (int i = 0; i < 3; i++) {
        [m_Trails[i] release];
        m_Trails[i] = nil;
    }
    [m_Pulse release];
    m_Pulse = nil;
    [m_PulseTint release];
    m_PulseTint = nil;
    [m_Panel orderOut:nil];
    [m_Panel close];
    [m_Panel release];
    m_Panel = nil;
}

- (NSPoint)local:(NSPoint)screenPoint
{
    NSRect frame = m_Panel != nil ? m_Panel.frame : m_StreamWindow.screen.frame;
    return NSMakePoint(screenPoint.x - NSMinX(frame), screenPoint.y - NSMinY(frame));
}

- (void)showCursor
{
    if (m_CursorHidden) {
        m_CursorHidden = NO;
        [NSCursor unhide];
    }
}

- (void)hideGhost
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    m_Ghost.opacity = 0;
    for (int i = 0; i < 3; i++) {
        m_Trails[i].opacity = 0;
    }
    [CATransaction commit];
}

- (void)hidePulse
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    m_Pulse.opacity = 0;
    m_PulseTint.opacity = 0;
    [CATransaction commit];
}

- (void)stopGhost
{
    m_Kind = ForkReachNone;
    m_Target = nullptr;
    m_Arriving = nullptr;
    [self showCursor];
    [self hideGhost];
}

- (void)stopPulse
{
    m_PulseKind = ForkReachNone;
    m_PulseScale = 1;
    m_PulseTintNow = 0;
    [self hidePulse];
}

// Once neither plays
- (void)idle
{
    if (m_Kind != ForkReachNone || m_PulseKind != ForkReachNone) {
        return;
    }
    [m_Timer invalidate];
    [m_Timer release];
    m_Timer = nil;
    [m_Panel orderOut:nil];
}

- (void)stop
{
    [self stopGhost];
    [self stopPulse];
    [self idle];
}

- (void)run
{
    m_ReduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (m_Timer == nil) {
        m_Timer = [[NSTimer timerWithTimeInterval:1.0 / 120 target:self selector:@selector(tick:) userInfo:nil repeats:YES] retain];
        [NSRunLoop.mainRunLoop addTimer:m_Timer forMode:NSRunLoopCommonModes];
    }
    if (!m_InTick) {
        [self tick:nil];
    }
}

- (void)play:(ForkReachKind)kind
{
    m_Kind = kind;
    m_Start = CACurrentMediaTime();
    [self run];
}

- (void)playPulse:(ForkReachKind)kind
{
    m_PulseKind = kind;
    m_PulseStart = CACurrentMediaTime();
    [self run];
}

- (void)projectFrom:(NSPoint)from to:(NSPoint)to
{
    [self stop];
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion || ![self preparePanel]) {
        // The Mac's pointer is just there
        [self idle];
        return;
    }
    m_From = [self local:from];
    m_To = [self local:to];
    // Hidden until the ghost gets there
    [NSCursor hide];
    m_CursorHidden = YES;
    [self play:ForkReachUp];
}

- (void)pullFrom:(NSPoint)from target:(std::function<std::optional<NSPoint>()>)target arriving:(std::function<void()>)arriving
{
    [self stop];
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion || ![self preparePanel]) {
        [self idle];
        if (arriving) {
            arriving();
        }
        return;
    }
    m_From = [self local:from];
    std::optional<NSPoint> now = target ? target() : std::nullopt;
    m_To = now ? [self local:*now] : m_From;
    m_Target = std::move(target);
    m_Arriving = std::move(arriving);
    m_Arrived = NO;
    [self play:ForkReachHome];
}

- (void)pulseAt:(NSPoint)point count:(int)count size:(CGFloat)size
{
    [self stopPulse];
    if (count <= 0 || ![self preparePanel]) {
        [self idle];
        return;
    }
    CGFloat height = MAX(size, 8);
    NSImage* image = pcArrow(height, NSColor.whiteColor);
    NSImage* tinted = pcArrow(height, accent());
    CGFloat scale = m_Panel.backingScaleFactor;
    CGFloat k = height / 20;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    m_Pulse.bounds = CGRectMake(0, 0, image.size.width, image.size.height);
    // The arrow's tip, at (1, 1) of its 13 by 20 from the top left
    m_Pulse.anchorPoint = CGPointMake(1 * k / image.size.width, 1 - 1 * k / image.size.height);
    m_Pulse.contents = [image layerContentsForContentsScale:scale];
    m_Pulse.contentsScale = [image recommendedLayerContentsScale:scale];
    m_Pulse.position = [self local:point];
    m_PulseTint.frame = m_Pulse.bounds;
    m_PulseTint.contents = [tinted layerContentsForContentsScale:scale];
    m_PulseTint.contentsScale = [tinted recommendedLayerContentsScale:scale];
    [CATransaction commit];
    m_PulseCount = count;
    [self playPulse:ForkReachPulse];
}

- (void)settlePulse
{
    if (m_PulseKind != ForkReachPulse) {
        return;
    }
    m_SettleScale = m_PulseScale;
    m_SettleTint = m_PulseTintNow;
    [self playPulse:ForkReachSettle];
}

- (void)invalidate
{
    [self stop];
    [self closePanel];
    [m_StreamWindow release];
    m_StreamWindow = nil;
}

- (void)tick:(NSTimer*)timer
{
    (void)timer;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL ghostDone = NO;
    BOOL pulseDone = NO;
    m_InTick = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    double ms = (now - m_Start) * 1000;
    switch (m_Kind) {
    case ForkReachUp:
        ghostDone = [self drawUp:ms];
        break;
    case ForkReachHome:
        ghostDone = [self drawHome:ms];
        break;
    default:
        break;
    }
    double pulseMs = (now - m_PulseStart) * 1000;
    switch (m_PulseKind) {
    case ForkReachPulse:
        pulseDone = [self drawPulse:pulseMs];
        break;
    case ForkReachSettle:
        pulseDone = [self drawSettle:pulseMs];
        break;
    default:
        break;
    }
    [CATransaction commit];
    m_InTick = NO;
    if (ghostDone) {
        [self stopGhost];
    }
    if (pulseDone) {
        [self stopPulse];
    }
    [self idle];
}

// Up into the strip: 220 ms with a slight overshoot, afterimages 30 ms apart, then the ghost fades
// as the Mac's pointer shows
- (BOOL)drawUp:(double)ms
{
    // The Mac's pointer may move while it's hidden: the ghost goes to where it is now, so the pointer
    // shows under it. Once the warp has taken, that's above where the ghost set off.
    NSPoint mouse = [self local:NSEvent.mouseLocation];
    if (mouse.y > m_From.y) {
        m_To = mouse;
    }
    auto rise = [&](double t) {
        return lerp(m_From, m_To, bezier(0.2, 0.9, 0.25, 1.15, t / k_RiseMs));
    };
    if (ms < k_RiseMs) {
        m_Ghost.position = rise(ms);
        m_Ghost.opacity = 0.55 + 0.35 * (ms / k_RiseMs);
    }
    else {
        [self showCursor];
        m_Ghost.position = m_To;
        m_Ghost.opacity = 0.9 * (1 - clamp01((ms - k_RiseMs) / k_LandMs));
    }
    m_Ghost.transform = CATransform3DIdentity;
    BOOL trails = NO;
    for (int i = 0; i < 3; i++) {
        double t = ms - k_TrailGapMs * (i + 1);
        if (t >= 0 && t < k_RiseMs) {
            m_Trails[i].position = rise(t);
            m_Trails[i].transform = CATransform3DIdentity;
            m_Trails[i].opacity = k_TrailOpacity[i] * (1 - t / k_RiseMs);
            trails = YES;
        }
        else {
            m_Trails[i].opacity = 0;
            trails = trails || t < 0;
        }
    }
    return ms >= k_RiseMs + k_LandMs && !trails;
}

// Where the ghost is t ms into the pull home, and how it's stretched
- (void)place:(CALayer*)layer at:(double)t target:(NSPoint)target opacity:(double)opacity
{
    NSPoint from = m_From;
    double dx = target.x - from.x;
    double dy = target.y - from.y;
    double distance = std::hypot(dx, dy);
    if (t < k_LurchMs) {
        // Away from home, as if caught, then jolted back
        double ax = distance > 0 ? -dx / distance : 0;
        double ay = distance > 0 ? -dy / distance : 1;
        double w = std::sin(M_PI * t / k_LurchMs);
        layer.position = NSMakePoint(from.x + ax * 9 * w, from.y + ay * 9 * w);
        layer.transform = CATransform3DMakeRotation(-0.17 * std::sin(2 * M_PI * t / k_LurchMs), 0, 0, 1);
        layer.opacity = opacity;
        return;
    }
    // Then along a shallow arc, faster and faster: stretched along the way, shrinking to nothing
    double e = bezier(0.42, 0, 1, 1, (t - k_LurchMs) / (k_PullMs - k_LurchMs));
    double px = distance > 0 ? -dy / distance : 0;
    double py = distance > 0 ? dx / distance : 1;
    if (py < 0) {
        // The arc bows upward
        px = -px;
        py = -py;
    }
    NSPoint control = NSMakePoint((from.x + target.x) / 2 + px * distance * 0.12, (from.y + target.y) / 2 + py * distance * 0.12);
    double r = 1 - e;
    layer.position = NSMakePoint(r * r * from.x + 2 * r * e * control.x + e * e * target.x,
                                 r * r * from.y + 2 * r * e * control.y + e * e * target.y);
    double tx = 2 * r * (control.x - from.x) + 2 * e * (target.x - control.x);
    double ty = 2 * r * (control.y - from.y) + 2 * e * (target.y - control.y);
    double angle = std::atan2(ty, tx);
    double k = 1 + 0.8 * 4 * e * (1 - e);
    double size = 1 - 0.85 * e * e * e;
    layer.transform = distance > 0 ? stretch(angle, k * size, size / k) : CATransform3DMakeScale(size, size, 1);
    layer.opacity = e < 0.6 ? opacity : opacity * (1 - (e - 0.6) / 0.4);
}

// Sucked back home: a lurch, then pulled in by 520 ms, to wherever the PC's pointer is now
- (BOOL)drawHome:(double)ms
{
    if (m_Target) {
        std::optional<NSPoint> now = m_Target();
        if (now) {
            m_To = [self local:*now];
        }
    }
    if (!m_Arrived && ms >= k_ArrivingMs) {
        m_Arrived = YES;
        if (m_Arriving) {
            m_Arriving();
        }
    }
    if (ms <= k_PullMs) {
        [self place:m_Ghost at:ms target:m_To opacity:0.85];
    }
    else {
        m_Ghost.opacity = 0;
    }
    BOOL trails = NO;
    for (int i = 0; i < 3; i++) {
        double t = ms - k_TrailGapMs * (i + 1);
        if (t >= k_LurchMs && t <= k_PullMs) {
            [self place:m_Trails[i] at:t target:m_To opacity:k_TrailOpacity[i]];
            trails = YES;
        }
        else {
            m_Trails[i].opacity = 0;
            trails = trails || t < k_LurchMs;
        }
    }
    return ms > k_PullMs && !trails;
}

// Pulses over the PC's pointer: larger and tinted, then back, eased in and out; with Reduce Motion
// only the tint
- (BOOL)drawPulse:(double)ms
{
    if (ms >= m_PulseCount * k_PulseMs) {
        return YES;
    }
    double phase = std::fmod(ms, k_PulseMs) / k_PulseMs;
    double w = (1 - std::cos(2 * M_PI * phase)) / 2;
    m_PulseScale = m_ReduceMotion ? 1 : 1 + (k_PeakScale - 1) * w;
    m_PulseTintNow = w;
    m_Pulse.opacity = 1;
    m_Pulse.transform = CATransform3DMakeScale(m_PulseScale, m_PulseScale, 1);
    m_PulseTint.opacity = m_PulseTintNow;
    return NO;
}

- (BOOL)drawSettle:(double)ms
{
    double t = clamp01(ms / k_SettleMs);
    double e = 1 - (1 - t) * (1 - t);
    double scale = m_SettleScale + (1 - m_SettleScale) * e;
    m_Pulse.opacity = 1;
    m_Pulse.transform = CATransform3DMakeScale(scale, scale, 1);
    m_PulseTint.opacity = m_SettleTint * (1 - e);
    return t >= 1;
}
@end
