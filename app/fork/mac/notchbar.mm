#include "notchbar.h"

#include "fork/streamstats.h"
#include "SDL_compat.h"

#include <atomic>

#include <QCoreApplication>

#include <SDL_syswm.h>

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

namespace
{
    const CGFloat k_Margin = 10;      // between a pill and the edge of its area
    const CGFloat k_Padding = 12;     // inside a pill, around its content
    const CGFloat k_IconGap = 6;      // between the message icon and its text
    const CGFloat k_TitleGap = 8;     // between the title and a message beside it
    const CGFloat k_DotSize = 8;
    const int64_t k_ToastDurationNs = 3 * NSEC_PER_SEC;
}

// A panel that can never take focus from the stream window: if it became key, SDL would treat
// it as the stream losing focus.
@interface ForkNotchPanel : NSPanel
@end

@implementation ForkNotchPanel
- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}
@end

typedef NS_ENUM(NSInteger, ForkMessageState) {
    ForkMessageHidden,
    ForkMessageBlinking,    // the red dot blinks beside the notch
    ForkMessageExpanding,   // the dot grows into the pill
    ForkMessageShown,
    ForkMessageChanging,    // another message replaces the one shown
    ForkMessageCollapsing,  // the pill shrinks away
};

@interface ForkNotchBarController : NSObject
{
    NSWindow* m_StreamWindow;   // retained: SDL destroys the window before the stream's fork extensions go away
    ForkNotchPanel* m_Panel;
    NSView* m_LeftPill;
    NSView* m_RightPill;
    NSTextField* m_LeftLabel;
    NSTextField* m_RightLabel;

    // Messages beside the notch, in a pill that grows out of a blinking red dot
    NSView* m_MessagePill;
    NSImageView* m_MessageIcon;
    NSTextField* m_MessageLabel;
    NSView* m_Dot;
    NSString* m_Warning;            // the connection warning, until the connection recovers
    NSString* m_Toast;              // a clipboard message, shown for a few seconds
    unsigned m_ToastGeneration;
    unsigned m_ToastTimerGeneration;
    BOOL m_ShowsWarning;            // the pill holds the warning rather than a clipboard message
    ForkMessageState m_MessageState;
    unsigned m_AnimationGeneration; // completion handlers of older animations do nothing
    std::atomic<bool> m_OnScreen;

    // The area left of the notch and the pill size, in panel coordinates, from the last refresh
    BOOL m_HasGeometry;
    NSRect m_LeftArea;
    CGFloat m_PillHeight;
    CGFloat m_PillY;
}
- (instancetype)initWithStreamWindow:(NSWindow*)window title:(NSString*)title;
- (void)setStatsText:(NSString*)text;
- (void)setWarning:(NSString*)text;
- (void)showToast:(NSString*)text;
- (BOOL)isOnScreen;
- (void)invalidate;
@end

@implementation ForkNotchBarController

static NSTextField* makeLabel(NSString* text)
{
    NSTextField* label = [[NSTextField labelWithString:text] retain];
    label.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
    label.textColor = NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    return label;
}

static NSImage* symbolImage(NSString* name)
{
    if (@available(macOS 11.0, *)) {
        NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:12
                                                                                                   weight:NSFontWeightMedium]];
    }
    return nil;
}

// A capsule of Liquid Glass (macOS 26) or vibrancy holding the views. Returns a +1 reference.
static NSView* makePill(NSArray<NSView*>* views)
{
    NSView* container = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    for (NSView* view in views) {
        [container addSubview:view];
    }

    if (@available(macOS 26.0, *)) {
        NSGlassEffectView* glass = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
        glass.contentView = container;
        return glass;
    }

    NSVisualEffectView* effect = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.wantsLayer = YES;
    effect.layer.masksToBounds = YES;
    [effect addSubview:container];
    return effect;
}

static void setCapsuleShape(NSView* pill, CGFloat height)
{
    if (@available(macOS 26.0, *)) {
        if ([pill isKindOfClass:NSGlassEffectView.class]) {
            ((NSGlassEffectView*)pill).cornerRadius = height / 2;
        }
    }
    if (pill.layer != nil) {
        pill.layer.cornerRadius = height / 2;
    }
}

// Sets a standalone layer's opacity, animated over the duration, or at once for 0
static void setLayerOpacity(CALayer* layer, float opacity, CFTimeInterval duration)
{
    [CATransaction begin];
    if (duration > 0) {
        [CATransaction setAnimationDuration:duration];
    }
    else {
        [CATransaction setDisableActions:YES];
    }
    layer.opacity = opacity;
    [CATransaction commit];
}

