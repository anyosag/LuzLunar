#include "notchbar.h"
#include "notchmenus_mac.h"

#include "fork/forknetworklink.h"
#include "fork/forkpolicy.h"
#include "fork/streamstats.h"
#include "SDL_compat.h"

#include <atomic>
#include <functional>

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
    const CGFloat k_ItemGap = 2;      // between the items right of the notch
    const int64_t k_ToastDurationNs = 3 * NSEC_PER_SEC;

    // The message pill in the bottom-left corner of a windowed stream
    const CGFloat k_CornerMargin = 16;      // from the window's left and bottom edges
    const CGFloat k_CornerHeight = 30;
    const CGFloat k_CornerMaxWidth = 480;
    const CGFloat k_CornerRise = 6;         // how far it rises as it appears
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

// Messages in the bottom-left corner of a windowed stream, in a pill like the notch bar's. It's in a
// child window of the stream window, so it moves, resizes and changes Spaces with it.
@interface ForkCornerMessage : NSObject
{
    NSWindow* m_StreamWindow;
    ForkNotchPanel* m_Panel;
    NSView* m_Pill;
    NSImageView* m_Icon;
    NSTextField* m_Label;
    NSString* m_Text;           // the message shown or appearing; nil while hidden or hiding
    BOOL m_Warning;
    unsigned m_Generation;      // completion handlers of older animations do nothing
}
- (instancetype)initWithStreamWindow:(NSWindow*)window;
// Shows the message, or another one in its place, or hides it for nil
- (void)showMessage:(NSString*)text warning:(BOOL)warning;
- (void)hideNow;
// Follows the stream window's size
- (void)layout;
- (void)invalidate;
@end

typedef NS_ENUM(NSInteger, ForkMessageState) {
    ForkMessageHidden,
    ForkMessageBlinking,    // the red dot blinks beside the notch
    ForkMessageExpanding,   // the dot grows into the pill
    ForkMessageShown,
    ForkMessageChanging,    // another message replaces the one shown
    ForkMessageCollapsing,  // the pill shrinks away
};

@interface ForkNotchBarController : NSObject <ForkNotchMenusHost>
{
    NSWindow* m_StreamWindow;   // retained: SDL destroys the window before the stream's fork extensions go away
    ForkNotchPanel* m_Panel;
    ForkBarItem* m_SessionItem;     // the app and the PC, left of the notch: the Session menu
    ForkBarItem* m_StatsItem;       // the stream's stats, right of the notch
    ForkBarItem* m_ControlItem;     // Stream Control Center, at the right edge
    NSString* m_AppName;
    NSString* m_HostName;

    // The menus under the items, and what they do (MacNotchBar::setActions())
    ForkNotchMenus* m_Menus;
    std::function<void(NotchMenus::Action)> m_Actions;
    std::function<NotchBar::MenuState()> m_State;
    NSRect m_StripFrame;            // the strip beside the notch on screen, from the last layout

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
    ForkCornerMessage* m_Corner;    // shows the messages instead while the stream is windowed
    BOOL m_BarOnScreen;
    BOOL m_CornerOnScreen;
    BOOL m_CoversScreen;            // the stream window fills its screen without being in a fullscreen Space
    std::atomic<bool> m_ShowsMessages; // the bar or the corner pill is on screen
    BOOL m_FullScreenTransition;    // the stream window is entering or leaving its fullscreen Space
    unsigned m_TransitionGeneration;

    // The area left of the notch and the pill size, in panel coordinates, from the last refresh
    BOOL m_HasGeometry;
    NSRect m_LeftArea;
    CGFloat m_PillHeight;
    CGFloat m_PillY;
}
- (instancetype)initWithStreamWindow:(NSWindow*)window appName:(NSString*)appName hostName:(NSString*)hostName;
- (void)setActions:(std::function<void(NotchMenus::Action)>)actions state:(std::function<NotchBar::MenuState()>)state;
- (BOOL)toggleMenusByKeyboard;
- (BOOL)handleMenuKey:(int)scancode pressed:(BOOL)pressed shift:(BOOL)shift;
- (BOOL)menuOpen;
- (BOOL)barOnScreen;
- (void)refreshMenus;
- (void)setStatsText:(NSString*)text;
- (void)setWarning:(NSString*)text;
- (void)showToast:(NSString*)text;
- (BOOL)showsMessages;
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

