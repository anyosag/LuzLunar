#include "notchbar.h"
#include "notchmenus_mac.h"

#include "fork/forklinkrules.h"
#include "fork/forknetworklink.h"
#include "fork/forkpolicy.h"
#include "fork/forkpreferences.h"
#include "fork/hostcadence.h"
#include "fork/notchstatus.h"
#include "fork/streamstats.h"
#include "SDL_compat.h"

#include <atomic>
#include <functional>

#include <QCoreApplication>

#include <SDL_syswm.h>

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
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
    const int64_t k_NoticeDurationNs = 6 * NSEC_PER_SEC;   // a power notice or a hint is longer to read
    const int64_t k_ActionNoticeDurationNs = 10 * NSEC_PER_SEC; // and longer still with a button to press
    const CGFloat k_ButtonGap = 9;    // between a message and its button
    const CGFloat k_ButtonInset = 11; // between a message's button and the pill's end
    const CGFloat k_ButtonHeight = 19;
    const int k_ReachHintStreams = 3; // the streams that say how to reach the bar while the PC has the mouse
    const int k_ReachHintTries = 5;   // a second apart, for the stream to take the mouse

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

// What a message is, which picks its icon
typedef NS_ENUM(NSInteger, ForkMessageKind) {
    ForkMessageKindClipboard,   // a clipboard message: a clipboard
    ForkMessageKindWarning,     // the connection warning: a yellow warning sign
    ForkMessageKindPower,       // Low Power Mode: a yellow dot, as on the canvas
    ForkMessageKindHint,        // how to reach the bar: a keyboard
};

// A message's button, in the canvas's blue capsule: "Reconnect at 60 fps". It answers the first click
// without taking focus from the stream, as the bar's items do.
@interface ForkPillButton : NSView
@property (nonatomic, copy) void (^onPress)(void);
- (void)setTitle:(NSString*)title;
- (CGFloat)naturalWidth;
@end

@implementation ForkPillButton
{
    NSTextField* m_Label;
    NSSize m_LabelSize;     // the title's own size: layout widens the label to the whole button
    BOOL m_Pressed;
}

@synthesize onPress = _onPress;

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    self.wantsLayer = YES;
    m_Label = [[NSTextField labelWithString:@""] retain];
    m_Label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    m_Label.textColor = NSColor.whiteColor;
    m_Label.alignment = NSTextAlignmentCenter;
    [self addSubview:m_Label];
    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityButtonRole];
    [self updateLayer];
    return self;
}

- (void)dealloc
{
    [_onPress release];
    [m_Label release];
    [super dealloc];
}

- (void)setTitle:(NSString*)title
{
    m_Label.stringValue = title != nil ? title : @"";
    [m_Label sizeToFit];
    m_LabelSize = m_Label.frame.size;
    [self setAccessibilityLabel:title];
    self.needsLayout = YES;
}

- (CGFloat)naturalWidth
{
    return ceil(m_LabelSize.width + 16);
}

- (void)layout
{
    [super layout];
    NSSize size = self.bounds.size;
    m_Label.frame = NSMakeRect(0, round((size.height - m_LabelSize.height) / 2), size.width, m_LabelSize.height);
    // A capsule at whatever height it's given
    self.needsDisplay = YES;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSColor* blue = [NSColor colorWithSRGBRed:0x0a / 255.0 green:0x84 / 255.0 blue:1 alpha:1];
    self.layer.backgroundColor = (m_Pressed ? [blue blendedColorWithFraction:0.25 ofColor:NSColor.blackColor] : blue).CGColor;
    self.layer.cornerRadius = NSHeight(self.bounds) / 2;
    [CATransaction commit];
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent*)event
{
    (void)event;
    m_Pressed = YES;
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent*)event
{
    BOOL inside = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    m_Pressed = NO;
    self.needsDisplay = YES;
    if (inside && _onPress != nil) {
        _onPress();
    }
}