static BOOL reduceMotion()
{
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

- (instancetype)initWithStreamWindow:(NSWindow*)window title:(NSString*)title
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    m_StreamWindow = [window retain];

    m_Panel = [[ForkNotchPanel alloc] initWithContentRect:NSZeroRect
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    m_Panel.releasedWhenClosed = NO;
    m_Panel.opaque = NO;
    m_Panel.backgroundColor = NSColor.clearColor;
    m_Panel.hasShadow = NO;
    m_Panel.ignoresMouseEvents = YES;
    m_Panel.hidesOnDeactivate = NO;
    m_Panel.becomesKeyOnlyIfNeeded = YES;
    // Above the stream window's level, and allowed into its fullscreen Space
    m_Panel.level = NSMainMenuWindowLevel + 2;
    m_Panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary |
                                 NSWindowCollectionBehaviorStationary |
                                 NSWindowCollectionBehaviorIgnoresCycle;
    // The strip beside the notch is black, so always use light-on-dark text
    m_Panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    m_LeftLabel = makeLabel(title);
    m_RightLabel = makeLabel(@"—");
    m_LeftPill = makePill(@[ m_LeftLabel ]);
    m_RightPill = makePill(@[ m_RightLabel ]);

    m_MessageLabel = makeLabel(@"");
    m_MessageIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    m_MessageIcon.imageScaling = NSImageScaleNone;
    m_MessagePill = makePill(@[ m_MessageIcon, m_MessageLabel ]);
    m_MessagePill.alphaValue = 0;

    // A layer-hosting view, so AppKit leaves the layer's color and shape alone
    m_Dot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, k_DotSize, k_DotSize)];
    CALayer* dot = [CALayer layer];
    dot.backgroundColor = NSColor.systemRedColor.CGColor;
    dot.cornerRadius = k_DotSize / 2;
    m_Dot.layer = dot;
    m_Dot.wantsLayer = YES;
    m_Dot.hidden = YES;

    m_MessageState = ForkMessageHidden;
    m_OnScreen = false;

    [m_Panel.contentView addSubview:m_LeftPill];
    [m_Panel.contentView addSubview:m_RightPill];
    // The dot sits under the pill that grows out of it
    [m_Panel.contentView addSubview:m_Dot];
    [m_Panel.contentView addSubview:m_MessagePill];

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[ NSWindowDidEnterFullScreenNotification,
                                       NSWindowDidExitFullScreenNotification,
                                       NSWindowDidMiniaturizeNotification,
                                       NSWindowDidDeminiaturizeNotification,
                                       NSWindowDidChangeScreenNotification ]) {
        [center addObserver:self selector:@selector(stateChanged:) name:name object:m_StreamWindow];
    }
    [center addObserver:self selector:@selector(stateChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(stateChanged:)
                                                           name:NSWorkspaceActiveSpaceDidChangeNotification
                                                         object:nil];

    [self refresh];
    return self;
}

- (void)dealloc
{
    [m_StreamWindow release];
    [m_Panel release];
    [m_LeftPill release];
    [m_RightPill release];
    [m_LeftLabel release];
    [m_RightLabel release];
    [m_MessagePill release];
    [m_MessageIcon release];
    [m_MessageLabel release];
    [m_Dot release];
    [m_Warning release];
    [m_Toast release];
    [super dealloc];
}

- (void)invalidate
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    // Animations and timers still queued find the controller invalidated and do nothing
    m_AnimationGeneration++;
    m_OnScreen = false;
    [m_Dot.layer removeAllAnimations];
    [m_Panel orderOut:nil];
    [m_Panel close];
    [m_StreamWindow release];
    m_StreamWindow = nil;
}

- (void)stateChanged:(NSNotification*)notification
{
    (void)notification;
    // The geometry may change under a running animation, so jump to where it was heading
    [self finishMessageAnimation];
    [self refresh];
}

- (void)setStatsText:(NSString*)text
{
    if (m_StreamWindow == nil) {
        return;
    }

    m_RightLabel.stringValue = text;
    [self refresh];
}

- (void)setWarning:(NSString*)text
{
    if (m_StreamWindow == nil || text == m_Warning || [text isEqualToString:m_Warning]) {
        return;
    }

    [m_Warning release];
    m_Warning = [text copy];
    [self updateMessage];
}

