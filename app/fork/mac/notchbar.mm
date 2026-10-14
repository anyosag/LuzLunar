#include "notchbar.h"

#include "fork/streamstats.h"
#include "SDL_compat.h"

#include <SDL_syswm.h>

#import <AppKit/AppKit.h>

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

@interface ForkNotchBarController : NSObject
{
    NSWindow* m_StreamWindow;   // not retained; SDL owns it and it outlives this controller
    ForkNotchPanel* m_Panel;
    NSView* m_LeftPill;
    NSView* m_RightPill;
    NSTextField* m_LeftLabel;
    NSTextField* m_RightLabel;
}
- (instancetype)initWithStreamWindow:(NSWindow*)window title:(NSString*)title;
- (void)setStatsText:(NSString*)text;
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

// A capsule of Liquid Glass (macOS 26) or vibrancy holding the label. Returns a +1 reference.
static NSView* makePill(NSTextField* label)
{
    NSView* container = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [container addSubview:label];

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

- (instancetype)initWithStreamWindow:(NSWindow*)window title:(NSString*)title
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    m_StreamWindow = window;

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
    m_LeftPill = makePill(m_LeftLabel);
    m_RightPill = makePill(m_RightLabel);
    [m_Panel.contentView addSubview:m_LeftPill];
    [m_Panel.contentView addSubview:m_RightPill];

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
    [m_Panel release];
    [m_LeftPill release];
    [m_RightPill release];
    [m_LeftLabel release];
    [m_RightLabel release];
    [super dealloc];
}

- (void)invalidate
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [m_Panel orderOut:nil];
    [m_Panel close];
    m_StreamWindow = nil;
}

- (void)stateChanged:(NSNotification*)notification
{
    (void)notification;
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

- (void)layoutPill:(NSView*)pill label:(NSTextField*)label area:(NSRect)area alignRight:(BOOL)alignRight height:(CGFloat)height y:(CGFloat)y
{
    const CGFloat margin = 10;
    const CGFloat padding = 12;

    [label sizeToFit];
    CGFloat maxWidth = MAX(NSWidth(area) - 2 * margin, 0);
    CGFloat width = MIN(NSWidth(label.frame) + 2 * padding, maxWidth);
    CGFloat x = alignRight ? NSMaxX(area) - margin - width : NSMinX(area) + margin;

    pill.frame = NSMakeRect(x, y, width, height);
    if (@available(macOS 26.0, *)) {
        if ([pill isKindOfClass:NSGlassEffectView.class]) {
            ((NSGlassEffectView*)pill).cornerRadius = height / 2;
        }
    }
    if (pill.layer != nil) {
        pill.layer.cornerRadius = height / 2;
    }

    NSView* container = label.superview;
    container.frame = pill.bounds;
    CGFloat labelHeight = NSHeight(label.frame);
    label.frame = NSMakeRect(padding, (height - labelHeight) / 2, MAX(width - 2 * padding, 0), labelHeight);
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

    BOOL show = m_StreamWindow != nil && screen != nil && inset > 0 &&
                (m_StreamWindow.styleMask & NSWindowStyleMaskFullScreen) != 0 &&
                !m_StreamWindow.isMiniaturized && m_StreamWindow.isOnActiveSpace &&
                !NSIsEmptyRect(leftArea) && !NSIsEmptyRect(rightArea);
    if (!show) {
        [m_Panel orderOut:nil];
        return;
    }

    NSRect screenFrame = screen.frame;
    NSRect strip = NSMakeRect(NSMinX(screenFrame), NSMaxY(screenFrame) - inset, NSWidth(screenFrame), inset);
    [m_Panel setFrame:strip display:NO];

    // Left pill at the left screen edge, right pill at the right edge, each kept to its side of the notch
    CGFloat height = MAX(inset - 8, 16);
    CGFloat y = (inset - height) / 2;
    [self layoutPill:m_LeftPill label:m_LeftLabel area:NSOffsetRect(leftArea, -NSMinX(strip), 0)
          alignRight:NO height:height y:y];
    [self layoutPill:m_RightPill label:m_RightLabel area:NSOffsetRect(rightArea, -NSMinX(strip), 0)
          alignRight:YES height:height y:y];

    [m_Panel orderFrontRegardless];
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
        }

        ~MacNotchBar() override
        {
            // No listener runs after this returns; queued updates hold their own reference
            ForkStreamStats::setListener(nullptr);
            [m_Controller invalidate];
            [m_Controller release];
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