- (BOOL)accessibilityPerformPress
{
    if (_onPress != nil) {
        _onPress();
        return YES;
    }
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
    ForkMessageKind m_Kind;
    unsigned m_Generation;      // completion handlers of older animations do nothing
}
- (instancetype)initWithStreamWindow:(NSWindow*)window;
// Shows the message, or another one in its place, or hides it for nil
- (void)showMessage:(NSString*)text kind:(ForkMessageKind)kind;
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
    ForkBarItem* m_StatsItem;       // the stream's stats, right of the notch: Stream status
    ForkBarItem* m_QualityItem;     // the bitrate, after the stats: Quality
    ForkBarItem* m_BatteryItem;     // the Mac's battery, after the bitrate: Battery
    ForkBarItem* m_ControlItem;     // Stream Control Center, at the right edge
    NSString* m_AppName;
    NSString* m_HostName;
    int m_VideoWidth;
    int m_VideoHeight;
    BOOL m_NotchStatsShown;         // the stats' text beside their icon (Control Center's Notch Stats)
    unsigned m_StatusTickGeneration; // the tick that keeps an open Stream status or Quality current
    int m_QualityKbps;              // what the Quality item shows
    BOOL m_QualityLowered;
    BOOL m_HasBattery;              // the Battery item is on the bar
    NSString* m_BatteryShown;       // what the Battery item shows, to tell when it changes

    // The menus under the items, and what they do (MacNotchBar::setActions())
    ForkNotchMenus* m_Menus;
    std::function<void(NotchMenus::Action, int)> m_Actions;
    std::function<NotchBar::MenuState()> m_State;
    NotchBar::StreamSettingsSource m_StreamSettings;
    NotchMenus::Menu m_OpenMenu;    // the menu open now, Stream Settings (no item of its own) included
    NSRect m_StripFrame;            // the strip beside the notch on screen, from the last layout

    // Messages beside the notch, in a pill that grows out of a blinking red dot
    NSView* m_MessagePill;
    NSImageView* m_MessageIcon;
    NSTextField* m_MessageLabel;
    NSView* m_Dot;
    NSString* m_Warning;            // the connection warning, until the connection recovers
    NSString* m_Toast;              // a clipboard message or a power notice, shown for a few seconds
    ForkMessageKind m_ToastKind;
    // A power notice's button (showNotice()): its title, nil for none, and what it does
    NSString* m_ToastActionTitle;
    NotchMenus::Action m_ToastAction;
    int m_ToastActionValue;
    ForkPillButton* m_MessageButton;
    unsigned m_ToastGeneration;
    unsigned m_ToastTimerGeneration;
    ForkMessageKind m_ShownKind;    // what the pill holds
    ForkMessageState m_MessageState;
    unsigned m_AnimationGeneration; // completion handlers of older animations do nothing
    ForkCornerMessage* m_Corner;    // shows the messages instead while the stream is windowed
    BOOL m_BarOnScreen;
    BOOL m_CornerOnScreen;
    BOOL m_CoversScreen;            // the stream window fills its screen without being in a fullscreen Space
    std::atomic<bool> m_ShowsMessages; // the bar or the corner pill is on screen
    BOOL m_FullScreenTransition;    // the stream window is entering or leaving its fullscreen Space
    unsigned m_TransitionGeneration;
    BOOL m_ReachHintOffered;        // this stream had its chance to say how to reach the bar

    // The area left of the notch and the pill size, in panel coordinates, from the last refresh
    BOOL m_HasGeometry;
    NSRect m_LeftArea;
    CGFloat m_PillHeight;
    CGFloat m_PillY;
}
- (instancetype)initWithStreamWindow:(NSWindow*)window appName:(NSString*)appName hostName:(NSString*)hostName
                          videoWidth:(int)videoWidth videoHeight:(int)videoHeight;
- (void)setActions:(std::function<void(NotchMenus::Action, int)>)actions state:(std::function<NotchBar::MenuState()>)state;
- (void)setStreamSettings:(NotchBar::StreamSettingsSource)source;
- (BOOL)toggleMenusByKeyboard;
- (BOOL)handleMenuKey:(int)scancode pressed:(BOOL)pressed shift:(BOOL)shift;
- (BOOL)menuOpen;
- (BOOL)barOnScreen;
- (void)takePointerAtWindowX:(CGFloat)windowX;
- (void)refreshMenus;
- (void)bitrateChanged;
- (void)powerChanged;
- (void)updateQualityItem;
- (void)updateBatteryItem;
- (void)statsArrived;
- (void)setWarning:(NSString*)text;
- (void)showToast:(NSString*)text;
- (void)showToast:(NSString*)text kind:(ForkMessageKind)kind;
- (void)showNotice:(NSString*)text actionTitle:(NSString*)actionTitle action:(NotchMenus::Action)action value:(int)value;
- (void)pressedMessageButton;
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

// The battery as macOS's menu bar draws it, from the canvas: 27 by 13, filled by the level, yellow in
// Low Power Mode, red at 10% or less on battery, with a bolt on a power adapter
static NSImage* batteryImage(const PowerRules::Glyph& glyph)
{
    NSColor* fill = glyph.fill == PowerRules::Fill::Yellow ? [NSColor colorWithSRGBRed:1 green:0xd6 / 255.0 blue:0x0a / 255.0 alpha:1] :
                    glyph.fill == PowerRules::Fill::Red    ? [NSColor colorWithSRGBRed:1 green:0x45 / 255.0 blue:0x3a / 255.0 alpha:1] :
                                                             NSColor.whiteColor;
    CGFloat fillWidth = glyph.fillWidth;
    BOOL bolt = glyph.bolt;
    return [NSImage imageWithSize:NSMakeSize(27, 13) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        NSColor* outline = [NSColor colorWithWhite:1 alpha:0.45];
        NSBezierPath* body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.75, 0.75, 22, 11.5) xRadius:3.6 yRadius:3.6];
        body.lineWidth = 1;
        [outline setStroke];
        [body stroke];
        [fill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2.4, 2.4, fillWidth, 8.2) xRadius:2 yRadius:2] fill];
        [outline setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(23.9, 4.3, 1.7, 4.4) xRadius:0.85 yRadius:0.85] fill];
        if (bolt) {
            NSBezierPath* path = [NSBezierPath bezierPath];
            [path moveToPoint:NSMakePoint(12.6, 1.6)];
            [path lineToPoint:NSMakePoint(8.4, 7.2)];
            [path lineToPoint:NSMakePoint(11.4, 7.2)];
            [path lineToPoint:NSMakePoint(10.3, 11.6)];
            [path lineToPoint:NSMakePoint(14.6, 5.9)];
            [path lineToPoint:NSMakePoint(11.5, 5.9)];
            [path closePath];
            [NSColor.whiteColor setFill];
            [path fill];
            path.lineWidth = 0.8;
            path.lineJoinStyle = NSLineJoinStyleRound;
            [NSColor.blackColor setStroke];
            [path stroke];
        }
        return YES;
    }];
}