// A clear panel for pills that clicks pass through. Returns a +1 reference.
static ForkNotchPanel* makePanel(NSWindowLevel level, NSWindowCollectionBehavior behavior)
{
    ForkNotchPanel* panel = [[ForkNotchPanel alloc] initWithContentRect:NSZeroRect
                                                              styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                                backing:NSBackingStoreBuffered
                                                                  defer:NO];
    panel.releasedWhenClosed = NO;
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.ignoresMouseEvents = YES;
    panel.hidesOnDeactivate = NO;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.level = level;
    panel.collectionBehavior = behavior;
    // Over the black strip beside the notch and over video, light-on-dark like macOS's video controls
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    return panel;
}

// The panel over the strip beside the notch: above the stream window's level, and allowed into its
// fullscreen Space. Its items take clicks; the strip is outside the stream window, so nothing meant
// for the PC lands there. Returns a +1 reference.
static ForkNotchPanel* makeNotchPanel()
{
    ForkNotchPanel* panel = makePanel(NSMainMenuWindowLevel + 2,
                                      NSWindowCollectionBehaviorFullScreenAuxiliary |
                                      NSWindowCollectionBehaviorStationary |
                                      NSWindowCollectionBehaviorIgnoresCycle);
    panel.ignoresMouseEvents = NO;
    panel.acceptsMouseMovedEvents = YES;
    return panel;
}

// The Session item's title: the app, then the PC in the secondary color
static NSAttributedString* sessionTitle(NSString* appName, NSString* hostName)
{
    NSMutableAttributedString* title = [[[NSMutableAttributedString alloc] init] autorelease];
    [title appendAttributedString:[[[NSAttributedString alloc] initWithString:appName
                                                                    attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
                                                                                  NSForegroundColorAttributeName: NSColor.labelColor }] autorelease]];
    if (hostName.length > 0) {
        [title appendAttributedString:[[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:hostName]
                                                                        attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                                                                                      NSForegroundColorAttributeName: NSColor.secondaryLabelColor }] autorelease]];
    }
    return title;
}

static NSAttributedString* statsTitle(NSString* text)
{
    return [[[NSAttributedString alloc] initWithString:text
                                            attributes:@{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium],
                                                          NSForegroundColorAttributeName: NSColor.labelColor }] autorelease];
}

// Puts a message in a pill's icon and label: a yellow warning sign for the connection warning, a
// clipboard for clipboard messages
static void setMessageContent(NSImageView* icon, NSTextField* label, NSString* text, BOOL warning)
{
    label.stringValue = text != nil ? text : @"";
    icon.image = symbolImage(warning ? @"wifi.exclamationmark" : @"doc.on.clipboard");
    icon.contentTintColor = warning ? NSColor.systemYellowColor : NSColor.labelColor;
    [icon setFrameSize:icon.image != nil ? icon.image.size : NSZeroSize];
}

// The width a message pill needs for its icon and text
static CGFloat messageWidth(NSImageView* icon, NSTextField* label)
{
    [label sizeToFit];
    CGFloat iconWidth = NSWidth(icon.frame);
    return k_Padding + (iconWidth > 0 ? iconWidth + k_IconGap : 0) + NSWidth(label.frame) + k_Padding;
}

// Lays out a message's icon and text for a pill of this size
static void layoutMessageContent(NSImageView* icon, NSTextField* label, NSSize size)
{
    label.superview.frame = NSMakeRect(0, 0, size.width, size.height);

    NSSize iconSize = icon.frame.size;
    CGFloat x = k_Padding;
    [icon setFrameOrigin:NSMakePoint(x, (size.height - iconSize.height) / 2)];
    if (iconSize.width > 0) {
        x += iconSize.width + k_IconGap;
    }

    CGFloat labelHeight = NSHeight(label.frame);
    label.frame = NSMakeRect(x, (size.height - labelHeight) / 2, MAX(size.width - x - k_Padding, 0), labelHeight);
}

static NSString* connectionWarningText(bool suggestLowerBitrate)
{
    QString message = suggestLowerBitrate ?
                          QCoreApplication::translate("NotchBar", "Slow connection to PC · reduce your bitrate") :
                          QCoreApplication::translate("NotchBar", "Poor connection to PC");
    return message.toNSString();
}