- (void)showToast:(NSString*)text
{
    if (m_StreamWindow == nil) {
        return;
    }

    [m_Toast release];
    m_Toast = [text copy];
    m_ToastGeneration++;
    [self updateMessage];
}

- (BOOL)isOnScreen
{
    return m_OnScreen.load();
}

- (void)layoutPill:(NSView*)pill label:(NSTextField*)label area:(NSRect)area alignRight:(BOOL)alignRight height:(CGFloat)height y:(CGFloat)y
{
    [label sizeToFit];
    CGFloat maxWidth = MAX(NSWidth(area) - 2 * k_Margin, 0);
    CGFloat width = MIN(NSWidth(label.frame) + 2 * k_Padding, maxWidth);
    CGFloat x = alignRight ? NSMaxX(area) - k_Margin - width : NSMinX(area) + k_Margin;

    pill.frame = NSMakeRect(x, y, width, height);
    setCapsuleShape(pill, height);

    NSView* container = label.superview;
    container.frame = pill.bounds;
    CGFloat labelHeight = NSHeight(label.frame);
    label.frame = NSMakeRect(k_Padding, (height - labelHeight) / 2, MAX(width - 2 * k_Padding, 0), labelHeight);
}

// Shows the bar while the stream window is fullscreen on the active Space of a display with a notch
- (void)refresh
{
    NSScreen* screen = m_StreamWindow.screen;
    CGFloat inset = 0;
    NSRect leftArea = NSZeroRect;
    NSRect rightArea = NSZeroRect;
    if (@available(macOS 12.0, *)) {
        if (screen != nil) {
            inset = screen.safeAreaInsets.top;
            leftArea = screen.auxiliaryTopLeftArea;
            rightArea = screen.auxiliaryTopRightArea;
        }
    }

    BOOL show = m_StreamWindow != nil && screen != nil && inset > 0 && m_StreamWindow.isVisible &&
                (m_StreamWindow.styleMask & NSWindowStyleMaskFullScreen) != 0 &&
                !m_StreamWindow.isMiniaturized && m_StreamWindow.isOnActiveSpace &&
                !NSIsEmptyRect(leftArea) && !NSIsEmptyRect(rightArea);
    m_OnScreen = show;
    if (!show) {
        // A clipboard message that hasn't appeared yet would be stale by the time the bar is back
        if (m_MessageState == ForkMessageHidden && m_Toast != nil) {
            [m_Toast release];
            m_Toast = nil;
        }
        [m_Panel orderOut:nil];
        return;
    }

    NSRect screenFrame = screen.frame;
    NSRect strip = NSMakeRect(NSMinX(screenFrame), NSMaxY(screenFrame) - inset, NSWidth(screenFrame), inset);
    [m_Panel setFrame:strip display:NO];

    // Left pill at the left screen edge, right pill at the right edge, each kept to its side of the notch
    m_PillHeight = MAX(inset - 8, 16);
    m_PillY = (inset - m_PillHeight) / 2;
    m_LeftArea = NSOffsetRect(leftArea, -NSMinX(strip), 0);
    m_HasGeometry = YES;
    [self layoutPill:m_LeftPill label:m_LeftLabel area:m_LeftArea
          alignRight:NO height:m_PillHeight y:m_PillY];
    [self layoutPill:m_RightPill label:m_RightLabel area:NSOffsetRect(rightArea, -NSMinX(strip), 0)
          alignRight:YES height:m_PillHeight y:m_PillY];
    [self layoutMessage];

    [m_Panel orderFrontRegardless];

    // Shows a message that arrived while the bar was hidden, like a connection warning that's still on
    [self updateMessage];
}

// Message pill

- (NSString*)currentMessage
{
    return m_Toast != nil ? m_Toast : m_Warning;
}

- (BOOL)pillShowsCurrentMessage
{
    NSString* message = [self currentMessage];
    return message != nil && m_ShowsWarning == (m_Toast == nil) && [message isEqualToString:m_MessageLabel.stringValue];
}

// Puts the current message in the pill: the clipboard message if there is one, else the warning
- (void)applyMessageContent
{
    BOOL warning = m_Toast == nil;
    NSString* message = [self currentMessage];
    m_MessageLabel.stringValue = message != nil ? message : @"";
    m_MessageIcon.image = symbolImage(warning ? @"wifi.exclamationmark" : @"doc.on.clipboard");
    m_MessageIcon.contentTintColor = warning ? NSColor.systemYellowColor : NSColor.labelColor;
    [m_MessageIcon setFrameSize:m_MessageIcon.image != nil ? m_MessageIcon.image.size : NSZeroSize];
    m_ShowsWarning = warning;
}