// The stats' text, with its "·" separators dimmed as on the canvas
static NSAttributedString* statsTitle(NSString* text)
{
    NSMutableAttributedString* title =
        [[[NSMutableAttributedString alloc] initWithString:text
                                                attributes:@{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium],
                                                              NSForegroundColorAttributeName: NSColor.labelColor }] autorelease];
    NSColor* dimmed = [NSColor colorWithSRGBRed:0x6e / 255.0 green:0x6e / 255.0 blue:0x75 / 255.0 alpha:1];
    NSRange search = NSMakeRange(0, text.length);
    for (;;) {
        NSRange dot = [text rangeOfString:@"·" options:0 range:search];
        if (dot.location == NSNotFound) {
            break;
        }
        [title addAttribute:NSForegroundColorAttributeName value:dimmed range:dot];
        search = NSMakeRange(NSMaxRange(dot), text.length - NSMaxRange(dot));
    }
    return title;
}

// The canvas's 7 pt yellow dot, for Low Power Mode
static NSImage* yellowDot()
{
    static NSImage* dot = [[NSImage imageWithSize:NSMakeSize(7, 7) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor colorWithSRGBRed:1 green:0xd6 / 255.0 blue:0x0a / 255.0 alpha:1] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:rect] fill];
        return YES;
    }] retain];
    return dot;
}