- (instancetype)initWithStreamWindow:(NSWindow*)window appName:(NSString*)appName hostName:(NSString*)hostName
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    m_StreamWindow = [window retain];
    m_Panel = makeNotchPanel();
    m_Corner = [[ForkCornerMessage alloc] initWithStreamWindow:window];
    m_AppName = [appName copy];
    m_HostName = [hostName copy];

    m_SessionItem = [[ForkBarItem alloc] initWithSymbol:@"moon"];
    [m_SessionItem setTitle:sessionTitle(appName, hostName)];
    [m_SessionItem setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Session menu: %1 on %2")
                                             .arg(QString::fromNSString(appName), QString::fromNSString(hostName)).toNSString()];
    m_StatsItem = [[ForkBarItem alloc] initWithSymbol:nil];
    m_StatsItem.interactive = NO;
    [m_StatsItem setTitle:statsTitle(@"—")];
    // Control Center's own icon, or sliders on a macOS without it
    m_ControlItem = [[ForkBarItem alloc] initWithSymbol:symbolImage(@"switch.2") != nil ? @"switch.2" : @"slider.horizontal.3"];
    [m_ControlItem setTitle:[[[NSAttributedString alloc] initWithString:@""] autorelease]];
    [m_ControlItem setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Control Center").toNSString()];
    m_Menus = [[ForkNotchMenus alloc] initWithHost:self appName:appName hostName:hostName];
    // Not retained by the blocks' captures beyond the items' life: the items go in dealloc
    __block ForkNotchBarController* controller = self;
    m_SessionItem.onPress = ^{
        [controller pressedItemForMenu:NotchMenus::Menu::Session];
    };
    m_ControlItem.onPress = ^{
        [controller pressedItemForMenu:NotchMenus::Menu::ControlCenter];
    };

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
    m_ShowsMessages = false;

    [m_Panel.contentView addSubview:m_SessionItem];
    [m_Panel.contentView addSubview:m_StatsItem];
    [m_Panel.contentView addSubview:m_ControlItem];
    // The dot sits under the pill that grows out of it
    [m_Panel.contentView addSubview:m_Dot];
    [m_Panel.contentView addSubview:m_MessagePill];

    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[ NSWindowWillEnterFullScreenNotification,
                                       NSWindowWillExitFullScreenNotification ]) {
        [center addObserver:self selector:@selector(fullScreenTransitionStarted:) name:name object:m_StreamWindow];
    }
    for (NSNotificationName name in @[ NSWindowDidEnterFullScreenNotification,
                                       NSWindowDidExitFullScreenNotification ]) {
        [center addObserver:self selector:@selector(fullScreenTransitionEnded:) name:name object:m_StreamWindow];
    }
    for (NSNotificationName name in @[ NSWindowDidMiniaturizeNotification,
                                       NSWindowDidDeminiaturizeNotification,
                                       NSWindowDidChangeScreenNotification ]) {
        [center addObserver:self selector:@selector(stateChanged:) name:name object:m_StreamWindow];
    }
    for (NSNotificationName name in @[ NSWindowDidResizeNotification,
                                       NSWindowDidMoveNotification ]) {
        [center addObserver:self selector:@selector(streamWindowFrameChanged:) name:name object:m_StreamWindow];
    }
    [center addObserver:self selector:@selector(stateChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    // Another app came forward (Command-Tab, a notification's click): its clicks don't reach the
    // menus' click monitor, so a menu would stay open over it
    [center addObserver:self selector:@selector(applicationResignedActive:) name:NSApplicationDidResignActiveNotification object:nil];
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
    [m_SessionItem release];
    [m_StatsItem release];
    [m_ControlItem release];
    [m_AppName release];
    [m_HostName release];
    [m_Menus release];
    [m_MessagePill release];
    [m_MessageIcon release];
    [m_MessageLabel release];
    [m_Dot release];
    [m_Warning release];
    [m_Toast release];
    [m_Corner release];
    [super dealloc];
}

- (void)invalidate
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    // Quietly: the stream is ending, and its event loop with it
    m_Actions = nullptr;
    [m_Menus invalidate];
    m_SessionItem.onPress = nil;
    m_ControlItem.onPress = nil;
    // Animations and timers still queued find the controller invalidated and do nothing
    m_AnimationGeneration++;
    m_ShowsMessages = false;
    [m_Corner invalidate];
    [m_Dot.layer removeAllAnimations];
    [m_Panel orderOut:nil];
    [m_Panel close];
    [m_StreamWindow release];
    m_StreamWindow = nil;
}

- (void)stateChanged:(NSNotification*)notification
{
    (void)notification;
    // A menu would hang from where the bar was
    [m_Menus close];
    // The geometry may change under a running animation, so jump to where it was heading
    [self finishMessageAnimation];
    [self refresh];
}

- (void)applicationResignedActive:(NSNotification*)notification
{
    (void)notification;
    [m_Menus close];
}

- (void)streamWindowFrameChanged:(NSNotification*)notification
{
    (void)notification;
    [m_Corner layout];

    // Fullscreen without a Space sends only resize and move notifications
    if ([self windowCoversScreen] != m_CoversScreen) {
        [self refresh];
    }
}