// The pill hugs the notch and grows away from it, up to the whole area left of the notch
- (NSRect)messageFrame
{
    [m_MessageLabel sizeToFit];
    CGFloat iconWidth = NSWidth(m_MessageIcon.frame);
    CGFloat width = k_Padding + (iconWidth > 0 ? iconWidth + k_IconGap : 0) + NSWidth(m_MessageLabel.frame) + k_Padding;
    width = MAX(MIN(width, NSWidth(m_LeftArea) - 2 * k_Margin), m_PillHeight);
    return NSMakeRect(NSMaxX(m_LeftArea) - k_Margin - width, m_PillY, width, m_PillHeight);
}

// The circle the pill grows out of and shrinks back into
- (NSRect)collapsedFrame
{
    return NSMakeRect(NSMaxX(m_LeftArea) - k_Margin - m_PillHeight, m_PillY, m_PillHeight, m_PillHeight);
}

- (BOOL)titleFitsBesideMessageWidth:(CGFloat)width
{
    return NSWidth(m_LeftPill.frame) + k_TitleGap + width <= NSWidth(m_LeftArea) - 2 * k_Margin;
}

// Lays out the icon and text for the pill's final size. They're hidden whenever the size animates.
- (void)layoutMessageContentForFrame:(NSRect)frame
{
    CGFloat width = NSWidth(frame);
    CGFloat height = NSHeight(frame);
    m_MessageLabel.superview.frame = NSMakeRect(0, 0, width, height);

    NSSize iconSize = m_MessageIcon.frame.size;
    CGFloat x = k_Padding;
    [m_MessageIcon setFrameOrigin:NSMakePoint(x, (height - iconSize.height) / 2)];
    if (iconSize.width > 0) {
        x += iconSize.width + k_IconGap;
    }

    CGFloat labelHeight = NSHeight(m_MessageLabel.frame);
    m_MessageLabel.frame = NSMakeRect(x, (height - labelHeight) / 2, MAX(width - x - k_Padding, 0), labelHeight);
}

// Keeps the pill in place between animations; the animations place it themselves
- (void)layoutMessage
{
    if (m_MessageState == ForkMessageShown) {
        NSRect frame = [self messageFrame];
        m_MessagePill.frame = frame;
        setCapsuleShape(m_MessagePill, m_PillHeight);
        [self layoutMessageContentForFrame:frame];
        m_LeftPill.alphaValue = [self titleFitsBesideMessageWidth:NSWidth(frame)] ? 1 : 0;
    }
    else if (m_MessageState == ForkMessageHidden) {
        m_LeftPill.alphaValue = 1;
    }
}

// Starts showing, changing or hiding the pill to match the current message
- (void)updateMessage
{
    if (m_StreamWindow == nil) {
        return;
    }

    NSString* message = [self currentMessage];
    switch (m_MessageState) {
    case ForkMessageHidden:
        if (message != nil && m_OnScreen && m_HasGeometry) {
            [self appear];
        }
        break;
    case ForkMessageShown:
        if (message == nil) {
            [self collapse];
        }
        else if (![self pillShowsCurrentMessage]) {
            [self change];
        }
        else if (m_Toast != nil) {
            // The clipboard message is on screen, so its time starts now
            [self startToastTimer];
        }
        break;
    default:
        // Every animation checks the message again when it ends
        break;
    }
}

- (void)startToastTimer
{
    if (m_ToastTimerGeneration == m_ToastGeneration) {
        return;
    }
    unsigned generation = m_ToastTimerGeneration = m_ToastGeneration;

    [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, k_ToastDurationNs), dispatch_get_main_queue(), ^{
        if (generation == m_ToastGeneration && m_StreamWindow != nil) {
            [m_Toast release];
            m_Toast = nil;
            [self updateMessage];
        }
        [self release];
    });
}