// Puts a message in a pill's icon and label: a yellow warning sign for the connection warning, a
// clipboard for clipboard messages, a yellow dot for Low Power Mode, a keyboard for a hint
static void setMessageContent(NSImageView* icon, NSTextField* label, NSString* text, ForkMessageKind kind)
{
    label.stringValue = text != nil ? text : @"";
    icon.image = kind == ForkMessageKindPower   ? yellowDot() :
                 kind == ForkMessageKindWarning ? symbolImage(@"wifi.exclamationmark") :
                 kind == ForkMessageKindHint    ? symbolImage(@"keyboard") : symbolImage(@"doc.on.clipboard");
    icon.contentTintColor = kind == ForkMessageKindWarning ? NSColor.systemYellowColor : NSColor.labelColor;
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
                          videoWidth:(int)videoWidth videoHeight:(int)videoHeight
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
    m_VideoWidth = videoWidth;
    m_VideoHeight = videoHeight;
    m_NotchStatsShown = ForkPreferences::get()->notchBarStats();

    m_SessionItem = [[ForkBarItem alloc] initWithSymbol:@"moon"];
    [m_SessionItem setTitle:sessionTitle(appName, hostName)];
    [m_SessionItem setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Session menu: %1 on %2")
                                             .arg(QString::fromNSString(appName), QString::fromNSString(hostName)).toNSString()];
    m_StatsItem = [[ForkBarItem alloc] initWithSymbol:@"network"];
    [m_StatsItem setTitle:statsTitle(m_NotchStatsShown ? @"—" : @"")];
    [m_StatsItem setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Stream status").toNSString()];
    // Its arrow and bitrate come with the menus' state (updateQualityItem)
    m_QualityItem = [[ForkBarItem alloc] initWithSymbol:nil];
    [m_QualityItem setTitle:statsTitle(@"—")];
    [m_QualityItem setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Bitrate").toNSString()];
    // Its level and glyph too (updateBatteryItem); off the bar until a battery turns up
    m_BatteryItem = [[ForkBarItem alloc] initWithSymbol:nil];
    [m_BatteryItem setTitle:statsTitle(@"")];
    [m_BatteryItem setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Battery").toNSString()];
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
    m_StatsItem.onPress = ^{
        [controller pressedItemForMenu:NotchMenus::Menu::Status];
    };
    m_QualityItem.onPress = ^{
        [controller pressedItemForMenu:NotchMenus::Menu::Quality];
    };
    m_BatteryItem.onPress = ^{
        [controller pressedItemForMenu:NotchMenus::Menu::Battery];
    };
    m_ControlItem.onPress = ^{
        [controller pressedItemForMenu:NotchMenus::Menu::ControlCenter];
    };

    m_MessageLabel = makeLabel(@"");
    m_MessageIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    m_MessageIcon.imageScaling = NSImageScaleNone;
    m_MessageButton = [[ForkPillButton alloc] initWithFrame:NSZeroRect];
    m_MessageButton.hidden = YES;
    m_MessageButton.onPress = ^{
        [controller pressedMessageButton];
    };
    m_MessagePill = makePill(@[ m_MessageIcon, m_MessageLabel, m_MessageButton ]);
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
    [m_Panel.contentView addSubview:m_QualityItem];
    [m_Panel.contentView addSubview:m_BatteryItem];
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
    [m_QualityItem release];
    [m_BatteryItem release];
    [m_BatteryShown release];
    [m_ControlItem release];
    [m_AppName release];
    [m_HostName release];
    [m_Menus release];
    [m_MessagePill release];
    [m_MessageIcon release];
    [m_MessageLabel release];
    [m_MessageButton release];
    [m_ToastActionTitle release];
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
    m_State = nullptr;
    m_StreamSettings = NotchBar::StreamSettingsSource();
    [m_Menus invalidate];
    m_SessionItem.onPress = nil;
    m_StatsItem.onPress = nil;
    m_QualityItem.onPress = nil;
    m_BatteryItem.onPress = nil;
    m_MessageButton.onPress = nil;
    m_ControlItem.onPress = nil;
    m_StatusTickGeneration++;
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
    for (NSView* view in @[ m_SessionItem, m_StatsItem, m_QualityItem, m_BatteryItem, m_ControlItem, m_Dot, m_MessagePill ]) {
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

// A new snapshot: the stats item's text, and an open Stream status
- (void)statsArrived
{
    if (m_StreamWindow == nil) {
        return;
    }

    ForkStreamStats::Snapshot stats;
    if (!ForkStreamStats::latest(&stats)) {
        return;
    }
    // The Wi-Fi band where the bar shows the link (ForkLinkRules::shouldShow())
    ForkNetworkLink::Current link = ForkNetworkLink::current();
    BOOL wifi = link.known && link.link.kind == ForkLinkRules::Kind::WiFi;
    std::string band = wifi && link.shown ? ForkLinkRules::bandText(link.link.bandGHz) : std::string();
    NSString* text = [NSString stringWithUTF8String:NotchStatus::barText(band, stats.fps, stats.rttMs).c_str()];
    [m_StatsItem setSymbol:wifi ? @"wifi" : @"network"];
    [m_StatsItem setTitle:statsTitle(m_NotchStatsShown ? text : @"")];
    [m_StatsItem setAccessibilityValue:text];
    [self updateQualityItem];
    [self refresh];
    [m_Menus statusChanged];
}

// "18 Mb/s", after an orange arrow while that's below the user's bitrate
- (void)updateQualityItem
{
    if (m_StreamWindow == nil || !m_State) {
        return;
    }
    NotchQuality::State state = m_State().bitrate;
    int kbps = NotchQuality::shownKbps(state);
    BOOL lowered = NotchQuality::lowered(state);
    if (kbps == m_QualityKbps && lowered == m_QualityLowered) {
        return;
    }
    m_QualityKbps = kbps;
    m_QualityLowered = lowered;

    QString mbps = QString::fromStdString(NotchQuality::mbps(kbps));
    [m_QualityItem setSymbol:lowered ? @"arrow.down" : nil
                        tint:[NSColor colorWithSRGBRed:1 green:0x9f / 255.0 blue:0x0a / 255.0 alpha:1]];
    [m_QualityItem setTitle:statsTitle(QCoreApplication::translate("NotchBar", "%1 Mb/s").arg(mbps).toNSString())];
    QString label = QCoreApplication::translate("NotchBar", "Bitrate: %1 megabits per second").arg(mbps);
    if (lowered) {
        label = QCoreApplication::translate("NotchBar", "%1, below your %2").arg(label, QString::fromStdString(NotchQuality::mbps(state.ownKbps)));
    }
    [m_QualityItem setAccessibilityLabel:label.toNSString()];
    [self refresh];
}

// "76%" and the glyph, as macOS's menu bar shows the battery
- (void)updateBatteryItem
{
    if (m_StreamWindow == nil || !m_State) {
        return;
    }
    NotchBar::MenuState state = m_State();
    BOOL hasBattery = state.powerKnown && state.power.present;
    const PowerRules::Reading& power = state.power;
    PowerRules::Glyph glyph = PowerRules::glyph(power, state.lowPowerMode);
    NSString* shown = [NSString stringWithFormat:@"%d %d %d %d %d %.1f", hasBattery, power.level, (int)glyph.fill, glyph.bolt,
                                                 power.charging, glyph.fillWidth];
    if (hasBattery == m_HasBattery && [shown isEqualToString:m_BatteryShown]) {
        return;
    }
    m_HasBattery = hasBattery;
    [m_BatteryShown release];
    m_BatteryShown = [shown copy];

    if (hasBattery) {
        [m_BatteryItem setTitle:statsTitle([NSString stringWithFormat:@"%d%%", power.level])];
        [m_BatteryItem setTrailingImage:batteryImage(glyph)];
        QString label = QCoreApplication::translate("NotchBar", "Battery %1%").arg(power.level);
        if (power.charging) {
            label += QCoreApplication::translate("NotchBar", ", charging");
        }
        if (state.lowPowerMode) {
            label += QCoreApplication::translate("NotchBar", ", Low Power Mode on");
        }
        [m_BatteryItem setAccessibilityLabel:label.toNSString()];
    }
    [self refresh];
}

// While Stream status, Quality or Battery is open, once a second, so it moves on even when no frames
// come (a still desktop): the graph, how long ago the bitrate changed, how long the stream has run
- (void)tickStatus:(unsigned)generation
{
    NotchMenus::Menu open = [m_Menus openMenu];
    if (generation != m_StatusTickGeneration || m_StreamWindow == nil ||
            (open != NotchMenus::Menu::Status && open != NotchMenus::Menu::Quality && open != NotchMenus::Menu::Battery)) {
        return;
    }
    if (open == NotchMenus::Menu::Status) {
        [m_Menus statusChanged];
    }
    else if (open == NotchMenus::Menu::Quality) {
        [m_Menus qualityChanged];
    }
    else {
        [m_Menus powerChanged];
    }
    [self retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self tickStatus:generation];
        [self release];
    });
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
    [self showToast:text kind:ForkMessageKindClipboard];
}

- (void)showToast:(NSString*)text kind:(ForkMessageKind)kind
{
    [self showNotice:text kind:kind actionTitle:nil action:NotchMenus::Action::None value:0];
}

- (void)showNotice:(NSString*)text actionTitle:(NSString*)actionTitle action:(NotchMenus::Action)action value:(int)value
{
    [self showNotice:text kind:ForkMessageKindPower actionTitle:actionTitle action:action value:value];
}

- (void)showNotice:(NSString*)text kind:(ForkMessageKind)kind actionTitle:(NSString*)actionTitle action:(NotchMenus::Action)action value:(int)value
{
    if (m_StreamWindow == nil) {
        return;
    }

    [m_Toast release];
    m_Toast = [text copy];
    m_ToastKind = kind;
    [m_ToastActionTitle release];
    m_ToastActionTitle = actionTitle.length > 0 ? [actionTitle copy] : nil;
    m_ToastAction = action;
    m_ToastActionValue = value;
    m_ToastGeneration++;
    [self updateMessage];
}

// The message's button: does its action, and the message goes
- (void)pressedMessageButton
{
    if (m_StreamWindow == nil || m_Toast == nil || m_ToastActionTitle == nil) {
        return;
    }
    NotchMenus::Action action = m_ToastAction;
    int value = m_ToastActionValue;
    [m_Toast release];
    m_Toast = nil;
    m_ToastGeneration++;
    [self updateMessage];
    if (m_Actions) {
        m_Actions(action, value);
    }
}

- (BOOL)showsMessages
{
    return m_ShowsMessages.load();
}

// Menus

- (void)setActions:(std::function<void(NotchMenus::Action, int)>)actions state:(std::function<NotchBar::MenuState()>)state
{
    m_Actions = std::move(actions);
    m_State = std::move(state);
    [self updateQualityItem];
    [self updateBatteryItem];
    if (m_BarOnScreen && m_Actions) {
        // Already up: the pointer mustn't be held to the picture
        m_Actions(NotchMenus::Action::BarShownOrHidden, 0);
    }
    [self offerReachHint];
}

// While the PC has the mouse (a game's, or the trackpad as a touchpad), the pointer on screen is the
// PC's, drawn in the picture, and it can't leave it for the bar: say how to reach the bar instead,
// pushing past the top in Mac trackpad mode, else Control-Option-Shift-N. Once a stream, when the bar
// first comes up with the mouse held, in the first few streams, and not once either has been used.
// The remote desktop's mouse is the Mac's own pointer, which moves up into the bar.
- (void)offerReachHint
{
    [self offerReachHint:0];
}

- (void)offerReachHint:(int)tries
{
    ForkPreferences* prefs = ForkPreferences::get();
    if (m_ReachHintOffered || !m_BarOnScreen || !m_State || m_StreamWindow == nil || prefs->notchBarHints() >= k_ReachHintStreams) {
        return;
    }
    NotchBar::MenuState state = m_State();
    if (state.mouseAbsolute) {
        return;
    }
    if (!state.mouseCaptured) {
        // The stream takes the mouse once its picture is up, which can be just after the bar is
        if (tries + 1 < k_ReachHintTries) {
            [self retain];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self offerReachHint:tries + 1];
                [self release];
            });
        }
        return;
    }
    m_ReachHintOffered = YES;

    // Not over a message already up, as a clipboard or Low Power Mode one is the stream's own news
    if (m_Toast != nil) {
        return;
    }
    prefs->setNotchBarHints(prefs->notchBarHints() + 1);
    // Mac trackpad mode's pointer comes up into the bar by itself, past the top
    NSString* text = state.pointerReachesBar ?
                         QCoreApplication::translate("NotchBar", "Keep moving up past the top to use this bar").toNSString() :
                         QCoreApplication::translate("NotchBar", "Press ⌃⌥⇧N to use this bar while the PC has the mouse").toNSString();
    [self showToast:text kind:ForkMessageKindHint];
}