// SDL's borderless fullscreen (used when a stream isn't in a fullscreen Space) is a plain window
// the size of the screen, with no fullscreen style. Neither the bar nor the corner pill fits there:
// the video is under the notch, and a corner pill would sit over it.
- (BOOL)windowCoversScreen
{
    NSScreen* screen = m_StreamWindow.screen;
    if (screen == nil || (m_StreamWindow.styleMask & NSWindowStyleMaskFullScreen) != 0) {
        return NO;
    }

    NSRect frame = m_StreamWindow.frame;
    NSRect screenFrame = screen.frame;
    return ForkPolicy::coversScreen({ NSMinX(frame), NSMinY(frame), NSWidth(frame), NSHeight(frame) },
                                    { NSMinX(screenFrame), NSMinY(screenFrame), NSWidth(screenFrame), NSHeight(screenFrame) },
                                    (m_StreamWindow.styleMask & NSWindowStyleMaskTitled) != 0);
}

// Moves the pills to a new panel in the same place
- (void)replacePanel
{
    ForkNotchPanel* panel = makeNotchPanel();
    [panel setFrame:m_Panel.frame display:NO];
    // In their order in the old panel, so the dot stays under the message pill
    for (NSView* view in @[ m_SessionItem, m_StatsItem, m_ControlItem, m_Dot, m_MessagePill ]) {
        [panel.contentView addSubview:view];
    }

    [m_Panel orderOut:nil];
    [m_Panel close];
    [m_Panel release];
    m_Panel = panel;
}

// The bar stays hidden while the stream window moves between Spaces (see refresh)
- (void)fullScreenTransitionStarted:(NSNotification*)notification
{
    m_FullScreenTransition = YES;
    unsigned generation = ++m_TransitionGeneration;
    [self stateChanged:notification];

    // AppKit has no notification for a transition that fails, so don't wait for one forever
    [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == m_TransitionGeneration && m_StreamWindow != nil) {
            m_FullScreenTransition = NO;
            [self refresh];
        }
        [self release];
    });
}

- (void)fullScreenTransitionEnded:(NSNotification*)notification
{
    m_FullScreenTransition = NO;
    m_TransitionGeneration++;
    [self stateChanged:notification];
}

// A poor connection warning follows the messages: in the bar or the corner pill while one is on
// screen, in Moonlight's status overlay otherwise. The connection listener only hears about changes,
// so this moves a warning that's already up when they come or go.
- (void)takeConnectionWarning:(BOOL)take
{
    if (take) {
        bool suggestLowerBitrate;
        bool poor = ForkStreamStats::connectionPoor(&suggestLowerBitrate);
        [self setWarning:poor ? connectionWarningText(suggestLowerBitrate) : nil];
    }
    ForkStreamStats::setConnectionWarningInOverlay(!take);
}