// A red dot blinks beside the notch, then grows into the pill
- (void)appear
{
    unsigned generation = ++m_AnimationGeneration;

    NSRect circle = [self collapsedFrame];
    m_MessagePill.frame = circle;
    setCapsuleShape(m_MessagePill, m_PillHeight);
    m_MessagePill.alphaValue = 0;
    m_MessageIcon.alphaValue = 0;
    m_MessageLabel.alphaValue = 0;

    if (reduceMotion()) {
        [self expandWithGeneration:generation];
        return;
    }

    m_MessageState = ForkMessageBlinking;
    m_Dot.frame = NSMakeRect(NSMidX(circle) - k_DotSize / 2, NSMidY(circle) - k_DotSize / 2, k_DotSize, k_DotSize);
    setLayerOpacity(m_Dot.layer, 1, 0);
    m_Dot.hidden = NO;

    CAKeyframeAnimation* blink = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    blink.values = @[ @0.0, @1.0, @0.2, @1.0, @0.2, @1.0 ];
    blink.duration = 0.8;

    [self retain];
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        if (generation == m_AnimationGeneration && m_StreamWindow != nil) {
            [self expandWithGeneration:generation];
        }
        [self release];
    }];
    [m_Dot.layer addAnimation:blink forKey:@"blink"];
    [CATransaction commit];
}

- (void)expandWithGeneration:(unsigned)generation
{
    // The message may have ended while the dot blinked
    if ([self currentMessage] == nil) {
        [self enterHidden];
        return;
    }

    m_MessageState = ForkMessageExpanding;
    [self applyMessageContent];
    NSRect target = [self messageFrame];
    [self layoutMessageContentForFrame:target];
    BOOL hideTitle = ![self titleFitsBesideMessageWidth:NSWidth(target)];

    BOOL simple = reduceMotion();
    if (simple) {
        // Just fades in
        m_MessagePill.frame = target;
        m_MessageIcon.alphaValue = 1;
        m_MessageLabel.alphaValue = 1;
    }
    else {
        setLayerOpacity(m_Dot.layer, 0, 0.35);
    }

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.allowsImplicitAnimation = YES;
        if (simple) {
            context.duration = 0.2;
        }
        else {
            context.duration = 0.35;
            // Eases out with a slight overshoot; only x and width change, so the ends stay round
            context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.3 :1.15];
            m_MessagePill.animator.frame = target;
        }
        m_MessagePill.animator.alphaValue = 1;
        if (hideTitle) {
            m_LeftPill.animator.alphaValue = 0;
        }
    } completionHandler:^{
        if (generation == m_AnimationGeneration && m_StreamWindow != nil) {
            [self enterShown];
        }
        [self release];
    }];
}

// Swaps in another message: the text fades out, the pill takes its new width, the new text fades in
- (void)change
{
    unsigned generation = ++m_AnimationGeneration;
    m_MessageState = ForkMessageChanging;

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.1;
        m_MessageIcon.animator.alphaValue = 0;
        m_MessageLabel.animator.alphaValue = 0;
    } completionHandler:^{
        if (generation == m_AnimationGeneration && m_StreamWindow != nil) {
            [self resizeWithGeneration:generation];
        }
        [self release];
    }];
}

- (void)resizeWithGeneration:(unsigned)generation
{
    if ([self currentMessage] == nil) {
        [self collapse];
        return;
    }

    [self applyMessageContent];
    NSRect target = [self messageFrame];
    [self layoutMessageContentForFrame:target];
    BOOL hideTitle = ![self titleFitsBesideMessageWidth:NSWidth(target)];

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.2;
        context.allowsImplicitAnimation = YES;
        m_MessagePill.animator.frame = target;
        m_LeftPill.animator.alphaValue = hideTitle ? 0 : 1;
    } completionHandler:^{
        if (generation == m_AnimationGeneration && m_StreamWindow != nil) {
            [self enterShown];
        }
        [self release];
    }];
}

// The text fades out, then the pill shrinks back into a circle and fades away
- (void)collapse
{
    unsigned generation = ++m_AnimationGeneration;
    m_MessageState = ForkMessageCollapsing;

    if (reduceMotion()) {
        [self shrinkWithGeneration:generation];
        return;
    }

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.12;
        m_MessageIcon.animator.alphaValue = 0;
        m_MessageLabel.animator.alphaValue = 0;
    } completionHandler:^{
        if (generation == m_AnimationGeneration && m_StreamWindow != nil) {
            [self shrinkWithGeneration:generation];
        }
        [self release];
    }];
}

- (void)shrinkWithGeneration:(unsigned)generation
{
    BOOL simple = reduceMotion();
    NSRect circle = [self collapsedFrame];

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.allowsImplicitAnimation = YES;
        if (simple) {
            context.duration = 0.2;
        }
        else {
            context.duration = 0.25;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            m_MessagePill.animator.frame = circle;
        }
        m_MessagePill.animator.alphaValue = 0;
        m_LeftPill.animator.alphaValue = 1;
    } completionHandler:^{
        if (generation == m_AnimationGeneration && m_StreamWindow != nil) {
            [self enterHidden];
        }
        [self release];
    }];
}