- (BOOL)barOnScreen
{
    return m_BarOnScreen;
}

// Mac trackpad mode's pointer came up past the top of the picture: the Mac's own goes on from there,
// half way up the strip
- (void)takePointerAtWindowX:(CGFloat)windowX
{
    if (m_StreamWindow == nil || !m_BarOnScreen || !m_HasGeometry) {
        return;
    }
    // No more hints: this is how
    ForkPreferences::get()->setNotchBarHints(MAX(ForkPreferences::get()->notchBarHints(), k_ReachHintStreams));

    CGFloat x = MIN(MAX(NSMinX(m_StreamWindow.frame) + windowX, NSMinX(m_StripFrame) + 1), NSMaxX(m_StripFrame) - 1);
    CGFloat y = NSMinY(m_StripFrame) + NSHeight(m_StripFrame) / 2;
    // Quartz's coordinates go down from the top of the primary display
    NSScreen* primary = NSScreen.screens.firstObject;
    if (primary == nil) {
        return;
    }
    CGWarpMouseCursorPosition(CGPointMake(x, NSMaxY(primary.frame) - y));
    // Else macOS holds the pointer still for a moment after the warp
    CGAssociateMouseAndMouseCursorPosition(true);
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
    // Known now: no more hints
    ForkPreferences::get()->setNotchBarHints(MAX(ForkPreferences::get()->notchBarHints(), k_ReachHintStreams));
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
    [self updateQualityItem];
    [m_Menus refresh];
}