- (void)setStatsText:(NSString*)text
{
    if (m_StreamWindow == nil) {
        return;
    }

    [m_StatsItem setTitle:statsTitle(text)];
    [m_StatsItem setAccessibilityLabel:text];
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

- (BOOL)showsMessages
{
    return m_ShowsMessages.load();
}

// Menus

- (void)setActions:(std::function<void(NotchMenus::Action)>)actions state:(std::function<NotchBar::MenuState()>)state
{
    m_Actions = std::move(actions);
    m_State = std::move(state);
    if (m_BarOnScreen && m_Actions) {
        // Already up: the pointer mustn't be held to the picture
        m_Actions(NotchMenus::Action::BarShownOrHidden);
    }
}

- (BOOL)barOnScreen
{
    return m_BarOnScreen;
}

- (void)pressedItemForMenu:(NotchMenus::Menu)menu
{
    if (m_StreamWindow == nil) {
        return;
    }
    if ([m_Menus openMenu] == menu) {
        [m_Menus close];
    }
    else {
        [m_Menus open:menu keyboard:NO];
    }
}

- (BOOL)toggleMenusByKeyboard
{
    if (m_StreamWindow == nil || !m_BarOnScreen) {
        return NO;
    }
    if ([m_Menus openMenu] != NotchMenus::Menu::None) {
        [m_Menus close];
    }
    else {
        [m_Menus open:NotchMenus::Menu::Session keyboard:YES];
    }
    return YES;
}

- (BOOL)handleMenuKey:(int)scancode pressed:(BOOL)pressed shift:(BOOL)shift
{
    return [m_Menus handleKey:scancode pressed:pressed shift:shift];
}

- (BOOL)menuOpen
{
    return [m_Menus openMenu] != NotchMenus::Menu::None;
}

- (void)refreshMenus
{
    [m_Menus refresh];
}

- (void)menusPerform:(NotchMenus::Action)action
{
    if (m_Actions) {
        m_Actions(action);
    }
}

- (NotchBar::MenuState)menusState
{
    return m_State ? m_State() : NotchBar::MenuState();
}

- (NSRect)menusAnchorFor:(NotchMenus::Menu)menu alignRight:(BOOL*)alignRight
{
    ForkBarItem* item = menu == NotchMenus::Menu::Session ? m_SessionItem :
                        menu == NotchMenus::Menu::ControlCenter ? m_ControlItem : nil;
    if (item == nil || item.hidden || !m_BarOnScreen) {
        return NSZeroRect;
    }
    *alignRight = item == m_ControlItem;
    // The item's left and right edges, and the bottom of the strip, so the menu hangs below the bar
    NSRect frame = [m_Panel convertRectToScreen:[item convertRect:item.bounds toView:nil]];
    return NSMakeRect(NSMinX(frame), NSMinY(m_StripFrame), NSWidth(frame), NSHeight(m_StripFrame));
}

- (void)menusChanged:(NotchMenus::Menu)menu
{
    BOOL wasOpen = m_SessionItem.open || m_ControlItem.open;
    m_SessionItem.open = menu == NotchMenus::Menu::Session;
    m_ControlItem.open = menu == NotchMenus::Menu::ControlCenter;
    BOOL isOpen = menu != NotchMenus::Menu::None;
    if (isOpen != wasOpen && m_Actions) {
        m_Actions(isOpen ? NotchMenus::Action::MenusOpened : NotchMenus::Action::MenusClosed);
    }
}

- (NSWindow*)menusBarWindow
{
    return m_Panel;
}

// The Session item at the left edge of the area left of the notch; the stats and Control Center
// from the right edge of the area right of it, the stats giving way when they don't fit
- (void)layoutItemsLeft:(NSRect)leftArea right:(NSRect)rightArea height:(CGFloat)height y:(CGFloat)y
{
    CGFloat sessionWidth = MIN([m_SessionItem naturalWidth], MAX(NSWidth(leftArea) - 2 * k_Margin, 0));
    m_SessionItem.frame = NSMakeRect(NSMinX(leftArea) + k_Margin, y, sessionWidth, height);
    m_SessionItem.hidden = sessionWidth <= 0;

    std::vector<NotchMenus::Placed> placed = NotchMenus::layoutRight(NSWidth(rightArea), k_Margin, k_ItemGap,
                                                                     { [m_StatsItem naturalWidth], [m_ControlItem naturalWidth] }, 0);
    NSArray<ForkBarItem*>* items = @[ m_StatsItem, m_ControlItem ];
    for (NSUInteger i = 0; i < items.count; i++) {
        ForkBarItem* item = items[i];
        item.hidden = placed[i].width <= 0;
        item.frame = NSMakeRect(NSMinX(rightArea) + placed[i].x, y, placed[i].width, height);
    }
}

// Shows the bar while the stream window is fullscreen on the active Space of a display with a notch,
// and the messages in the corner pill while it's windowed on the active Space (not while it covers the screen)
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

    // Not during a fullscreen transition, while the window still counts as on the Space it's leaving,
    // so neither shows over that Space
    BOOL visible = !m_FullScreenTransition && m_StreamWindow != nil && m_StreamWindow.isVisible &&
                   !m_StreamWindow.isMiniaturized && m_StreamWindow.isOnActiveSpace;
    BOOL fullScreen = (m_StreamWindow.styleMask & NSWindowStyleMaskFullScreen) != 0;
    BOOL show = visible && fullScreen && screen != nil && inset > 0 &&
                !NSIsEmptyRect(leftArea) && !NSIsEmptyRect(rightArea);
    BOOL covers = [self windowCoversScreen];
    BOOL corner = visible && !fullScreen && !covers;
    if (covers != m_CoversScreen) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, covers ? "[fork] Stream window covers the screen" : "[fork] Stream window no longer covers the screen");
    }
    m_CoversScreen = covers;
    BOOL barChanged = show != m_BarOnScreen;
    if (barChanged) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, show ? "[fork] Notch bar shown" : "[fork] Notch bar hidden");
    }
    if (corner != m_CornerOnScreen) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, corner ? "[fork] Messages in the window's corner" : "[fork] Messages no longer in the window's corner");
    }
    m_BarOnScreen = show;
    m_CornerOnScreen = corner;

    BOOL showsMessages = show || corner;
    BOOL changed = showsMessages != m_ShowsMessages.load();
    m_ShowsMessages = showsMessages;

    if (!corner) {
        [m_Corner hideNow];
    }

    if (!show) {
        // Nothing for a menu to hang from
        [m_Menus close];
        // A clipboard message that hasn't appeared yet would be stale by the time it could
        if (!showsMessages && m_MessageState == ForkMessageHidden && m_Toast != nil) {
            [m_Toast release];
            m_Toast = nil;
        }
        [m_Panel orderOut:nil];
    }
    else {
        [self layoutBarOnScreen:screen inset:inset leftArea:leftArea rightArea:rightArea];
    }

    if (changed) {
        [self takeConnectionWarning:showsMessages];
    }

    // The pointer is held to the picture only while there's no bar above it to reach
    if (barChanged && m_Actions) {
        m_Actions(NotchMenus::Action::BarShownOrHidden);
    }

    // Shows a message that arrived while neither was on screen, or moves one between them
    [self updateMessage];
}