- (void)enterShown
{
    m_MessageState = ForkMessageShown;
    m_Dot.hidden = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.15;
        m_MessageIcon.animator.alphaValue = 1;
        m_MessageLabel.animator.alphaValue = 1;
    } completionHandler:nil];

    // The message may have changed or ended during the animation
    [self updateMessage];
}

- (void)enterHidden
{
    m_MessageState = ForkMessageHidden;
    m_Dot.hidden = YES;
    m_MessagePill.alphaValue = 0;
    m_LeftPill.alphaValue = 1;

    // Another message may have arrived during the animation
    [self updateMessage];
}

// Jumps to where a running animation was heading, for when the screen changes under it
- (void)finishMessageAnimation
{
    switch (m_MessageState) {
    case ForkMessageBlinking:
    case ForkMessageExpanding:
    case ForkMessageChanging:
        m_AnimationGeneration++;
        [m_Dot.layer removeAllAnimations];
        m_Dot.hidden = YES;
        if ([self currentMessage] == nil) {
            m_MessageState = ForkMessageHidden;
            m_MessagePill.alphaValue = 0;
            m_LeftPill.alphaValue = 1;
        }
        else {
            [self applyMessageContent];
            m_MessageState = ForkMessageShown;
            m_MessagePill.alphaValue = 1;
            m_MessageIcon.alphaValue = 1;
            m_MessageLabel.alphaValue = 1;
        }
        break;
    case ForkMessageCollapsing:
        m_AnimationGeneration++;
        m_MessageState = ForkMessageHidden;
        m_MessagePill.alphaValue = 0;
        m_LeftPill.alphaValue = 1;
        break;
    default:
        break;
    }
}

@end

namespace
{
    class MacNotchBar : public NotchBar
    {
    public:
        // Takes over the controller's +1 reference
        explicit MacNotchBar(ForkNotchBarController* controller)
            : m_Controller(controller)
        {
            ForkStreamStats::setListener([controller](const ForkStreamStats::Snapshot& stats) {
                // Runs on the decode thread, which has no autorelease pool of its own
                @autoreleasepool {
                    NSString* text = [[NSString alloc] initWithFormat:@"%.0f fps · %u ms · %.1f Mb/s · %@ · %.1f%% loss",
                                                                      stats.fps, stats.rttMs, stats.mbps,
                                                                      stats.codec.toNSString(), stats.dropPercent];
                    [controller retain];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [controller setStatsText:text];
                        [text release];
                        [controller release];
                    });
                }
            });

            ForkStreamStats::setConnectionListener([controller](bool poor, bool suggestLowerBitrate) -> bool {
                // Runs on moonlight-common-c's receive thread
                bool shown = poor && [controller isOnScreen];
                if (poor && !shown) {
                    // Moonlight's status overlay shows it instead
                    return false;
                }

                @autoreleasepool {
                    // Nil clears the warning once the connection is okay again
                    NSString* text = nil;
                    if (shown) {
                        QString message = suggestLowerBitrate ?
                                              QCoreApplication::translate("NotchBar", "Slow connection to PC · reduce your bitrate") :
                                              QCoreApplication::translate("NotchBar", "Poor connection to PC");
                        text = [message.toNSString() retain];
                    }
                    [controller retain];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [controller setWarning:text];
                        [text release];
                        [controller release];
                    });
                }
                return shown;
            });
        }

        ~MacNotchBar() override
        {
            // No listener runs after these return; queued updates hold their own reference
            ForkStreamStats::setListener(nullptr);
            ForkStreamStats::setConnectionListener(nullptr);
            [m_Controller invalidate];
            [m_Controller release];
        }

        bool showToast(const QString& text) override
        {
            if (![m_Controller isOnScreen]) {
                return false;
            }

            @autoreleasepool {
                [m_Controller showToast:text.toNSString()];
            }
            return true;
        }

    private:
        ForkNotchBarController* m_Controller;
    };
}

std::unique_ptr<NotchBar> NotchBar::create(SDL_Window* window, const QString& title)
{
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (window == nullptr || !SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA ||
            info.info.cocoa.window == nil) {
        return nullptr;
    }

    @autoreleasepool {
        ForkNotchBarController* controller = [[ForkNotchBarController alloc] initWithStreamWindow:info.info.cocoa.window
                                                                                             title:title.toNSString()];
        return std::unique_ptr<NotchBar>(new MacNotchBar(controller));
    }
}