- (void)bitrateChanged
{
    [self updateQualityItem];
    [m_Menus bitrateChanged];
}

- (void)powerChanged
{
    [self updateBatteryItem];
    [m_Menus powerChanged];
}

- (void)menusPerform:(NotchMenus::Action)action
{
    if (action == NotchMenus::Action::OpenBatterySettings) {
        // The bar's own: System Settings comes forward, and the stream loses focus as with Command-Tab
        NSURL* url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Battery-Settings.extension"];
        if (![NSWorkspace.sharedWorkspace openURL:url]) {
            [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:@"/System/Library/PreferencePanes/Battery.prefPane"]];
        }
        return;
    }
    if (action == NotchMenus::Action::ToggleNotchStats) {
        // The bar's own, and remembered
        m_NotchStatsShown = !m_NotchStatsShown;
        ForkPreferences::get()->setNotchBarStats(m_NotchStatsShown);
        NSString* text = m_StatsItem.accessibilityValue;
        [m_StatsItem setTitle:statsTitle(m_NotchStatsShown ? (text.length > 0 ? text : @"—") : @"")];
        [self refresh];
        [m_Menus refresh];
        return;
    }
    [self menusPerform:action value:0];
}

- (void)menusPerform:(NotchMenus::Action)action value:(int)value
{
    if (m_Actions) {
        m_Actions(action, value);
    }
}

- (NotchBar::MenuState)menusState
{
    NotchBar::MenuState state = m_State ? m_State() : NotchBar::MenuState();
    state.notchStatsShown = m_NotchStatsShown;
    return state;
}

- (void)setStreamSettings:(NotchBar::StreamSettingsSource)source
{
    m_StreamSettings = std::move(source);
}

- (BOOL)menusStreamSettings:(ForkStreamSettings::View*)view open:(BOOL)open
{
    if (!m_StreamSettings.view) {
        return NO;
    }
    *view = m_StreamSettings.view(open);
    return YES;
}

- (void)menusStreamSettingsPick:(int)row choice:(int)choice
{
    if (m_StreamSettings.pick) {
        m_StreamSettings.pick(row, choice);
    }
}

- (void)menusStreamSettingsPreset:(int)preset
{
    if (m_StreamSettings.preset) {
        m_StreamSettings.preset(preset);
    }
}

- (void)menusStreamSettingsReset
{
    if (m_StreamSettings.reset) {
        m_StreamSettings.reset();
    }
}

- (void)menusStatus:(ForkStatusModel*)model
{
    model->now = ForkStreamStats::nowSeconds();
    model->samples = ForkStreamStats::history();
    ForkStreamStats::Snapshot stats;
    model->haveLatest = ForkStreamStats::latest(&stats);
    if (model->haveLatest) {
        model->latest.seconds = stats.seconds;
        model->latest.parts = stats.latencyMs;
    }
    bool suggestLowerBitrate;
    model->health = NotchStatus::health(model->haveLatest, ForkStreamStats::connectionPoor(&suggestLowerBitrate),
                                        model->samples, model->now);

    ForkNetworkLink::Current link = ForkNetworkLink::current();
    if (link.known) {
        model->connection = QString::fromStdString(ForkLinkRules::connectionText(link.link, link.viaLan));
        model->linkSpeed = QString::fromStdString(ForkLinkRules::speedText(link.link.mbps));
    }

    QString resolution = QStringLiteral("%1×%2").arg(m_VideoWidth).arg(m_VideoHeight);
    if (model->haveLatest) {
        model->frameRate = QCoreApplication::translate("NotchBar", "%1 fps").arg(stats.fps, 0, 'f', 0);
        switch (pacingVerdict(stats.pacingLowest, stats.fps)) {
        case PacingVerdict::Even:
            model->pacing = QCoreApplication::translate("NotchBar", "Even");
            break;
        case PacingVerdict::Uneven:
            model->pacing = QCoreApplication::translate("NotchBar", "Uneven");
            break;
        case PacingVerdict::Unknown:
            break;
        }
        model->framesLost = QStringLiteral("%1%").arg(stats.dropPercent, 0, 'f', 1);
        model->video = stats.codec + QStringLiteral(" · ") + resolution;
    }
    else {
        model->video = resolution;
    }
}