- (void)layoutBarOnScreen:(NSScreen*)screen inset:(CGFloat)inset leftArea:(NSRect)leftArea rightArea:(NSRect)rightArea
{
    NSRect screenFrame = screen.frame;
    NSRect strip = NSMakeRect(NSMinX(screenFrame), NSMaxY(screenFrame) - inset, NSWidth(screenFrame), inset);
    [m_Panel setFrame:strip display:NO];

    // Items at the left and right screen edges, each kept to its side of the notch
    m_PillHeight = MAX(inset - 8, 16);
    m_PillY = (inset - m_PillHeight) / 2;
    m_LeftArea = NSOffsetRect(leftArea, -NSMinX(strip), 0);
    m_HasGeometry = YES;
    m_StripFrame = strip;
    [self layoutItemsLeft:m_LeftArea right:NSOffsetRect(rightArea, -NSMinX(strip), 0) height:m_PillHeight y:m_PillY];
    [self layoutMessage];

    [m_Panel orderFrontRegardless];
    if (!m_Panel.isOnActiveSpace) {
        // Once its first fullscreen Space is gone, the panel belongs to the desktop's Space and goes
        // back there whenever it's ordered in. A new panel joins the active Space, beside the stream.
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Notch bar moved to a new panel on the stream's Space");
        [self replacePanel];
        [m_Panel orderFrontRegardless];
    }
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
    setMessageContent(m_MessageIcon, m_MessageLabel, [self currentMessage], warning);
    m_ShowsWarning = warning;
}

// The pill hugs the notch and grows away from it, up to the whole area left of the notch
- (NSRect)messageFrame
{
    CGFloat width = messageWidth(m_MessageIcon, m_MessageLabel);
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
    return NSWidth(m_SessionItem.frame) + k_TitleGap + width <= NSWidth(m_LeftArea) - 2 * k_Margin;
}

// Lays out the icon and text for the pill's final size. They're hidden whenever the size animates.
- (void)layoutMessageContentForFrame:(NSRect)frame
{
    layoutMessageContent(m_MessageIcon, m_MessageLabel, frame.size);
}

// Keeps the pill in place between animations; the animations place it themselves
- (void)layoutMessage
{
    if (m_MessageState == ForkMessageShown) {
        NSRect frame = [self messageFrame];
        m_MessagePill.frame = frame;
        setCapsuleShape(m_MessagePill, m_PillHeight);
        [self layoutMessageContentForFrame:frame];
        m_SessionItem.alphaValue = [self titleFitsBesideMessageWidth:NSWidth(frame)] ? 1 : 0;
    }
    else if (m_MessageState == ForkMessageHidden) {
        m_SessionItem.alphaValue = 1;
    }
}

// Starts showing, changing or hiding the pill to match the current message
- (void)updateMessage
{
    if (m_StreamWindow == nil) {
        return;
    }

    NSString* message = [self currentMessage];

    // While the stream is windowed, the corner pill shows the message instead of the bar
    if (m_CornerOnScreen) {
        [m_Corner showMessage:message warning:m_Toast == nil];
        if (m_Toast != nil) {
            // The clipboard message is on screen, so its time starts now
            [self startToastTimer];
        }
    }

    switch (m_MessageState) {
    case ForkMessageHidden:
        if (message != nil && m_BarOnScreen && m_HasGeometry) {
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
            m_SessionItem.animator.alphaValue = 0;
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
        m_SessionItem.animator.alphaValue = hideTitle ? 0 : 1;
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
        m_SessionItem.animator.alphaValue = 1;
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
    m_SessionItem.alphaValue = 1;

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
            m_SessionItem.alphaValue = 1;
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
        m_SessionItem.alphaValue = 1;
        break;
    default:
        break;
    }
}

@end

@implementation ForkCornerMessage

- (instancetype)initWithStreamWindow:(NSWindow*)window
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    m_StreamWindow = [window retain];
    // As the stream window's child it stays just above it
    m_Panel = makePanel(NSNormalWindowLevel, NSWindowCollectionBehaviorIgnoresCycle);

    m_Label = makeLabel(@"");
    m_Icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    m_Icon.imageScaling = NSImageScaleNone;
    m_Pill = makePill(@[ m_Icon, m_Label ]);
    m_Pill.alphaValue = 0;
    [m_Panel.contentView addSubview:m_Pill];
    return self;
}

- (void)dealloc
{
    [m_StreamWindow release];
    [m_Panel release];
    [m_Pill release];
    [m_Icon release];
    [m_Label release];
    [m_Text release];
    [super dealloc];
}

- (void)invalidate
{
    [self hideNow];
    [m_Panel close];
    [m_StreamWindow release];
    m_StreamWindow = nil;
}

// The panel spans the widest pill the window has room for, plus the distance the pill rises
- (void)layoutPanel
{
    NSRect window = m_StreamWindow.frame;
    CGFloat width = MAX(MIN(NSWidth(window) - 2 * k_CornerMargin, k_CornerMaxWidth), k_CornerHeight);
    [m_Panel setFrame:NSMakeRect(NSMinX(window) + k_CornerMargin, NSMinY(window) + k_CornerMargin - k_CornerRise,
                                 width, k_CornerHeight + k_CornerRise)
              display:NO];
}

// Where the pill rests, sized for its message
- (NSRect)pillFrame
{
    CGFloat width = MAX(MIN(messageWidth(m_Icon, m_Label), NSWidth(m_Panel.frame)), k_CornerHeight);
    return NSMakeRect(0, k_CornerRise, width, k_CornerHeight);
}

- (void)showMessage:(NSString*)text warning:(BOOL)warning
{
    if (m_StreamWindow == nil) {
        return;
    }
    if (text == nil) {
        [self hide];
        return;
    }
    if (m_Text != nil && warning == m_Warning && [text isEqualToString:m_Text]) {
        return;
    }

    BOOL replacing = m_Text != nil;
    [m_Text release];
    m_Text = [text copy];
    m_Warning = warning;
    if (replacing) {
        [self change];
    }
    else {
        [self appear];
    }
}

// Fades in while rising into place, like macOS's HUDs. With Reduce Motion it only fades.
- (void)appear
{
    ++m_Generation;

    setMessageContent(m_Icon, m_Label, m_Text, m_Warning);
    m_Icon.alphaValue = 1;
    m_Label.alphaValue = 1;
    [self layoutPanel];
    NSRect target = [self pillFrame];
    layoutMessageContent(m_Icon, m_Label, target.size);

    BOOL simple = reduceMotion();
    // A pill still fading out comes back from where it is
    if (m_Pill.alphaValue == 0) {
        m_Pill.frame = simple ? target : NSOffsetRect(target, 0, -k_CornerRise);
    }
    setCapsuleShape(m_Pill, k_CornerHeight);
    if (m_Panel.parentWindow == nil) {
        [m_StreamWindow addChildWindow:m_Panel ordered:NSWindowAbove];
    }

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.allowsImplicitAnimation = YES;
        context.duration = simple ? 0.2 : 0.3;
        context.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.2 :0.9 :0.3 :1];
        m_Pill.animator.alphaValue = 1;
        m_Pill.animator.frame = target;
    } completionHandler:^{
        [self release];
    }];
}

// Swaps in another message: the text fades out, the pill takes its new width, the new text fades in
- (void)change
{
    unsigned generation = ++m_Generation;

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.1;
        m_Icon.animator.alphaValue = 0;
        m_Label.animator.alphaValue = 0;
    } completionHandler:^{
        if (generation == m_Generation && m_StreamWindow != nil) {
            [self resizeWithGeneration:generation];
        }
        [self release];
    }];
}

- (void)resizeWithGeneration:(unsigned)generation
{
    setMessageContent(m_Icon, m_Label, m_Text, m_Warning);
    NSRect target = [self pillFrame];
    layoutMessageContent(m_Icon, m_Label, target.size);

    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.duration = 0.2;
        context.allowsImplicitAnimation = YES;
        m_Pill.animator.frame = target;
        m_Pill.animator.alphaValue = 1;
    } completionHandler:^{
        if (generation == m_Generation && m_StreamWindow != nil) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
                context.duration = 0.12;
                m_Icon.animator.alphaValue = 1;
                m_Label.animator.alphaValue = 1;
            } completionHandler:nil];
        }
        [self release];
    }];
}