- (NSRect)menusAnchorFor:(NotchMenus::Menu)menu alignRight:(BOOL*)alignRight
{
    if (menu == NotchMenus::Menu::StreamSettings) {
        // Centred under the notch, which is at the middle of the screen: a point-wide anchor there
        if (!m_BarOnScreen || !m_StreamSettings.view) {
            return NSZeroRect;
        }
        *alignRight = NO;
        return NSMakeRect(NSMidX(m_StripFrame) - 0.5, NSMinY(m_StripFrame), 1, NSHeight(m_StripFrame));
    }
    ForkBarItem* item = menu == NotchMenus::Menu::Session ? m_SessionItem :
                        menu == NotchMenus::Menu::Status ? m_StatsItem :
                        menu == NotchMenus::Menu::Quality ? m_QualityItem :
                        menu == NotchMenus::Menu::Battery ? m_BatteryItem :
                        menu == NotchMenus::Menu::ControlCenter ? m_ControlItem : nil;
    if (item == nil || item.hidden || !m_BarOnScreen) {
        return NSZeroRect;
    }
    // Right of the notch, menus line up with their item's right edge, which stays put as the stats change
    *alignRight = item != m_SessionItem;
    // The item's left and right edges, and the bottom of the strip, so the menu hangs below the bar
    NSRect frame = [m_Panel convertRectToScreen:[item convertRect:item.bounds toView:nil]];
    return NSMakeRect(NSMinX(frame), NSMinY(m_StripFrame), NSWidth(frame), NSHeight(m_StripFrame));
}

- (void)menusChanged:(NotchMenus::Menu)menu
{
    BOOL wasOpen = m_OpenMenu != NotchMenus::Menu::None;
    m_OpenMenu = menu;
    BOOL tickedOpen = m_StatsItem.open || m_QualityItem.open || m_BatteryItem.open;
    m_SessionItem.open = menu == NotchMenus::Menu::Session;
    m_StatsItem.open = menu == NotchMenus::Menu::Status;
    m_QualityItem.open = menu == NotchMenus::Menu::Quality;
    m_BatteryItem.open = menu == NotchMenus::Menu::Battery;
    m_ControlItem.open = menu == NotchMenus::Menu::ControlCenter;
    if ((m_StatsItem.open || m_QualityItem.open || m_BatteryItem.open) && !tickedOpen) {
        // From one of them to another, the tick goes on
        [self tickStatus:++m_StatusTickGeneration];
    }
    BOOL isOpen = menu != NotchMenus::Menu::None;
    if (isOpen != wasOpen && m_Actions) {
        m_Actions(isOpen ? NotchMenus::Action::MenusOpened : NotchMenus::Action::MenusClosed, 0);
    }
}

- (NSWindow*)menusBarWindow
{
    return m_Panel;
}