// Fades out while sinking back a little, then leaves the stream window
- (void)hide
{
    if (m_Text == nil) {
        return;
    }
    [m_Text release];
    m_Text = nil;
    unsigned generation = ++m_Generation;

    BOOL simple = reduceMotion();
    NSRect from = m_Pill.frame;
    [self retain];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
        context.allowsImplicitAnimation = YES;
        context.duration = 0.2;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
        m_Pill.animator.alphaValue = 0;
        if (!simple) {
            m_Pill.animator.frame = NSMakeRect(NSMinX(from), 0, NSWidth(from), NSHeight(from));
        }
    } completionHandler:^{
        if (generation == m_Generation && m_StreamWindow != nil) {
            [self leaveStreamWindow];
        }
        [self release];
    }];
}

- (void)hideNow
{
    if (m_Text == nil && m_Panel.parentWindow == nil) {
        return;
    }

    ++m_Generation;
    [m_Text release];
    m_Text = nil;
    m_Pill.alphaValue = 0;
    [self leaveStreamWindow];
}

- (void)leaveStreamWindow
{
    if (m_Panel.parentWindow != nil) {
        [m_Panel.parentWindow removeChildWindow:m_Panel];
    }
    [m_Panel orderOut:nil];
}

- (void)layout
{
    if (m_StreamWindow == nil || m_Text == nil) {
        return;
    }

    [self layoutPanel];
    NSRect target = [self pillFrame];
    m_Pill.frame = target;
    layoutMessageContent(m_Icon, m_Label, target.size);
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
                    // First the connection the stream uses, like "Ethernet 1 Gb/s", where it's shown
                    QString link = ForkNetworkLink::badge();
                    // While adaptive bitrate holds the stream lower, its cap follows the bitrate: "18.3 Mb/s ↓20"
                    NSString* cap = stats.bitrateCapMbps > 0 ? [NSString stringWithFormat:@" ↓%.0f", stats.bitrateCapMbps] : @"";
                    NSString* text = [[NSString alloc] initWithFormat:@"%@%.0f fps · %u ms · %.1f Mb/s%@ · %@ · %.1f%% loss",
                                                                      link.isEmpty() ? @"" : [link.toNSString() stringByAppendingString:@" · "],
                                                                      stats.fps, stats.rttMs, stats.mbps, cap,
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
                bool shown = poor && [controller showsMessages];
                if (poor && !shown) {
                    // Moonlight's status overlay shows it instead
                    return false;
                }

                @autoreleasepool {
                    // Nil clears the warning once the connection is okay again
                    NSString* text = shown ? [connectionWarningText(suggestLowerBitrate) retain] : nil;
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
            @autoreleasepool {
                [m_Controller invalidate];
                [m_Controller release];
            }
        }

        bool showToast(const QString& text) override
        {
            if (![m_Controller showsMessages]) {
                return false;
            }

            @autoreleasepool {
                [m_Controller showToast:text.toNSString()];
            }
            return true;
        }

        void setActions(std::function<void(NotchMenus::Action)> actions, std::function<MenuState()> state) override
        {
            [m_Controller setActions:std::move(actions) state:std::move(state)];
        }

        bool toggleMenus() override
        {
            @autoreleasepool {
                return [m_Controller toggleMenusByKeyboard];
            }
        }

        bool handleMenuKey(int scancode, bool pressed, bool shift) override
        {
            @autoreleasepool {
                return [m_Controller handleMenuKey:scancode pressed:pressed shift:shift];
            }
        }

        bool menuOpen() const override
        {
            return [m_Controller menuOpen];
        }

        bool onScreen() const override
        {
            return [m_Controller barOnScreen];
        }

        void refreshMenus() override
        {
            @autoreleasepool {
                [m_Controller refreshMenus];
            }
        }

    private:
        ForkNotchBarController* m_Controller;
    };
}

std::unique_ptr<NotchBar> NotchBar::create(SDL_Window* window, const QString& appName, const QString& hostName)
{
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (window == nullptr || !SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA ||
            info.info.cocoa.window == nil) {
        return nullptr;
    }

    @autoreleasepool {
        ForkNotchBarController* controller = [[ForkNotchBarController alloc] initWithStreamWindow:info.info.cocoa.window
                                                                                           appName:appName.toNSString()
                                                                                          hostName:hostName.toNSString()];
        return std::unique_ptr<NotchBar>(new MacNotchBar(controller));
    }
}