// The Session item at the left edge of the area left of the notch; the stats, the bitrate, the battery
// and Control Center from the right edge of the area right of it, the stats giving way when they don't fit
- (void)layoutItemsLeft:(NSRect)leftArea right:(NSRect)rightArea height:(CGFloat)height y:(CGFloat)y
{
    CGFloat sessionWidth = MIN([m_SessionItem naturalWidth], MAX(NSWidth(leftArea) - 2 * k_Margin, 0));
    m_SessionItem.frame = NSMakeRect(NSMinX(leftArea) + k_Margin, y, sessionWidth, height);
    m_SessionItem.hidden = sessionWidth <= 0;

    // The stats shrink, down to their icon alone
    std::vector<NotchMenus::Placed> placed = NotchMenus::layoutRight(NSWidth(rightArea), k_Margin, k_ItemGap,
                                                                     { [m_StatsItem naturalWidth], [m_QualityItem naturalWidth],
                                                                       m_HasBattery ? [m_BatteryItem naturalWidth] : 0,
                                                                       [m_ControlItem naturalWidth] },
                                                                     0, [m_StatsItem iconOnlyWidth]);
    NSArray<ForkBarItem*>* items = @[ m_StatsItem, m_QualityItem, m_BatteryItem, m_ControlItem ];
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
        m_Actions(NotchMenus::Action::BarShownOrHidden, 0);
    }
    if (barChanged && show) {
        [self offerReachHint];
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

- (ForkMessageKind)currentKind
{
    return m_Toast != nil ? m_ToastKind : ForkMessageKindWarning;
}

- (BOOL)pillShowsCurrentMessage
{
    NSString* message = [self currentMessage];
    return message != nil && m_ShownKind == [self currentKind] && [message isEqualToString:m_MessageLabel.stringValue];
}

// Puts the current message in the pill: the clipboard message or power notice if there is one, else
// the warning
- (void)applyMessageContent
{
    ForkMessageKind kind = [self currentKind];
    setMessageContent(m_MessageIcon, m_MessageLabel, [self currentMessage], kind);
    m_ShownKind = kind;

    // A power notice's button, on the bar's pill
    BOOL button = m_Toast != nil && m_ToastActionTitle != nil;
    m_MessageButton.hidden = !button;
    if (button) {
        [m_MessageButton setTitle:m_ToastActionTitle];
    }
}

// The pill hugs the notch and grows away from it, up to the whole area left of the notch
- (NSRect)messageFrame
{
    CGFloat width = messageWidth(m_MessageIcon, m_MessageLabel);
    if (!m_MessageButton.hidden) {
        // In place of the text's own padding at the end
        width += k_ButtonGap + [m_MessageButton naturalWidth] + k_ButtonInset - k_Padding;
    }
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
    if (!m_MessageButton.hidden) {
        // At the right end, the text giving way before it
        CGFloat buttonWidth = [m_MessageButton naturalWidth];
        CGFloat x = frame.size.width - k_ButtonInset - buttonWidth;
        m_MessageButton.frame = NSMakeRect(x, round((frame.size.height - k_ButtonHeight) / 2), buttonWidth, k_ButtonHeight);
        NSRect label = m_MessageLabel.frame;
        label.size.width = MAX(x - k_ButtonGap - NSMinX(label), 0);
        m_MessageLabel.frame = label;
    }
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
        [m_Corner showMessage:message kind:[self currentKind]];
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
    int64_t duration = m_ToastActionTitle != nil ? k_ActionNoticeDurationNs :
                       (m_ToastKind == ForkMessageKindPower || m_ToastKind == ForkMessageKindHint) ? k_NoticeDurationNs : k_ToastDurationNs;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, duration),
                   dispatch_get_main_queue(), ^{
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
    m_MessageButton.alphaValue = 0;

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
        m_MessageButton.alphaValue = 1;
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
        m_MessageButton.animator.alphaValue = 0;
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
        m_MessageButton.animator.alphaValue = 0;
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
        m_MessageButton.animator.alphaValue = 1;
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
            m_MessageButton.alphaValue = 1;
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

- (void)showMessage:(NSString*)text kind:(ForkMessageKind)kind
{
    if (m_StreamWindow == nil) {
        return;
    }
    if (text == nil) {
        [self hide];
        return;
    }
    if (m_Text != nil && kind == m_Kind && [text isEqualToString:m_Text]) {
        return;
    }

    BOOL replacing = m_Text != nil;
    [m_Text release];
    m_Text = [text copy];
    m_Kind = kind;
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

    setMessageContent(m_Icon, m_Label, m_Text, m_Kind);
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
    setMessageContent(m_Icon, m_Label, m_Text, m_Kind);
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
            ForkStreamStats::setListener([controller](const ForkStreamStats::Snapshot&) {
                // Runs on the decode thread, which has no autorelease pool of its own. The main thread
                // reads the snapshot itself (ForkStreamStats::latest()), with the link and the history.
                @autoreleasepool {
                    [controller retain];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [controller statsArrived];
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

        bool showNotice(const QString& text, const QString& actionTitle, NotchMenus::Action action, int value) override
        {
            if (![m_Controller showsMessages]) {
                return false;
            }

            @autoreleasepool {
                [m_Controller showNotice:text.toNSString() actionTitle:actionTitle.isEmpty() ? nil : actionTitle.toNSString()
                                  action:action value:value];
            }
            return true;
        }

        void setActions(std::function<void(NotchMenus::Action, int)> actions, std::function<MenuState()> state) override
        {
            [m_Controller setActions:std::move(actions) state:std::move(state)];
        }

        void setStreamSettings(StreamSettingsSource source) override
        {
            [m_Controller setStreamSettings:std::move(source)];
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

        void takePointer(double windowX) override
        {
            @autoreleasepool {
                [m_Controller takePointerAtWindowX:windowX];
            }
        }

        void refreshMenus() override
        {
            @autoreleasepool {
                [m_Controller refreshMenus];
            }
        }

        void bitrateChanged() override
        {
            @autoreleasepool {
                [m_Controller bitrateChanged];
            }
        }

        void powerChanged() override
        {
            @autoreleasepool {
                [m_Controller powerChanged];
            }
        }

    private:
        ForkNotchBarController* m_Controller;
    };
}

std::unique_ptr<NotchBar> NotchBar::create(SDL_Window* window, const QString& appName, const QString& hostName,
                                           int width, int height)
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
                                                                                          hostName:hostName.toNSString()
                                                                                        videoWidth:width
                                                                                       videoHeight:height];
        return std::unique_ptr<NotchBar>(new MacNotchBar(controller));
    }
}
