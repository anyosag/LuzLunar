#include "notchmenus_mac.h"

#include "SDL_compat.h"

#include <QCoreApplication>
#include <QString>

#include "fork/reconnectrules.h"

#import <QuartzCore/QuartzCore.h>

// [fork] The notch bar's items and menus. Like the bar (notchbar.mm), every panel here is
// non-activating and can't become key, so the stream keeps focus: if a panel took it, SDL would treat
// it as the stream losing focus (the clipboard fetched, audio muted, the trackpad let go). Menus are
// panels of their own rather than NSMenus, whose tracking loop would hold up the stream's event loop
// while one is open.

namespace
{
    const CGFloat k_ItemPadding = 8;    // inside an item, around its icon and title
    const CGFloat k_ItemGap = 6;        // between an item's icon and title
    const CGFloat k_TrailingGap = 5;    // between an item's title and an image after it
    const CGFloat k_MenuGap = 4;        // between the bar and a menu
    const CGFloat k_ScreenMargin = 6;   // between a menu and the screen's edge

    // Session menu
    const CGFloat k_SessionWidth = 260;         // at least; wider when a row needs it
    const CGFloat k_SessionMaxWidth = 420;
    const int k_AppNameLength = 24;             // longer app names are cut short in the menus
    const CGFloat k_SessionPadding = 5;
    const CGFloat k_HeaderHeight = 22;
    const CGFloat k_RowHeight = 24;
    const CGFloat k_SeparatorHeight = 11;

    // Stream status
    const CGFloat k_StatusWidth = 300;
    const CGFloat k_StatusPadding = 6;

    // Quality
    const CGFloat k_QualityWidth = 320;
    const CGFloat k_QualityPadding = 6;
    const CGFloat k_QualityHeaderHeight = 32;
    const CGFloat k_SwitchRowHeight = 30;
    const CGFloat k_SliderHeight = 22;
    const CGFloat k_Knob = 16;
    const CFTimeInterval k_HeldSeconds = 5;     // the slider's bitrate shows this long at most, waiting for the PC

    // Battery
    const CGFloat k_BatteryWidth = 320;
    const CGFloat k_BatteryPadding = 6;

    // Stream Settings, as on the canvas
    const CGFloat k_SettingsWidth = 360;
    const CGFloat k_SettingsPadding = 12;
    const CGFloat k_SettingsRowHeight = 27;

    // Stream Control Center
    const CGFloat k_CenterWidth = 340;
    const CGFloat k_CenterPadding = 10;
    const CGFloat k_TileGap = 10;
    const CGFloat k_ToggleHeight = 36;
    const CGFloat k_ActionTileHeight = 70;
    const CGFloat k_Circle = 28;

    NSString* tr(const char* text)
    {
        return QCoreApplication::translate("NotchBar", text).toNSString();
    }

    // The app's name, cut short so the rows that name it still show what they do
    QString shortName(NSString* name)
    {
        if (name.length <= (NSUInteger)k_AppNameLength) {
            return QString::fromNSString(name);
        }
        NSRange kept = [name rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, k_AppNameLength - 1)];
        return QString::fromNSString([[name substringWithRange:kept] stringByAppendingString:@"…"]);
    }

    NSImage* symbol(NSString* name, CGFloat size, NSFontWeight weight)
    {
        if (name == nil) {
            return nil;
        }
        if (@available(macOS 11.0, *)) {
            NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
            return [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
        }
        return nil;
    }

    NSTextField* makeText(NSString* text, NSFont* font, NSColor* color)
    {
        NSTextField* label = [NSTextField labelWithString:text != nil ? text : @""];
        label.font = font;
        label.textColor = color;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.maximumNumberOfLines = 1;
        return label;
    }

    // A label that wraps, to two lines at most
    NSTextField* makeWrappingText(NSFont* font, NSColor* color)
    {
        NSTextField* label = makeText(@"", font, color);
        label.maximumNumberOfLines = 2;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.cell.wraps = YES;
        label.cell.scrollable = NO;
        label.cell.usesSingleLineMode = NO;
        return label;
    }

    // The height a label needs at this width
    CGFloat textHeight(NSTextField* label, CGFloat width)
    {
        return ceil([label.cell cellSizeForBounds:NSMakeRect(0, 0, width, 1000)].height);
    }

    // The trackpad's modes, as Settings names them
    NSString* trackpadModeTitle(int mode)
    {
        return mode == ReconnectRules::k_TrackpadMacTrackpad      ? tr("Mac trackpad") :
               mode == ReconnectRules::k_TrackpadWindowsTouchpad ? tr("Windows touchpad") : tr("Mac mouse");
    }

    // "18 Mb/s"
    QString mbpsText(int kbps)
    {
        return QCoreApplication::translate("NotchBar", "%1 Mb/s").arg(QString::fromStdString(NotchQuality::mbps(kbps)));
    }

    // "just now", "40 s ago", "3 min ago"
    QString agoText(double seconds)
    {
        NotchQuality::Ago ago = NotchQuality::ago(seconds);
        switch (ago.unit) {
        case NotchQuality::Ago::Seconds:
            return QCoreApplication::translate("NotchBar", "%1 s ago").arg(ago.value);
        case NotchQuality::Ago::Minutes:
            return QCoreApplication::translate("NotchBar", "%1 min ago").arg(ago.value);
        case NotchQuality::Ago::JustNow:
            break;
        }
        return QCoreApplication::translate("NotchBar", "just now");
    }

    // The Stream status graph's "Bitrate lowered" orange
    NSColor* loweredColor()
    {
        return [NSColor colorWithSRGBRed:1 green:0x9f / 255.0 blue:0x0a / 255.0 alpha:1];
    }

    // Low Power Mode's and Stream Battery Saver's yellow
    NSColor* saverColor()
    {
        return [NSColor colorWithSRGBRed:1 green:0xd6 / 255.0 blue:0x0a / 255.0 alpha:1];
    }

    // A menu's separator line, as the Session menu's
    NSView* makeSeparatorLine()
    {
        NSView* line = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
        line.wantsLayer = YES;
        line.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.12].CGColor;
        return line;
    }

    CGColorRef white(CGFloat alpha)
    {
        return [NSColor colorWithWhite:1 alpha:alpha].CGColor;
    }

    BOOL isNavigationKey(int scancode)
    {
        switch (scancode) {
        case SDL_SCANCODE_UP:
        case SDL_SCANCODE_DOWN:
        case SDL_SCANCODE_LEFT:
        case SDL_SCANCODE_RIGHT:
        case SDL_SCANCODE_TAB:
        case SDL_SCANCODE_HOME:
        case SDL_SCANCODE_END:
        case SDL_SCANCODE_RETURN:
        case SDL_SCANCODE_KP_ENTER:
        case SDL_SCANCODE_SPACE:
        case SDL_SCANCODE_ESCAPE:
            return YES;
        default:
            return NO;
        }
    }
}

// Top-down coordinates for the menus' contents
@interface ForkFlippedView : NSView
@end

@implementation ForkFlippedView
- (BOOL)isFlipped
{
    return YES;
}
@end

// A menu's panel: like the bar's, it never becomes key
@interface ForkMenuPanel : NSPanel
@end

@implementation ForkMenuPanel
- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}
@end

@implementation ForkBarItem
{
    NSImageView* m_Icon;
    NSTextField* m_Label;
    NSImageView* m_Trailing;    // an image after the title, as the battery's
    NSTrackingArea* m_Tracking;
    BOOL m_Hovered;
}

@synthesize onPress = _onPress;
@synthesize interactive = _interactive;
@synthesize open = _open;

- (instancetype)initWithSymbol:(NSString*)name
{
    self = [super initWithFrame:NSZeroRect];
    if (self == nil) {
        return nil;
    }

    self.wantsLayer = YES;
    self.layer.cornerRadius = 6;
    _interactive = YES;

    NSImage* image = symbol(name, 13, NSFontWeightMedium);
    if (image != nil) {
        m_Icon = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, image.size.width, image.size.height)];
        m_Icon.image = image;
        m_Icon.imageScaling = NSImageScaleNone;
        m_Icon.contentTintColor = NSColor.labelColor;
        [self addSubview:m_Icon];
    }
    m_Label = [makeText(@"", [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium], NSColor.labelColor) retain];
    [self addSubview:m_Label];

    [self setAccessibilityElement:YES];
    [self setAccessibilityRole:NSAccessibilityButtonRole];
    [self setAccessibilityExpanded:NO];
    return self;
}

- (void)setSymbol:(NSString*)name
{
    [self setSymbol:name tint:nil];
}

- (void)setSymbol:(NSString*)name tint:(NSColor*)tint
{
    NSImage* image = symbol(name, 13, NSFontWeightMedium);
    if (image == nil) {
        [m_Icon removeFromSuperview];
        [m_Icon release];
        m_Icon = nil;
    }
    else {
        if (m_Icon == nil) {
            m_Icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
            m_Icon.imageScaling = NSImageScaleNone;
            m_Icon.contentTintColor = NSColor.labelColor;
            [self addSubview:m_Icon];
        }
        m_Icon.image = image;
        m_Icon.contentTintColor = tint != nil ? tint : NSColor.labelColor;
        [m_Icon setFrameSize:image.size];
    }
    self.needsLayout = YES;
}

- (void)dealloc
{
    [_onPress release];
    [m_Icon release];
    [m_Label release];
    [m_Trailing release];
    [m_Tracking release];
    [super dealloc];
}

- (void)setTitle:(NSAttributedString*)title
{
    m_Label.attributedStringValue = title;
    m_Label.hidden = title.length == 0;
    [m_Label sizeToFit];
    self.needsLayout = YES;
}

- (void)setTrailingImage:(NSImage*)image
{
    if (image == nil) {
        [m_Trailing removeFromSuperview];
        [m_Trailing release];
        m_Trailing = nil;
    }
    else {
        if (m_Trailing == nil) {
            m_Trailing = [[NSImageView alloc] initWithFrame:NSZeroRect];
            m_Trailing.imageScaling = NSImageScaleNone;
            [self addSubview:m_Trailing];
        }
        m_Trailing.image = image;
        [m_Trailing setFrameSize:image.size];
    }
    self.needsLayout = YES;
}

- (CGFloat)naturalWidth
{
    CGFloat width = 2 * k_ItemPadding;
    CGFloat iconWidth = m_Icon != nil ? NSWidth(m_Icon.frame) : 0;
    CGFloat labelWidth = m_Label.hidden ? 0 : NSWidth(m_Label.frame);
    CGFloat trailingWidth = m_Trailing != nil ? NSWidth(m_Trailing.frame) : 0;
    width += iconWidth + labelWidth + trailingWidth;
    if (iconWidth > 0 && labelWidth > 0) {
        width += k_ItemGap;
    }
    if (trailingWidth > 0 && (iconWidth > 0 || labelWidth > 0)) {
        width += k_TrailingGap;
    }
    return ceil(width);
}

- (CGFloat)iconOnlyWidth
{
    return ceil(2 * k_ItemPadding + (m_Icon != nil ? NSWidth(m_Icon.frame) : 0));
}

- (void)layout
{
    [super layout];
    NSSize size = self.bounds.size;
    CGFloat x = k_ItemPadding;
    if (m_Icon != nil) {
        NSSize iconSize = m_Icon.frame.size;
        [m_Icon setFrameOrigin:NSMakePoint(x, round((size.height - iconSize.height) / 2))];
        x += iconSize.width + k_ItemGap;
    }
    CGFloat trailingWidth = m_Trailing != nil ? NSWidth(m_Trailing.frame) : 0;
    if (m_Trailing != nil) {
        [m_Trailing setFrameOrigin:NSMakePoint(size.width - k_ItemPadding - trailingWidth,
                                               round((size.height - NSHeight(m_Trailing.frame)) / 2))];
    }
    if (!m_Label.hidden) {
        CGFloat labelHeight = NSHeight(m_Label.frame);
        CGFloat right = size.width - k_ItemPadding - (trailingWidth > 0 ? trailingWidth + k_TrailingGap : 0);
        m_Label.frame = NSMakeRect(x, round((size.height - labelHeight) / 2), MAX(right - x, 0), labelHeight);
    }
}

- (void)setOpen:(BOOL)open
{
    _open = open;
    [self setAccessibilityExpanded:open];
    [self updateHighlight];
}

- (void)setInteractive:(BOOL)interactive
{
    _interactive = interactive;
    [self setAccessibilityRole:interactive ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole];
    [self updateHighlight];
}

- (void)updateHighlight
{
    [self applyHighlight];
    self.needsDisplay = YES;
}

- (void)applyHighlight
{
    CGFloat alpha = _open ? 0.18 : (m_Hovered && _interactive ? 0.10 : 0);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.backgroundColor = white(alpha);
    self.layer.cornerRadius = 6;
    [CATransaction commit];
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    [self applyHighlight];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (m_Tracking != nil) {
        [self removeTrackingArea:m_Tracking];
        [m_Tracking release];
    }
    // Always active: the bar's panel is never key
    m_Tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                owner:self
                                             userInfo:nil];
    [self addTrackingArea:m_Tracking];
}

- (void)mouseEntered:(NSEvent*)event
{
    (void)event;
    m_Hovered = YES;
    [self updateHighlight];
}

- (void)mouseExited:(NSEvent*)event
{
    (void)event;
    m_Hovered = NO;
    [self updateHighlight];
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent*)event
{
    (void)event;
    if (_interactive && _onPress != nil) {
        _onPress();
    }
}

- (BOOL)accessibilityPerformPress
{
    if (_interactive && _onPress != nil) {
        _onPress();
        return YES;
    }
    return NO;
}
@end

typedef NS_ENUM(NSInteger, ForkMenuControlKind) {
    ForkMenuControlHeader,      // the Session menu's title row
    ForkMenuControlRow,         // a menu row
    ForkMenuControlSeparator,
    ForkMenuControlToggle,      // a Control Center switch: a circle, a title and its state
    ForkMenuControlTile,        // a Control Center button: a circle and a title
    ForkMenuControlSwitch,      // a title and an on/off switch at the right, as in Quality
    ForkMenuControlSlider,      // a bitrate slider: dragged without a tracking loop, so the stream runs on
    ForkMenuControlChip,        // one choice of a segmented control, as Quality's frame rates
    ForkMenuControlPopup,       // a value in a capsule with up and down chevrons, its choices under it: Resolution
    ForkMenuControlModule,      // a Control Center tile with a circle and a title over a line: Trackpad, Notch Stats
    ForkMenuControlChoice,      // one choice of a list over the menu: a tick, its title, and ↻ if it reconnects
    ForkMenuControlButton,      // a push button: Stream Settings' Reset to Global, Save for Next Time and Apply
};

// What a control does in the menus themselves, rather than through an action: Stream Settings' draft
typedef NS_ENUM(NSInteger, ForkMenuLocal) {
    ForkMenuLocalNone,
    ForkMenuLocalPreset,        // a preset card (m_Value: 0 Office, 1 Gaming, 2 Custom)
    ForkMenuLocalRow,           // a row's capsule, which opens its choices (m_Value: the row)
    ForkMenuLocalPick,          // a choice in that list (m_Value: the row << 8 | the choice)
    ForkMenuLocalReset,         // Reset to Global
};

// A button's look
typedef NS_ENUM(NSInteger, ForkButtonStyle) {
    ForkButtonLink,             // blue text alone
    ForkButtonSecondary,        // grey
    ForkButtonPrimary,          // blue, white text
};

@class ForkNotchMenus;

@interface ForkNotchMenus ()
- (void)controlHovered:(NSView*)control;
- (void)controlUnhovered:(NSView*)control;
- (void)controlActivated:(NSView*)control;
// The slider moved to its value (while dragged), or was let go of there (final)
- (void)sliderMoved:(NSView*)control final:(BOOL)final;
// Up or down a step, from VoiceOver or the keyboard
- (void)slider:(NSView*)control step:(int)direction;
// Closes the list over the menu, as a click beside it does
- (void)closeList;
// Whether the pointer may light it: while a list is open, only the list's choices
- (BOOL)controlTakesPointer:(NSView*)control;
@end

// Behind a list over the menu: a click on it closes the list and goes no further, as beside a macOS menu
@interface ForkListScrim : NSView
{
@public
    ForkNotchMenus* m_Owner;    // not retained
}
@end

@implementation ForkListScrim
- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent*)event
{
    (void)event;
    [m_Owner closeList];
}
@end

// A row, switch or button in a menu
@interface ForkMenuControl : NSView
{
@public
    ForkMenuControlKind m_Kind;
    NotchMenus::Action m_Action;
    BOOL m_Enabled;
    BOOL m_On;
    BOOL m_Selected;
    BOOL m_KeyboardSelected;    // shows a focus ring, as the keyboard got here
    BOOL m_Hovered;
    BOOL m_Pressed;

    // A slider's range, in kbps
    int m_MinKbps;
    int m_MaxKbps;
    int m_StepKbps;
    int m_ValueKbps;
    BOOL m_Dragging;
    CGFloat m_GrabOffset;       // where on the knob the drag took it, so taking it doesn't move it
    BOOL m_ReadOnly;            // only shows the value, as Control Center's Bitrate does
    int m_Value;                // what the action carries, as a frame rate; 0 for nothing
    ForkMenuLocal m_Local;      // what it does in the menus themselves, for Stream Settings
    ForkButtonStyle m_ButtonStyle;
}
- (instancetype)initWithKind:(ForkMenuControlKind)kind owner:(ForkNotchMenus*)owner;
- (void)setTitle:(NSString*)title detail:(NSString*)detail symbol:(NSString*)name;
// The width a row or header needs for its title and shortcut
- (CGFloat)naturalWidth;
// A Control Center switch's or tile's height at this width, its line under the title on two lines if
// it needs them
- (CGFloat)heightForWidth:(CGFloat)width;
// A choice's tick, and ↻ when choosing it reconnects the stream
- (void)setChecked:(BOOL)checked reconnects:(BOOL)reconnects;
- (void)refreshAppearance;
// Out of the open menu: AppKit may still send it events until its panel goes
- (void)detach;
@end

@implementation ForkMenuControl
{
    ForkNotchMenus* m_Owner;    // not retained: it owns the menu
    NSView* m_Circle;
    NSImageView* m_Icon;
    NSTextField* m_Title;
    NSTextField* m_Detail;      // a row's shortcut, or a switch's state
    NSImageView* m_Badge;       // a choice's ↻
    NSTrackingArea* m_Tracking;
}

- (instancetype)initWithKind:(ForkMenuControlKind)kind owner:(ForkNotchMenus*)owner
{
    self = [super initWithFrame:NSZeroRect];
    if (self == nil) {
        return nil;
    }

    m_Kind = kind;
    m_Owner = owner;
    m_Enabled = YES;
    m_StepKbps = 500;
    self.wantsLayer = YES;

    switch (kind) {
    case ForkMenuControlHeader:
        m_Title = [makeText(@"", [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor) retain];
        [self addSubview:m_Title];
        break;
    case ForkMenuControlRow:
        self.layer.cornerRadius = 6;
        m_Title = [makeText(@"", [NSFont menuFontOfSize:13], NSColor.labelColor) retain];
        m_Detail = [makeText(@"", [NSFont menuFontOfSize:13], NSColor.secondaryLabelColor) retain];
        m_Detail.alignment = NSTextAlignmentRight;
        [self addSubview:m_Title];
        [self addSubview:m_Detail];
        break;
    case ForkMenuControlSeparator:
        break;
    case ForkMenuControlToggle:
    case ForkMenuControlTile:
    case ForkMenuControlModule:
        self.layer.cornerRadius = kind == ForkMenuControlToggle ? 8 : 16;
        m_Circle = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, k_Circle, k_Circle)];
        m_Circle.wantsLayer = YES;
        m_Circle.layer.cornerRadius = k_Circle / 2;
        m_Icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        m_Icon.imageScaling = NSImageScaleNone;
        [m_Circle addSubview:m_Icon];
        [self addSubview:m_Circle];
        m_Title = [makeText(@"", [NSFont systemFontOfSize:kind == ForkMenuControlTile ? 12 : 13
                                                     weight:kind == ForkMenuControlTile ? NSFontWeightRegular : NSFontWeightSemibold],
                            NSColor.labelColor) retain];
        [self addSubview:m_Title];
        if (kind == ForkMenuControlTile) {
            m_Title.alignment = NSTextAlignmentCenter;
            m_Title.maximumNumberOfLines = 2;
            m_Title.lineBreakMode = NSLineBreakByWordWrapping;
            m_Title.cell.wraps = YES;
            m_Title.cell.scrollable = NO;
            m_Title.cell.usesSingleLineMode = NO;
        }
        else {
            // Two lines when it needs them, at half Control Center's width
            m_Detail = [makeWrappingText([NSFont systemFontOfSize:12], NSColor.secondaryLabelColor) retain];
            [self addSubview:m_Detail];
        }
        break;
    case ForkMenuControlSwitch:
        self.layer.cornerRadius = 6;
        m_Title = [makeText(@"", [NSFont systemFontOfSize:13], NSColor.labelColor) retain];
        [self addSubview:m_Title];
        break;
    case ForkMenuControlSlider:
        self.layer.cornerRadius = 6;
        break;
    case ForkMenuControlChip:
        self.layer.cornerRadius = 5;
        m_Title = [makeText(@"", [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular], NSColor.labelColor) retain];
        m_Title.alignment = NSTextAlignmentCenter;
        [self addSubview:m_Title];
        break;
    case ForkMenuControlPopup:
        self.layer.cornerRadius = 6;
        m_Title = [makeText(@"", [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular], NSColor.labelColor) retain];
        [self addSubview:m_Title];
        m_Icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        m_Icon.imageScaling = NSImageScaleNone;
        m_Icon.contentTintColor = NSColor.labelColor;
        m_Icon.image = symbol(@"chevron.up.chevron.down", 9, NSFontWeightSemibold);
        [m_Icon setFrameSize:m_Icon.image != nil ? m_Icon.image.size : NSZeroSize];
        [self addSubview:m_Icon];
        break;
    case ForkMenuControlButton:
        self.layer.cornerRadius = 6;
        m_Title = [makeText(@"", [NSFont systemFontOfSize:13], NSColor.labelColor) retain];
        m_Title.alignment = NSTextAlignmentCenter;
        [self addSubview:m_Title];
        break;
    case ForkMenuControlChoice:
        self.layer.cornerRadius = 5;
        m_Icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        m_Icon.imageScaling = NSImageScaleNone;
        m_Icon.image = symbol(@"checkmark", 10, NSFontWeightSemibold);
        [m_Icon setFrameSize:m_Icon.image != nil ? m_Icon.image.size : NSZeroSize];
        [self addSubview:m_Icon];
        m_Title = [makeText(@"", [NSFont menuFontOfSize:13], NSColor.labelColor) retain];
        [self addSubview:m_Title];
        m_Badge = [[NSImageView alloc] initWithFrame:NSZeroRect];
        m_Badge.imageScaling = NSImageScaleNone;
        m_Badge.image = symbol(@"arrow.clockwise", 10, NSFontWeightMedium);
        [m_Badge setFrameSize:m_Badge.image != nil ? m_Badge.image.size : NSZeroSize];
        [self addSubview:m_Badge];
        break;
    }

    BOOL actionable = kind == ForkMenuControlRow || kind == ForkMenuControlToggle || kind == ForkMenuControlTile ||
                      kind == ForkMenuControlModule || kind == ForkMenuControlButton;
    [self setAccessibilityElement:kind != ForkMenuControlSeparator];
    [self setAccessibilityRole:kind == ForkMenuControlRow ? NSAccessibilityMenuItemRole :
                               kind == ForkMenuControlToggle || kind == ForkMenuControlSwitch ? NSAccessibilityCheckBoxRole :
                               kind == ForkMenuControlSlider ? NSAccessibilitySliderRole :
                               kind == ForkMenuControlChip || kind == ForkMenuControlChoice ? NSAccessibilityRadioButtonRole :
                               kind == ForkMenuControlPopup ? NSAccessibilityPopUpButtonRole :
                               actionable ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole];
    if (kind == ForkMenuControlToggle || kind == ForkMenuControlSwitch) {
        [self setAccessibilitySubrole:NSAccessibilitySwitchSubrole];
    }
    return self;
}

- (void)dealloc
{
    [m_Circle release];
    [m_Icon release];
    [m_Title release];
    [m_Detail release];
    [m_Badge release];
    [m_Tracking release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setTitle:(NSString*)title detail:(NSString*)detail symbol:(NSString*)name
{
    m_Title.stringValue = title != nil ? title : @"";
    m_Detail.stringValue = detail != nil ? detail : @"";
    if (m_Icon != nil && m_Kind != ForkMenuControlPopup && m_Kind != ForkMenuControlChoice) {
        m_Icon.image = symbol(name, 14, NSFontWeightMedium);
        [m_Icon setFrameSize:m_Icon.image != nil ? m_Icon.image.size : NSZeroSize];
    }
    // A switch's state is its value (on or off), so its label carries what that means
    [self setAccessibilityLabel:m_Kind == ForkMenuControlToggle && detail.length > 0 ?
                                    [NSString stringWithFormat:@"%@, %@", title, detail] : title];
    if (m_Kind == ForkMenuControlRow && detail.length > 0) {
        [self setAccessibilityHelp:detail];
    }
    [self setAccessibilityEnabled:m_Enabled];
    self.needsLayout = YES;
}

- (void)detach
{
    m_Owner = nil;
}

- (CGFloat)naturalWidth
{
    [m_Title sizeToFit];
    if (m_Kind == ForkMenuControlPopup) {
        // As on the canvas: 9 before the value, 6 between it and the chevrons, 6 after
        return ceil(9 + NSWidth(m_Title.frame) + 6 + NSWidth(m_Icon.frame) + 6);
    }
    if (m_Kind == ForkMenuControlChoice) {
        return ceil(24 + NSWidth(m_Title.frame) + 8 + (m_Badge.hidden ? 0 : 6 + NSWidth(m_Badge.frame)));
    }
    if (m_Kind == ForkMenuControlButton) {
        return ceil(NSWidth(m_Title.frame) + (m_ButtonStyle == ForkButtonLink ? 8 : 20));
    }
    CGFloat width = 18 + NSWidth(m_Title.frame);
    if (m_Detail != nil && m_Detail.stringValue.length > 0) {
        [m_Detail sizeToFit];
        width += 12 + NSWidth(m_Detail.frame);
    }
    return ceil(width);
}

- (CGFloat)heightForWidth:(CGFloat)width
{
    [m_Title sizeToFit];
    if (m_Kind == ForkMenuControlModule) {
        return 10 + k_Circle + 6 + NSHeight(m_Title.frame) + textHeight(m_Detail, MAX(width - 20, 0)) + 10;
    }
    CGFloat text = NSHeight(m_Title.frame) + textHeight(m_Detail, MAX(width - k_Circle - 9, 0));
    return MAX(k_ToggleHeight, ceil(text) + 5);
}

- (void)setChecked:(BOOL)checked reconnects:(BOOL)reconnects
{
    m_On = checked;
    m_Icon.hidden = !checked;
    m_Badge.hidden = !reconnects;
    [self setAccessibilityValue:checked ? @1 : @0];
    [self setAccessibilityHelp:reconnects ? tr("Reconnects the stream") : nil];
    self.needsLayout = YES;
}

- (void)layout
{
    [super layout];
    NSSize size = self.bounds.size;
    switch (m_Kind) {
    case ForkMenuControlHeader:
        [m_Title sizeToFit];
        m_Title.frame = NSMakeRect(9, round((size.height - NSHeight(m_Title.frame)) / 2), size.width - 18, NSHeight(m_Title.frame));
        break;
    case ForkMenuControlRow: {
        [m_Detail sizeToFit];
        [m_Title sizeToFit];
        CGFloat detailWidth = NSWidth(m_Detail.frame);
        m_Detail.frame = NSMakeRect(size.width - 9 - detailWidth, round((size.height - NSHeight(m_Detail.frame)) / 2),
                                    detailWidth, NSHeight(m_Detail.frame));
        CGFloat titleWidth = MAX(size.width - 18 - (detailWidth > 0 ? detailWidth + 12 : 0), 0);
        m_Title.frame = NSMakeRect(9, round((size.height - NSHeight(m_Title.frame)) / 2), titleWidth, NSHeight(m_Title.frame));
        break;
    }
    case ForkMenuControlSeparator:
        break;
    case ForkMenuControlToggle: {
        m_Circle.frame = NSMakeRect(0, round((size.height - k_Circle) / 2), k_Circle, k_Circle);
        [self centerIcon];
        [m_Title sizeToFit];
        CGFloat x = k_Circle + 9;
        CGFloat width = MAX(size.width - x, 0);
        CGFloat titleHeight = NSHeight(m_Title.frame);
        CGFloat detailHeight = textHeight(m_Detail, width);
        CGFloat top = round((size.height - titleHeight - detailHeight) / 2);
        m_Title.frame = NSMakeRect(x, top, width, titleHeight);
        m_Detail.frame = NSMakeRect(x, top + titleHeight, width, detailHeight);
        break;
    }
    case ForkMenuControlTile: {
        CGFloat titleHeight = 30;
        CGFloat top = round((size.height - k_Circle - 6 - titleHeight) / 2);
        m_Circle.frame = NSMakeRect(round((size.width - k_Circle) / 2), top, k_Circle, k_Circle);
        [self centerIcon];
        m_Title.frame = NSMakeRect(6, top + k_Circle + 6, MAX(size.width - 12, 0), titleHeight);
        break;
    }
    case ForkMenuControlSwitch: {
        [m_Title sizeToFit];
        m_Title.frame = NSMakeRect(9, round((size.height - NSHeight(m_Title.frame)) / 2), MAX(size.width - 18 - 32 - 9, 0),
                                   NSHeight(m_Title.frame));
        break;
    }
    case ForkMenuControlSlider:
        break;
    case ForkMenuControlChip: {
        [m_Title sizeToFit];
        m_Title.frame = NSMakeRect(0, round((size.height - NSHeight(m_Title.frame)) / 2), size.width, NSHeight(m_Title.frame));
        break;
    }
    case ForkMenuControlModule: {
        // As on the canvas: the circle at the top left, the title and its line under it
        m_Circle.frame = NSMakeRect(10, 10, k_Circle, k_Circle);
        [self centerIcon];
        CGFloat width = MAX(size.width - 20, 0);
        [m_Title sizeToFit];
        m_Title.frame = NSMakeRect(10, 10 + k_Circle + 6, width, NSHeight(m_Title.frame));
        m_Detail.frame = NSMakeRect(10, NSMaxY(m_Title.frame), width, textHeight(m_Detail, width));
        break;
    }
    case ForkMenuControlButton: {
        [m_Title sizeToFit];
        m_Title.frame = NSMakeRect(0, round((size.height - NSHeight(m_Title.frame)) / 2), size.width, NSHeight(m_Title.frame));
        break;
    }
    case ForkMenuControlChoice: {
        // The tick in a column of its own, the title, ↻ at the right
        NSSize check = m_Icon.frame.size;
        [m_Icon setFrameOrigin:NSMakePoint(round(4 + (16 - check.width) / 2), round((size.height - check.height) / 2))];
        NSSize badge = m_Badge.frame.size;
        [m_Badge setFrameOrigin:NSMakePoint(size.width - 8 - badge.width, round((size.height - badge.height) / 2))];
        [m_Title sizeToFit];
        CGFloat right = m_Badge.hidden ? size.width - 8 : NSMinX(m_Badge.frame) - 6;
        m_Title.frame = NSMakeRect(24, round((size.height - NSHeight(m_Title.frame)) / 2), MAX(right - 24, 0), NSHeight(m_Title.frame));
        break;
    }
    case ForkMenuControlPopup: {
        NSSize iconSize = m_Icon.frame.size;
        CGFloat iconX = size.width - 6 - iconSize.width;
        [m_Icon setFrameOrigin:NSMakePoint(iconX, round((size.height - iconSize.height) / 2))];
        [m_Title sizeToFit];
        m_Title.frame = NSMakeRect(9, round((size.height - NSHeight(m_Title.frame)) / 2), MAX(iconX - 6 - 9, 0), NSHeight(m_Title.frame));
        break;
    }
    }
}

// The switch at a switch row's right edge, as on the canvas: 32 by 19
- (NSRect)switchRect
{
    NSSize size = self.bounds.size;
    return NSMakeRect(size.width - 9 - 32, round((size.height - 19) / 2), 32, 19);
}

// Where the knob's centre runs, left to right
- (CGFloat)sliderLeft
{
    return k_Knob / 2;
}

- (CGFloat)sliderRight
{
    return NSWidth(self.bounds) - k_Knob / 2;
}

- (CGFloat)knobX
{
    int span = m_MaxKbps - m_MinKbps;
    double fraction = span > 0 ? static_cast<double>(m_ValueKbps - m_MinKbps) / span : 1;
    fraction = MAX(0.0, MIN(fraction, 1.0));
    return [self sliderLeft] + fraction * ([self sliderRight] - [self sliderLeft]);
}

- (void)setSliderFromEvent:(NSEvent*)event
{
    CGFloat x = [self convertPoint:event.locationInWindow fromView:nil].x - m_GrabOffset;
    CGFloat span = MAX([self sliderRight] - [self sliderLeft], 1);
    double fraction = MAX(0.0, MIN((x - [self sliderLeft]) / span, 1.0));
    NotchQuality::Range range;
    range.minKbps = m_MinKbps;
    range.maxKbps = m_MaxKbps;
    range.stepKbps = m_StepKbps;
    m_ValueKbps = NotchQuality::snap(static_cast<int>(lround(m_MinKbps + fraction * (m_MaxKbps - m_MinKbps))), range);
    [self setAccessibilityValue:@(m_ValueKbps / 1000.0)];
    self.needsDisplay = YES;
}

- (void)centerIcon
{
    NSSize iconSize = m_Icon.frame.size;
    [m_Icon setFrameOrigin:NSMakePoint(round((k_Circle - iconSize.width) / 2), round((k_Circle - iconSize.height) / 2))];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSColor* accent = NSColor.controlAccentColor;
    if (m_Kind == ForkMenuControlSeparator) {
        [[NSColor colorWithWhite:1 alpha:0.12] setFill];
        NSRectFill(NSMakeRect(9, round(NSHeight(self.bounds) / 2), NSWidth(self.bounds) - 18, 1));
    }
    else if (m_Kind == ForkMenuControlSwitch) {
        if (m_KeyboardSelected && m_Selected) {
            NSBezierPath* ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:6 yRadius:6];
            ring.lineWidth = 2;
            [accent setStroke];
            [ring stroke];
        }
        // The switch, dimmed while it can't be used, its knob at the right while on
        [NSGraphicsContext saveGraphicsState];
        CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, m_Enabled ? 1 : 0.45);
        NSRect track = [self switchRect];
        [(m_On ? accent : [NSColor colorWithWhite:1 alpha:0.22]) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:track xRadius:NSHeight(track) / 2 yRadius:NSHeight(track) / 2] fill];
        NSShadow* shadow = [[[NSShadow alloc] init] autorelease];
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
        shadow.shadowOffset = NSMakeSize(0, -1);
        shadow.shadowBlurRadius = 2;
        [shadow set];
        [NSColor.whiteColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(track) + 2 + (m_On ? 13 : 0), NSMinY(track) + 2, 15, 15)] fill];
        [NSGraphicsContext restoreGraphicsState];
    }
    else if (m_Kind == ForkMenuControlSlider) {
        if (m_KeyboardSelected && m_Selected) {
            NSBezierPath* ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:6 yRadius:6];
            ring.lineWidth = 2;
            [accent setStroke];
            [ring stroke];
        }
        CGFloat mid = round(NSHeight(self.bounds) / 2);
        CGFloat left = [self sliderLeft];
        CGFloat right = [self sliderRight];
        CGFloat knob = [self knobX];
        // The track, filled up to the knob
        [[NSColor colorWithWhite:1 alpha:0.22] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(left, mid - 2, right - left, 4) xRadius:2 yRadius:2] fill];
        [accent setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(left, mid - 2, MAX(knob - left, 0), 4) xRadius:2 yRadius:2] fill];
        [NSGraphicsContext saveGraphicsState];
        NSShadow* shadow = [[[NSShadow alloc] init] autorelease];
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
        shadow.shadowOffset = NSMakeSize(0, -1);
        shadow.shadowBlurRadius = 2;
        [shadow set];
        [NSColor.whiteColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(knob - k_Knob / 2, mid - k_Knob / 2, k_Knob, k_Knob)] fill];
        [NSGraphicsContext restoreGraphicsState];
    }
}

- (BOOL)wantsUpdateLayer
{
    // The switch and the slider draw themselves
    return m_Kind != ForkMenuControlSeparator && m_Kind != ForkMenuControlSwitch && m_Kind != ForkMenuControlSlider;
}

- (void)updateLayer
{
    [self refreshAppearance];
}

// Shows the state: selection, hover, pressed, on, enabled
- (void)refreshAppearance
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    NSColor* accent = NSColor.controlAccentColor;
    switch (m_Kind) {
    case ForkMenuControlRow: {
        BOOL lit = m_Selected && m_Enabled;
        self.layer.backgroundColor = lit ? accent.CGColor : CGColorGetConstantColor(kCGColorClear);
        m_Title.textColor = !m_Enabled ? NSColor.tertiaryLabelColor : (lit ? NSColor.whiteColor : NSColor.labelColor);
        m_Detail.textColor = lit ? [NSColor colorWithWhite:1 alpha:0.85] : NSColor.secondaryLabelColor;
        break;
    }
    case ForkMenuControlToggle:
    case ForkMenuControlTile:
    case ForkMenuControlModule: {
        CGFloat background = m_Kind != ForkMenuControlToggle ? (m_Pressed ? 0.20 : (m_Hovered ? 0.12 : 0.08))
                                                             : (m_Pressed ? 0.12 : (m_Hovered ? 0.06 : 0));
        self.layer.backgroundColor = white(background);
        self.layer.borderWidth = m_KeyboardSelected && m_Selected ? 2 : 0;
        self.layer.borderColor = accent.CGColor;
        BOOL filled = m_Kind != ForkMenuControlTile && m_On;
        m_Circle.layer.backgroundColor = filled ? accent.CGColor : white(0.14);
        m_Icon.contentTintColor = filled ? NSColor.whiteColor : NSColor.labelColor;
        self.alphaValue = m_Enabled ? 1 : 0.45;
        break;
    }
    case ForkMenuControlSwitch:
        // No highlight, as on the canvas: the switch shows its state
        self.needsDisplay = YES;
        break;
    case ForkMenuControlSlider:
        self.alphaValue = m_ReadOnly ? 0.55 : (m_Enabled ? 1 : 0.45);
        self.needsDisplay = YES;
        break;
    case ForkMenuControlChip:
        // The chosen one lit, as on the canvas; the pointer's lighter
        self.layer.backgroundColor = white(m_On ? 0.24 : (m_Pressed ? 0.16 : (m_Hovered ? 0.10 : 0)));
        self.layer.borderWidth = m_KeyboardSelected && m_Selected ? 2 : 0;
        self.layer.borderColor = accent.CGColor;
        break;
    case ForkMenuControlButton: {
        // As on the canvas: Reset to Global blue text, Save for Next Time grey, Apply blue
        NSColor* blue = [NSColor colorWithSRGBRed:0x0a / 255.0 green:0x84 / 255.0 blue:1 alpha:1];
        CGColorRef background = CGColorGetConstantColor(kCGColorClear);
        if (m_ButtonStyle == ForkButtonPrimary) {
            background = (m_Pressed ? [blue blendedColorWithFraction:0.25 ofColor:NSColor.blackColor] : blue).CGColor;
        }
        else if (m_ButtonStyle == ForkButtonSecondary) {
            background = white(m_Pressed ? 0.22 : 0.14);
        }
        else if (m_Pressed || (m_Hovered && m_Enabled)) {
            background = white(0.08);
        }
        self.layer.backgroundColor = background;
        m_Title.textColor = m_ButtonStyle == ForkButtonLink ? [NSColor colorWithSRGBRed:0x4d / 255.0 green:0xa3 / 255.0 blue:1 alpha:1]
                                                            : (m_ButtonStyle == ForkButtonPrimary ? NSColor.whiteColor : NSColor.labelColor);
        m_Title.font = [NSFont systemFontOfSize:13 weight:m_ButtonStyle == ForkButtonPrimary ? NSFontWeightMedium : NSFontWeightRegular];
        self.layer.borderWidth = m_KeyboardSelected && m_Selected ? 2 : 0;
        self.layer.borderColor = (m_ButtonStyle == ForkButtonPrimary ? NSColor.whiteColor : accent).CGColor;
        self.alphaValue = m_Enabled ? 1 : 0.45;
        break;
    }
    case ForkMenuControlChoice: {
        // As a menu's rows: the accent under the pointer or the keyboard
        BOOL lit = m_Selected && m_Enabled;
        self.layer.backgroundColor = lit ? accent.CGColor : CGColorGetConstantColor(kCGColorClear);
        NSColor* text = !m_Enabled ? NSColor.tertiaryLabelColor : (lit ? NSColor.whiteColor : NSColor.labelColor);
        m_Title.textColor = text;
        m_Icon.contentTintColor = text;
        m_Badge.contentTintColor = lit ? [NSColor colorWithWhite:1 alpha:0.85] : NSColor.secondaryLabelColor;
        break;
    }
    case ForkMenuControlPopup:
        // The canvas's 0.12, lighter under the pointer and while its choices are open
        self.layer.backgroundColor = white(m_Pressed ? 0.24 : (m_On || m_Hovered ? 0.18 : 0.12));
        self.layer.borderWidth = m_KeyboardSelected && m_Selected ? 2 : 0;
        self.layer.borderColor = accent.CGColor;
        break;
    default:
        break;
    }

    [CATransaction commit];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (m_Tracking != nil) {
        [self removeTrackingArea:m_Tracking];
        [m_Tracking release];
        m_Tracking = nil;
    }
    if (m_Kind == ForkMenuControlHeader || m_Kind == ForkMenuControlSeparator) {
        return;
    }
    m_Tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                owner:self
                                             userInfo:nil];
    [self addTrackingArea:m_Tracking];
}

- (void)mouseEntered:(NSEvent*)event
{
    (void)event;
    m_Hovered = [m_Owner controlTakesPointer:self];
    [m_Owner controlHovered:self];
    [self refreshAppearance];
}

- (void)mouseExited:(NSEvent*)event
{
    (void)event;
    m_Hovered = NO;
    m_Pressed = NO;
    [m_Owner controlUnhovered:self];
    [self refreshAppearance];
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent*)event
{
    if (m_Kind == ForkMenuControlSlider) {
        // AppKit sends this view the drags that follow, outside it too, with no tracking loop of its own.
        // Taken by the knob, it stays where it is until dragged; elsewhere on the track it jumps there.
        if (m_Enabled && !m_ReadOnly) {
            m_Dragging = YES;
            CGFloat offset = [self convertPoint:event.locationInWindow fromView:nil].x - [self knobX];
            if (fabs(offset) <= k_Knob / 2) {
                m_GrabOffset = offset;
            }
            else {
                m_GrabOffset = 0;
                [self setSliderFromEvent:event];
            }
            [m_Owner sliderMoved:self final:NO];
        }
        return;
    }
    m_Pressed = m_Enabled && m_Kind != ForkMenuControlHeader && m_Kind != ForkMenuControlSeparator;
    [self refreshAppearance];
}

- (void)mouseDragged:(NSEvent*)event
{
    if (m_Kind == ForkMenuControlSlider && m_Dragging) {
        [self setSliderFromEvent:event];
        [m_Owner sliderMoved:self final:NO];
    }
}

- (void)mouseUp:(NSEvent*)event
{
    if (m_Kind == ForkMenuControlSlider) {
        // Where the last drag left it
        if (m_Dragging) {
            m_Dragging = NO;
            [m_Owner sliderMoved:self final:YES];
        }
        return;
    }
    BOOL inside = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    BOOL pressed = m_Pressed;
    m_Pressed = NO;
    [self refreshAppearance];
    if (pressed && inside) {
        [m_Owner controlActivated:self];
    }
}

- (BOOL)accessibilityPerformPress
{
    if (!m_Enabled || m_Kind == ForkMenuControlHeader || m_Kind == ForkMenuControlSeparator || m_Kind == ForkMenuControlSlider) {
        return NO;
    }
    [m_Owner controlActivated:self];
    return YES;
}

- (BOOL)accessibilityPerformIncrement
{
    if (m_Kind != ForkMenuControlSlider || !m_Enabled || m_ReadOnly) {
        return NO;
    }
    [m_Owner slider:self step:1];
    return YES;
}

- (BOOL)accessibilityPerformDecrement
{
    if (m_Kind != ForkMenuControlSlider || !m_Enabled || m_ReadOnly) {
        return NO;
    }
    [m_Owner slider:self step:-1];
    return YES;
}
@end

@implementation ForkNotchMenus
{
    id<ForkNotchMenusHost> m_Host;   // not retained: the bar owns the menus
    NSString* m_AppName;
    NSString* m_HostName;
    NotchMenus::Menu m_Open;
    ForkMenuPanel* m_Panel;
    NSMutableArray<ForkMenuControl*>* m_Controls;
    int m_Selected;
    BOOL m_KeyboardSelection;
    id m_ClickMonitor;
    NSMutableSet<NSNumber*>* m_OwedReleases;   // keys whose press a menu took
    ForkStatusView* m_StatusView;   // Stream status's, while it's open; not retained: the panel holds it

    // Quality's, while it's open; not retained: the panel holds them
    NSView* m_QualityContent;
    NSTextField* m_QualityTitle;
    NSTextField* m_QualityValue;    // "18 of 20 Mb/s"
    ForkMenuControl* m_AdaptSwitch;
    NSView* m_ReasonDot;
    NSTextField* m_Reason;
    ForkMenuControl* m_Slider;
    NSTextField* m_SliderLow;
    NSTextField* m_SliderHigh;
    NSTextField* m_Caption;
    NotchQuality::State m_Bitrate;  // what it shows
    // Quality's way to Stream Settings
    NSView* m_QualitySettingsLine;
    ForkMenuControl* m_QualitySettingsRow;
    // Stream Settings' contents, from the bar (ForkStreamSettings); m_Opening while its panel opens,
    // so the draft starts again from what the stream applied
    ForkStreamSettings::View m_SettingsView;
    BOOL m_Opening;
    // Quality's Stream Battery Saver note, and its reconnect on a PC that can't change the bitrate live
    NSView* m_SaverBox;
    NSTextField* m_SaverText;
    ForkMenuControl* m_SaverReconnect;
    // Quality's frame rates and resolutions, which reconnect
    NSView* m_QualityLine;
    NSTextField* m_FpsTitle;
    NSView* m_FpsGroup;
    NSTextField* m_ResolutionTitle;
    ForkMenuControl* m_ResolutionButton;
    NSMutableArray<ForkMenuControl*>* m_ResolutionChoices;  // not retained either: shown while m_ResolutionsShown
    NSTextField* m_ReconnectCaption;
    BOOL m_ResolutionsShown;
    // Battery's reconnect at the saver's cap
    ForkMenuControl* m_BatteryReconnect;
    // A list over the open menu, as Control Center's Trackpad opens: only its choices take the pointer
    // and the keys while it's open. Not retained either: the content holds them.
    ForkListScrim* m_ListScrim;
    NSView* m_ListView;
    NSUInteger m_ListFirst;         // its choices' place in m_Controls
    ForkMenuControl* m_ListOpener;  // selected again once it closes
    ForkMenuControl* m_TrackpadTile;
    // Control Center's bitrate, while it's open; not retained either
    NSTextField* m_BitrateTileDetail;
    ForkMenuControl* m_BitrateTileBar;
    // Battery's, while it's open; not retained either
    NSView* m_BatteryContent;
    ForkBatteryView* m_BatteryView;
    NSView* m_BatteryLines[2];
    ForkMenuControl* m_SaverSwitch;
    NSTextField* m_SaverCaptions[2];
    ForkMenuControl* m_BatterySettingsRow;
    // The bitrate the slider was let go at, shown until the PC runs at it, or for k_HeldSeconds
    int m_HeldKbps;
    CFTimeInterval m_HeldUntil;
}

- (instancetype)initWithHost:(id<ForkNotchMenusHost>)host appName:(NSString*)appName hostName:(NSString*)hostName
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    m_Host = host;
    m_AppName = [appName copy];
    m_HostName = [hostName copy];
    m_Open = NotchMenus::Menu::None;
    m_Controls = [[NSMutableArray alloc] init];
    m_Selected = -1;
    m_OwedReleases = [[NSMutableSet alloc] init];
    return self;
}

- (void)dealloc
{
    [m_AppName release];
    [m_HostName release];
    [m_ResolutionChoices release];
    [m_Panel release];
    [m_Controls release];
    [m_OwedReleases release];
    [super dealloc];
}

- (NotchMenus::Menu)openMenu
{
    return m_Open;
}

- (void)invalidate
{
    [self closeQuietly];
    m_Host = nil;
}

// Builds the open menu's controls into a new content view, and returns its size
- (NSView*)buildContent:(NSSize*)size
{
    [self dropControls];
    NotchBar::MenuState state = m_Host != nil ? [m_Host menusState] : NotchBar::MenuState();

    ForkFlippedView* content = [[[ForkFlippedView alloc] initWithFrame:NSZeroRect] autorelease];

    if (m_Open == NotchMenus::Menu::Session) {
        auto add = [&](ForkMenuControlKind kind, NSString* title, NSString* detail, NotchMenus::Action action, BOOL enabled) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:kind owner:self] autorelease];
            control->m_Action = action;
            control->m_Enabled = enabled;
            [control setTitle:title detail:detail symbol:nil];
            [content addSubview:control];
            [m_Controls addObject:control];
        };
        QString app = shortName(m_AppName);
        add(ForkMenuControlHeader,
            QCoreApplication::translate("NotchBar", "%1 on %2").arg(app, QString::fromNSString(m_HostName)).toNSString(),
            nil, NotchMenus::Action::None, NO);
        add(ForkMenuControlRow, tr("Disconnect"), @"⌃⌥⇧Q", NotchMenus::Action::Disconnect, YES);
        add(ForkMenuControlRow, tr("Disconnect and Quit LuzLunar"), nil, NotchMenus::Action::DisconnectAndQuitLuzLunar, YES);
        add(ForkMenuControlSeparator, nil, nil, NotchMenus::Action::None, NO);
        add(ForkMenuControlRow, QCoreApplication::translate("NotchBar", "Quit %1 on PC").arg(app).toNSString(),
            nil, NotchMenus::Action::QuitAppOnPc, YES);
        add(ForkMenuControlRow, QCoreApplication::translate("NotchBar", "Quit %1 and Sleep PC").arg(app).toNSString(),
            nil, NotchMenus::Action::QuitAndSleepPc, state.canSleepPc);
        add(ForkMenuControlSeparator, nil, nil, NotchMenus::Action::None, NO);
        add(ForkMenuControlRow, tr("Reconnect"), nil, NotchMenus::Action::Reconnect, YES);
        add(ForkMenuControlRow, QCoreApplication::translate("NotchBar", "Stream Settings for %1…").arg(app).toNSString(), nil,
            NotchMenus::Action::OpenStreamSettings, YES);

        // As wide as its widest row, like macOS's menus, within limits
        CGFloat width = k_SessionWidth - 2 * k_SessionPadding;
        for (ForkMenuControl* control in m_Controls) {
            if (control->m_Kind != ForkMenuControlSeparator) {
                width = MAX(width, [control naturalWidth]);
            }
        }
        width = MIN(width, k_SessionMaxWidth - 2 * k_SessionPadding);
        CGFloat y = k_SessionPadding;
        for (ForkMenuControl* control in m_Controls) {
            CGFloat height = control->m_Kind == ForkMenuControlHeader ? k_HeaderHeight :
                             control->m_Kind == ForkMenuControlSeparator ? k_SeparatorHeight : k_RowHeight;
            control.frame = NSMakeRect(k_SessionPadding, y, width, height);
            y += height;
        }
        *size = NSMakeSize(width + 2 * k_SessionPadding, y + k_SessionPadding);
    }
    else if (m_Open == NotchMenus::Menu::Status) {
        // The status above, the two rows below: only the rows take the keyboard and choose
        CGFloat width = k_StatusWidth - 2 * k_StatusPadding;
        ForkStatusView* status = [[[ForkStatusView alloc] initWithWidth:width] autorelease];
        [status setFrameOrigin:NSMakePoint(k_StatusPadding, k_StatusPadding)];
        [content addSubview:status];
        m_StatusView = status;
        [self statusChanged];
        CGFloat y = k_StatusPadding + NSHeight(status.frame);
        auto addRow = [&](NSString* title, NSString* detail, NotchMenus::Action action) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlRow owner:self] autorelease];
            control->m_Action = action;
            [control setTitle:title detail:detail symbol:nil];
            control.frame = NSMakeRect(k_StatusPadding, y, width, k_RowHeight);
            [content addSubview:control];
            [m_Controls addObject:control];
            y += k_RowHeight;
        };
        addRow(state.statsOverlayShown ? tr("Hide Stats Overlay") : tr("Show Stats Overlay"), @"⌃⌥⇧S",
               NotchMenus::Action::ToggleStatsOverlay);
        addRow(tr("Copy Diagnostics"), nil, NotchMenus::Action::CopyDiagnostics);
        *size = NSMakeSize(k_StatusWidth, y + k_StatusPadding);
    }
    else if (m_Open == NotchMenus::Menu::Quality) {
        [self buildQuality:content state:state];
        *size = NSMakeSize(k_QualityWidth, [self layoutQuality]);
    }
    else if (m_Open == NotchMenus::Menu::Battery) {
        [self buildBattery:content];
        *size = NSMakeSize(k_BatteryWidth, [self layoutBattery:state]);
    }
    else if (m_Open == NotchMenus::Menu::StreamSettings) {
        [self buildStreamSettings:content size:size];
    }
    else if (m_Open == NotchMenus::Menu::ControlCenter) {
        CGFloat width = k_CenterWidth - 2 * k_CenterPadding;
        CGFloat y = k_CenterPadding;

        // As on the canvas, in two columns: the switches in one tall tile at the left, Trackpad and
        // Notch Stats at the right
        CGFloat column = floor((width - k_TileGap) / 2);
        NSView* group = [[[ForkFlippedView alloc] initWithFrame:NSZeroRect] autorelease];
        group.wantsLayer = YES;
        group.layer.cornerRadius = 16;
        group.layer.backgroundColor = white(0.08);
        [content addSubview:group];
        NSMutableArray<ForkMenuControl*>* toggles = [NSMutableArray array];
        auto addToggle = [&](NSString* title, NSString* detail, NSString* name, BOOL on, NotchMenus::Action action, BOOL enabled) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlToggle owner:self] autorelease];
            control->m_Action = action;
            control->m_On = on;
            control->m_Enabled = enabled;
            [control setTitle:title detail:detail symbol:name];
            [control setAccessibilityValue:on ? @1 : @0];
            [group addSubview:control];
            [m_Controls addObject:control];
            [toggles addObject:control];
        };
        // Automatic for this stream, or by shortcut; greyed when the PC can't sync
        using Clipboard = NotchBar::MenuState::Clipboard;
        bool clipboardUsable = state.clipboard == Clipboard::Available || state.clipboard == Clipboard::Unknown;
        NSString* clipboardDetail = state.clipboard == Clipboard::OffInSettings ? tr("Off in Settings") :
                                    state.clipboard == Clipboard::NeedsApollo   ? tr("Needs Apollo") :
                                    state.clipboard == Clipboard::NotAllowed    ? tr("Not allowed in Apollo") :
                                    state.clipboardAutomatic                     ? tr("Automatic") : tr("With ⌃⌥⇧U and ⌃⌥⇧G");
        addToggle(tr("Clipboard Sync"), clipboardDetail, @"doc.on.clipboard", clipboardUsable && state.clipboardAutomatic,
                  NotchMenus::Action::ToggleClipboardSync, clipboardUsable);
        addToggle(tr("Mac Shortcuts"), state.systemKeysToPc ? tr("Sent to the PC") : tr("Kept on the Mac"),
                  @"keyboard", state.systemKeysToPc, NotchMenus::Action::ToggleSystemKeys, YES);
        addToggle(tr("Mouse"), state.mouseCaptured ? tr("Captured · ⌃⌥⇧Z") : tr("Free · ⌃⌥⇧Z"),
                  @"cursorarrow", state.mouseCaptured, NotchMenus::Action::ToggleMouseCapture, YES);

        // Trackpad opens its modes (openTrackpadList); Notch Stats switches the bar's stats text
        m_TrackpadTile = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlModule owner:self] autorelease];
        m_TrackpadTile->m_On = YES;
        // A trackpad with a hand on it; an older macOS's symbols have the hand alone
        NSString* trackpadSymbol = symbol(@"rectangle.and.hand.point.up.left", 14, NSFontWeightMedium) != nil ? @"rectangle.and.hand.point.up.left"
                                                                                                          : @"hand.point.up.left";
        [m_TrackpadTile setTitle:tr("Trackpad") detail:trackpadModeTitle(state.trackpadMode) symbol:trackpadSymbol];
        [m_TrackpadTile setAccessibilityRole:NSAccessibilityPopUpButtonRole];
        [m_TrackpadTile setAccessibilityLabel:QCoreApplication::translate("NotchBar", "Trackpad mode: %1")
                                                  .arg(QString::fromNSString(trackpadModeTitle(state.trackpadMode))).toNSString()];
        [m_TrackpadTile setAccessibilityExpanded:NO];
        ForkMenuControl* stats = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlModule owner:self] autorelease];
        stats->m_Action = NotchMenus::Action::ToggleNotchStats;
        stats->m_On = state.notchStatsShown;
        [stats setTitle:tr("Notch Stats") detail:state.notchStatsShown ? tr("Shown") : tr("Hidden") symbol:@"chart.bar.fill"];
        [stats setAccessibilityRole:NSAccessibilityCheckBoxRole];
        [stats setAccessibilitySubrole:NSAccessibilitySwitchSubrole];
        [stats setAccessibilityValue:state.notchStatsShown ? @1 : @0];
        for (ForkMenuControl* tile in @[ m_TrackpadTile, stats ]) {
            [content addSubview:tile];
            [m_Controls addObject:tile];
        }

        // The tall tile's switches as tall as they need, the two at the right as tall as each other;
        // whichever side is shorter grows to the other, its switches spread out as on the canvas
        CGFloat toggleWidth = column - 20;
        CGFloat togglesHeight = 0;
        for (ForkMenuControl* toggle in toggles) {
            togglesHeight += [toggle heightForWidth:toggleWidth];
        }
        CGFloat leftHeight = 10 + togglesHeight + 8 * (toggles.count - 1) + 10;
        CGFloat moduleHeight = MAX([m_TrackpadTile heightForWidth:column], [stats heightForWidth:column]);
        CGFloat gridHeight = MAX(leftHeight, 2 * moduleHeight + k_TileGap);
        moduleHeight = floor((gridHeight - k_TileGap) / 2);
        CGFloat spread = toggles.count > 1 ? (gridHeight - leftHeight) / (toggles.count - 1) : 0;
        CGFloat toggleY = 10;
        for (ForkMenuControl* toggle in toggles) {
            CGFloat height = [toggle heightForWidth:toggleWidth];
            toggle.frame = NSMakeRect(10, round(toggleY), toggleWidth, height);
            toggleY += height + 8 + spread;
        }
        group.frame = NSMakeRect(k_CenterPadding, y, column, gridHeight);
        CGFloat right = k_CenterPadding + width - column;
        m_TrackpadTile.frame = NSMakeRect(right, y, column, moduleHeight);
        stats.frame = NSMakeRect(right, y + gridHeight - moduleHeight, column, moduleHeight);
        y += gridHeight + k_TileGap;

        // The bitrate, to look at: Quality changes it
        NSView* bitrate = [self bitrateTile:state.bitrate width:width];
        [bitrate setFrameOrigin:NSMakePoint(k_CenterPadding, y)];
        [content addSubview:bitrate];
        y += NSHeight(bitrate.frame) + k_TileGap;

        // This Mac as a drive on the PC, while it is one
        if (state.driveMapped) {
            NSView* drive = [self driveTile:state width:width];
            [drive setFrameOrigin:NSMakePoint(k_CenterPadding, y)];
            [content addSubview:drive];
            y += NSHeight(drive.frame) + k_TileGap;
        }

        // The session's buttons, three across
        CGFloat tileWidth = floor((width - 2 * k_TileGap) / 3);
        struct Tile {
            NSString* title;
            NSString* symbol;
            NotchMenus::Action action;
            BOOL enabled;
        };
        Tile tiles[] = {
            { tr("Disconnect"), @"rectangle.portrait.and.arrow.right", NotchMenus::Action::Disconnect, YES },
            { tr("Quit App"), @"stop.fill", NotchMenus::Action::QuitAppOnPc, YES },
            { tr("Quit and Sleep PC"), @"power", NotchMenus::Action::QuitAndSleepPc, state.canSleepPc },
        };
        for (int i = 0; i < 3; i++) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlTile owner:self] autorelease];
            control->m_Action = tiles[i].action;
            control->m_Enabled = tiles[i].enabled;
            [control setTitle:tiles[i].title detail:nil symbol:tiles[i].symbol];
            control.frame = NSMakeRect(k_CenterPadding + i * (tileWidth + k_TileGap), y, tileWidth, k_ActionTileHeight);
            [content addSubview:control];
            [m_Controls addObject:control];
        }
        y += k_ActionTileHeight + k_CenterPadding;
        *size = NSMakeSize(k_CenterWidth, y);
    }

    content.frame = NSMakeRect(0, 0, size->width, size->height);
    return content;
}

- (BOOL)selectable:(int)index
{
    if (index < 0 || index >= (int)m_Controls.count) {
        return NO;
    }
    if (m_ListView != nil && (NSUInteger)index < m_ListFirst) {
        return NO;
    }
    ForkMenuControl* control = m_Controls[(NSUInteger)index];
    return control->m_Enabled && control->m_Kind != ForkMenuControlHeader && control->m_Kind != ForkMenuControlSeparator;
}

- (void)select:(int)index keyboard:(BOOL)keyboard
{
    m_Selected = index;
    m_KeyboardSelection = keyboard;
    for (NSUInteger i = 0; i < m_Controls.count; i++) {
        ForkMenuControl* control = m_Controls[i];
        control->m_Selected = (int)i == index;
        control->m_KeyboardSelected = keyboard;
        [control refreshAppearance];
    }
}

- (void)open:(NotchMenus::Menu)menu keyboard:(BOOL)keyboard
{
    BOOL alignRight = NO;
    NSRect anchor = menu != NotchMenus::Menu::None && m_Host != nil ? [m_Host menusAnchorFor:menu alignRight:&alignRight] : NSZeroRect;
    if (NSIsEmptyRect(anchor)) {
        // Nothing to hang it from: the item isn't on screen
        [self close];
        return;
    }
    [self removePanel];
    m_Open = menu;
    m_Selected = -1;

    NSSize size;
    m_Opening = YES;
    NSView* content = [self buildContent:&size];
    m_Opening = NO;

    // A new panel each time: one shown before belongs to the Space it was shown on, and a new one
    // joins the stream's
    m_Panel = [[ForkMenuPanel alloc] initWithContentRect:NSZeroRect
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    m_Panel.releasedWhenClosed = NO;
    m_Panel.opaque = NO;
    m_Panel.backgroundColor = NSColor.clearColor;
    m_Panel.hasShadow = YES;
    m_Panel.hidesOnDeactivate = NO;
    m_Panel.becomesKeyOnlyIfNeeded = YES;
    m_Panel.acceptsMouseMovedEvents = YES;
    // Above the bar
    m_Panel.level = NSMainMenuWindowLevel + 3;
    m_Panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary |
                                 NSWindowCollectionBehaviorStationary |
                                 NSWindowCollectionBehaviorIgnoresCycle;
    m_Panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];

    NSVisualEffectView* effect = [[[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)] autorelease];
    effect.material = NSVisualEffectMaterialMenu;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = menu == NotchMenus::Menu::ControlCenter ? 22 :
                                menu == NotchMenus::Menu::Status || menu == NotchMenus::Menu::Quality ||
                                menu == NotchMenus::Menu::Battery || menu == NotchMenus::Menu::StreamSettings ? 14 : 12;
    effect.layer.masksToBounds = YES;
    effect.layer.borderWidth = 1;
    effect.layer.borderColor = white(0.10);
    [effect addSubview:content];
    m_Panel.contentView = effect;

    [effect setAccessibilityElement:YES];
    [effect setAccessibilityRole:menu == NotchMenus::Menu::Session ? NSAccessibilityMenuRole : NSAccessibilityGroupRole];
    [effect setAccessibilityLabel:menu == NotchMenus::Menu::Session ? tr("Session") :
                                  menu == NotchMenus::Menu::Status  ? tr("Stream status") :
                                  menu == NotchMenus::Menu::Quality ? tr("Quality") :
                                  menu == NotchMenus::Menu::Battery ? tr("Battery") :
                                  menu == NotchMenus::Menu::StreamSettings ? m_SettingsView.title.toNSString() : tr("Stream Control Center")];

    // Under its item, kept on the screen
    NSScreen* screen = [m_Host menusBarWindow].screen;
    NSRect screenFrame = screen != nil ? screen.frame : NSMakeRect(0, 0, 10000, 10000);
    // Stream Settings is centred under the notch
    CGFloat x = menu == NotchMenus::Menu::StreamSettings ? round(NSMidX(anchor) - size.width / 2) :
                alignRight ? NSMaxX(anchor) - size.width : NSMinX(anchor);
    x = MAX(NSMinX(screenFrame) + k_ScreenMargin, MIN(x, NSMaxX(screenFrame) - k_ScreenMargin - size.width));
    CGFloat top = NSMinY(anchor) - k_MenuGap;
    [m_Panel setFrame:NSMakeRect(x, top - size.height, size.width, size.height) display:NO];
    [m_Panel orderFrontRegardless];

    if (keyboard) {
        [self select:NotchMenus::nextSelectable((int)m_Controls.count, -1, 1, [self](int i) { return [self selectable:i]; }) keyboard:YES];
    }

    // A click anywhere but the menu and the bar's items closes it. On the stream it goes no further:
    // not to the PC. The items open and close menus themselves.
    if (m_ClickMonitor == nil) {
        m_ClickMonitor = [[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown
                                                                handler:^NSEvent*(NSEvent* event) {
            if (m_Open == NotchMenus::Menu::None || event.window == m_Panel) {
                return event;
            }
            NSWindow* bar = [m_Host menusBarWindow];
            if (event.window != nil && event.window == bar) {
                if (![self barItemAt:event]) {
                    [self close];
                }
                return event;
            }
            [self close];
            return nil;
        }] retain];
    }

    [m_Host menusChanged:menu];
}

// Whether a click in the bar is on one of its items
- (BOOL)barItemAt:(NSEvent*)event
{
    NSView* root = event.window.contentView;
    NSPoint point = root.superview != nil ? [root.superview convertPoint:event.locationInWindow fromView:nil] : event.locationInWindow;
    for (NSView* view = [root hitTest:point]; view != nil; view = view.superview) {
        if ([view isKindOfClass:[ForkBarItem class]]) {
            return ((ForkBarItem*)view).interactive;
        }
    }
    return NO;
}

// Closes the panel without telling the bar
- (void)removePanel
{
    [m_Panel orderOut:nil];
    [m_Panel close];
    // Not released yet: this may run inside one of its controls' mouseUp:
    [m_Panel autorelease];
    m_Panel = nil;
    m_StatusView = nil;
    m_QualityContent = nil;
    m_QualityTitle = nil;
    m_QualityValue = nil;
    m_AdaptSwitch = nil;
    m_ReasonDot = nil;
    m_Reason = nil;
    m_Slider = nil;
    m_SliderLow = nil;
    m_SliderHigh = nil;
    m_Caption = nil;
    m_BitrateTileDetail = nil;
    m_BitrateTileBar = nil;
    m_SaverBox = nil;
    m_SaverText = nil;
    m_SaverReconnect = nil;
    m_QualityLine = nil;
    m_FpsTitle = nil;
    m_FpsGroup = nil;
    m_ResolutionTitle = nil;
    m_ResolutionButton = nil;
    [m_ResolutionChoices release];
    m_ResolutionChoices = nil;
    m_ReconnectCaption = nil;
    m_QualitySettingsLine = nil;
    m_QualitySettingsRow = nil;
    m_ResolutionsShown = NO;
    m_BatteryReconnect = nil;
    m_BatteryContent = nil;
    m_BatteryView = nil;
    m_BatteryLines[0] = m_BatteryLines[1] = nil;
    m_SaverSwitch = nil;
    m_SaverCaptions[0] = m_SaverCaptions[1] = nil;
    m_BatterySettingsRow = nil;
    m_HeldKbps = 0;
    [self dropControls];
    m_Selected = -1;
}

- (void)dropControls
{
    for (ForkMenuControl* control in m_Controls) {
        [control detach];
    }
    [m_Controls removeAllObjects];
    m_ListScrim = nil;
    m_ListView = nil;
    m_ListFirst = 0;
    m_ListOpener = nil;
    m_TrackpadTile = nil;
}

// A list of choices over the open menu, under what opened it (above it if there's no room below),
// its right edge with the opener's, as on the canvas
- (void)openListFor:(ForkMenuControl*)opener choices:(NSArray<ForkMenuControl*>*)choices
{
    [self closeList];
    NSView* content = opener.superview;
    while (content != nil && content.superview != m_Panel.contentView) {
        content = content.superview;
    }
    if (content == nil) {
        return;
    }
    const CGFloat rowHeight = 22;
    const CGFloat separatorHeight = 9;
    const CGFloat padding = 5;
    // The canvas's 224, wider for a long choice, within the menu
    CGFloat width = 224;
    for (ForkMenuControl* choice in choices) {
        if (choice->m_Kind == ForkMenuControlChoice) {
            width = MAX(width, [choice naturalWidth] + 2 * padding);
        }
    }
    width = MIN(width, NSWidth(content.bounds) - 8);

    m_ListScrim = [[[ForkListScrim alloc] initWithFrame:content.bounds] autorelease];
    m_ListScrim->m_Owner = self;
    [content addSubview:m_ListScrim];

    NSView* list = [[[ForkFlippedView alloc] initWithFrame:NSZeroRect] autorelease];
    list.wantsLayer = YES;
    list.layer.cornerRadius = 10;
    list.layer.backgroundColor = [NSColor colorWithSRGBRed:44 / 255.0 green:44 / 255.0 blue:48 / 255.0 alpha:0.97].CGColor;
    list.layer.borderWidth = 1;
    list.layer.borderColor = white(0.10);
    list.layer.shadowOpacity = 0.55;
    list.layer.shadowRadius = 16;
    list.layer.shadowOffset = CGSizeZero;   // all round: a flipped view's layer would turn an offset upwards
    [list setAccessibilityElement:YES];
    [list setAccessibilityRole:NSAccessibilityMenuRole];
    CGFloat height = padding * 2;
    for (ForkMenuControl* choice in choices) {
        height += choice->m_Kind == ForkMenuControlSeparator ? separatorHeight : rowHeight;
    }
    NSRect openerFrame = [content convertRect:opener.bounds fromView:opener];
    CGFloat x = MAX(4, MIN(NSMaxX(openerFrame) - width, NSWidth(content.bounds) - 4 - width));
    CGFloat y = NSMaxY(openerFrame) + 4;
    if (y + height > NSHeight(content.bounds) - 4) {
        y = MAX(4, NSMinY(openerFrame) - 4 - height);
    }
    list.frame = NSMakeRect(x, y, width, height);
    m_ListFirst = m_Controls.count;
    CGFloat rowY = padding;
    for (ForkMenuControl* choice in choices) {
        CGFloat itemHeight = choice->m_Kind == ForkMenuControlSeparator ? separatorHeight : rowHeight;
        choice.frame = NSMakeRect(padding, rowY, width - 2 * padding, itemHeight);
        [list addSubview:choice];
        [m_Controls addObject:choice];
        rowY += itemHeight;
    }
    [content addSubview:list];
    m_ListView = list;
    m_ListOpener = opener;
    [opener setAccessibilityExpanded:YES];

    // The keyboard goes on to the ticked choice; the pointer selects as it moves
    BOOL keyboard = m_KeyboardSelection;
    int ticked = -1;
    for (NSUInteger i = m_ListFirst; i < m_Controls.count; i++) {
        if (m_Controls[i]->m_On) {
            ticked = (int)i;
            break;
        }
    }
    [self select:keyboard ? (ticked >= 0 ? ticked : (int)m_ListFirst) : -1 keyboard:keyboard];
}

// Stream Settings, as on the canvas: the app's settings over Settings, a draft until Apply or Save for
// Next Time (ForkStreamSettings). Its rows' capsules open their choices in a list over the panel.
- (void)buildStreamSettings:(NSView*)content size:(NSSize*)size
{
    m_SettingsView = ForkStreamSettings::View();
    if (m_Host == nil || ![m_Host menusStreamSettings:&m_SettingsView open:m_Opening]) {
        *size = NSMakeSize(k_SettingsWidth, 2 * k_SettingsPadding);
        return;
    }
    const ForkStreamSettings::View& view = m_SettingsView;
    const CGFloat outer = k_SettingsWidth - 2 * k_SettingsPadding;
    const CGFloat left = k_SettingsPadding + 4;    // the rows' text inset
    const CGFloat inner = outer - 8;
    CGFloat y = k_SettingsPadding;
    auto addText = [&](NSString* text, NSFont* font, NSColor* color, CGFloat x, CGFloat width) {
        NSTextField* label = makeWrappingText(font, color);
        label.stringValue = text;
        CGFloat height = textHeight(label, width);
        label.frame = NSMakeRect(x, y, width, height);
        [content addSubview:label];
        return height;
    };
    auto reconnectIcon = [&]() {
        NSImageView* icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
        icon.imageScaling = NSImageScaleNone;
        icon.image = symbol(@"arrow.clockwise", 10, NSFontWeightMedium);
        icon.contentTintColor = NSColor.secondaryLabelColor;
        [icon setFrameSize:icon.image != nil ? icon.image.size : NSMakeSize(11, 11)];
        [icon setAccessibilityElement:YES];
        [icon setAccessibilityRole:NSAccessibilityImageRole];
        [icon setAccessibilityLabel:tr("Reconnects the stream")];
        return icon;
    };

    // "Stream Settings for Desktop", "GAMING-PC · Office profile"
    y += addText(view.title.toNSString(), [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor, left, inner) + 2;
    y += addText(view.subtitle.toNSString(), [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor, left, inner);

    // The preset cards, a segmented control
    y += 10;
    NSView* presets = [[[ForkFlippedView alloc] initWithFrame:NSMakeRect(k_SettingsPadding, y, outer, 28)] autorelease];
    presets.wantsLayer = YES;
    presets.layer.cornerRadius = 8;
    presets.layer.backgroundColor = white(0.08);
    [presets setAccessibilityElement:YES];
    [presets setAccessibilityRole:NSAccessibilityRadioGroupRole];
    [presets setAccessibilityLabel:tr("Profile")];
    [content addSubview:presets];
    NSString* presetNames[] = { tr("Office"), tr("Gaming"), tr("Custom") };
    CGFloat chipWidth = (outer - 4 - 4) / 3;
    for (int i = 0; i < 3; i++) {
        ForkMenuControl* chip = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlChip owner:self] autorelease];
        chip->m_Local = ForkMenuLocalPreset;
        chip->m_Value = i;
        chip->m_On = view.preset == i;
        chip.layer.cornerRadius = 6;
        [chip setTitle:presetNames[i] detail:nil symbol:nil];
        [chip setAccessibilityValue:chip->m_On ? @1 : @0];
        chip.frame = NSMakeRect(2 + i * (chipWidth + 2), 2, chipWidth, 24);
        [presets addSubview:chip];
        [m_Controls addObject:chip];
    }
    y += 28 + 6;

    // "2 settings are set for Desktop. The rest follow Settings."
    y += addText(view.countText.toNSString(), [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor, left, inner) + 4;

    // The sections and their rows: a gold dot when set for the app, ↻ when the row's value reconnects,
    // the value in a capsule
    NSColor* gold = [NSColor colorWithSRGBRed:0xe3 / 255.0 green:0xb3 / 255.0 blue:0x41 / 255.0 alpha:1];
    int rowIndex = 0;
    for (const ForkStreamSettings::Section& section : view.sections) {
        y += 8;
        y += addText(section.title.toNSString(), [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor,
                     left, inner) + 2;
        for (const ForkStreamSettings::Row& row : section.rows) {
            ForkMenuControl* popup = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlPopup owner:self] autorelease];
            popup->m_Local = ForkMenuLocalRow;
            popup->m_Value = rowIndex;
            [popup setTitle:row.value.toNSString() detail:nil symbol:nil];
            [popup setAccessibilityLabel:row.accessibility.toNSString()];
            [popup setAccessibilityExpanded:NO];
            CGFloat popupWidth = MIN([popup naturalWidth], 190);
            popup.frame = NSMakeRect(left + inner - popupWidth, y + 2, popupWidth, 22);

            NSView* dot = [[[NSView alloc] initWithFrame:NSMakeRect(left, y + round((k_SettingsRowHeight - 6) / 2), 6, 6)] autorelease];
            dot.wantsLayer = YES;
            dot.layer.cornerRadius = 3;
            dot.layer.backgroundColor = row.set ? gold.CGColor : CGColorGetConstantColor(kCGColorClear);
            [content addSubview:dot];

            NSTextField* label = makeText(row.label.toNSString(), [NSFont systemFontOfSize:13], NSColor.labelColor);
            [label sizeToFit];
            CGFloat labelX = left + 6 + 6;
            NSImageView* icon = row.reconnects ? reconnectIcon() : nil;
            CGFloat room = NSMinX(popup.frame) - 10 - labelX - (icon != nil ? 6 + NSWidth(icon.frame) : 0);
            label.frame = NSMakeRect(labelX, y + round((k_SettingsRowHeight - NSHeight(label.frame)) / 2), MAX(MIN(NSWidth(label.frame), room), 0),
                                     NSHeight(label.frame));
            [content addSubview:label];
            if (icon != nil) {
                [icon setFrameOrigin:NSMakePoint(NSMaxX(label.frame) + 6, y + round((k_SettingsRowHeight - NSHeight(icon.frame)) / 2))];
                [content addSubview:icon];
            }
            [content addSubview:popup];
            [m_Controls addObject:popup];
            y += k_SettingsRowHeight;
            rowIndex++;
        }
    }

    // "↻ Reconnects the stream, for a second or two"
    y += 6;
    NSImageView* legendIcon = reconnectIcon();
    [legendIcon setAccessibilityElement:NO];
    NSTextField* legend = makeText(tr("Reconnects the stream, for a second or two"), [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [legend sizeToFit];
    [legendIcon setFrameOrigin:NSMakePoint(left, y + round((NSHeight(legend.frame) - NSHeight(legendIcon.frame)) / 2))];
    legend.frame = NSMakeRect(left + NSWidth(legendIcon.frame) + 6, y, inner - NSWidth(legendIcon.frame) - 6, NSHeight(legend.frame));
    [content addSubview:legendIcon];
    [content addSubview:legend];
    y += NSHeight(legend.frame);

    // Reset to Global at the left; Save for Next Time and Apply at the right
    y += 10;
    NSView* line = makeSeparatorLine();
    line.frame = NSMakeRect(k_SettingsPadding, y, outer, 1);
    [content addSubview:line];
    y += 1 + 10;
    auto addButton = [&](NSString* title, ForkButtonStyle style, BOOL enabled) {
        ForkMenuControl* button = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlButton owner:self] autorelease];
        button->m_ButtonStyle = style;
        button->m_Enabled = enabled;
        [button setTitle:title detail:nil symbol:nil];
        [content addSubview:button];
        [m_Controls addObject:button];
        [button refreshAppearance];
        return button;
    };
    ForkMenuControl* reset = addButton(tr("Reset to Global"), ForkButtonLink, YES);
    reset->m_Local = ForkMenuLocalReset;
    ForkMenuControl* save = addButton(tr("Save for Next Time"), ForkButtonSecondary, view.canSave);
    save->m_Action = NotchMenus::Action::StreamSettingsSave;
    ForkMenuControl* apply = addButton(view.applyReconnects ? tr("Apply and Reconnect") : tr("Apply"), ForkButtonPrimary, view.canApply);
    apply->m_Action = NotchMenus::Action::StreamSettingsApply;
    CGFloat right = k_SettingsPadding + outer;
    CGFloat applyWidth = [apply naturalWidth];
    apply.frame = NSMakeRect(right - applyWidth, y, applyWidth, 24);
    CGFloat saveWidth = [save naturalWidth];
    save.frame = NSMakeRect(NSMinX(apply.frame) - 8 - saveWidth, y, saveWidth, 24);
    reset.frame = NSMakeRect(k_SettingsPadding, y, [reset naturalWidth], 24);
    y += 24 + 10;
    *size = NSMakeSize(k_SettingsWidth, y);
}

// A Stream Settings row's choices: Global first, then a line, then the row's values; ↻ on those that
// reconnect where the row's others don't
- (void)openStreamSettingsList:(ForkMenuControl*)popup
{
    int wanted = popup->m_Value;
    int rowIndex = 0;
    const ForkStreamSettings::Row* found = nullptr;
    for (const ForkStreamSettings::Section& section : m_SettingsView.sections) {
        for (const ForkStreamSettings::Row& row : section.rows) {
            if (rowIndex++ == wanted) {
                found = &row;
            }
        }
    }
    if (found == nullptr) {
        return;
    }
    NSMutableArray<ForkMenuControl*>* choices = [NSMutableArray array];
    for (size_t i = 0; i < found->choices.size(); i++) {
        const ForkStreamSettings::Choice& option = found->choices[i];
        ForkMenuControl* choice = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlChoice owner:self] autorelease];
        choice->m_Local = ForkMenuLocalPick;
        choice->m_Value = (wanted << 8) | static_cast<int>(i);
        [choice setTitle:option.text.toNSString() detail:nil symbol:nil];
        [choice setChecked:option.checked reconnects:option.reconnects];
        [choices addObject:choice];
        if (option.separatorAfter) {
            [choices addObject:[[[ForkMenuControl alloc] initWithKind:ForkMenuControlSeparator owner:self] autorelease]];
        }
    }
    popup->m_On = YES;
    [popup refreshAppearance];
    [self openListFor:popup choices:choices];
}

// Control Center's Trackpad: the three modes, the stream's ticked, ↻ on those that reconnect
// (ReconnectRules::trackpadNeedsReconnect())
- (void)openTrackpadList
{
    if (m_TrackpadTile == nil || m_Host == nil) {
        return;
    }
    NotchBar::MenuState state = [m_Host menusState];
    NSMutableArray<ForkMenuControl*>* choices = [NSMutableArray array];
    for (int mode : { ReconnectRules::k_TrackpadMacTrackpad, ReconnectRules::k_TrackpadWindowsTouchpad, ReconnectRules::k_TrackpadMacMouse }) {
        ForkMenuControl* choice = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlChoice owner:self] autorelease];
        choice->m_Action = NotchMenus::Action::SetTrackpadMode;
        choice->m_Value = mode;
        [choice setTitle:trackpadModeTitle(mode) detail:nil symbol:nil];
        BOOL current = mode == state.trackpadMode;
        // Greyed when the PC's Apollo can't take the trackpad that way
        choice->m_Enabled = current || mode == ReconnectRules::k_TrackpadMacMouse ||
                            (mode == ReconnectRules::k_TrackpadWindowsTouchpad ? state.trackpadTouchpad : state.trackpadMac);
        [choice setAccessibilityEnabled:choice->m_Enabled];
        [choice setChecked:current reconnects:!current && ReconnectRules::trackpadNeedsReconnect(state.trackpadStartedMode, mode)];
        [choices addObject:choice];
    }
    [self openListFor:m_TrackpadTile choices:choices];
}

- (void)closeList
{
    if (m_ListView == nil) {
        return;
    }
    while (m_Controls.count > m_ListFirst) {
        ForkMenuControl* choice = m_Controls.lastObject;
        [choice detach];
        // This may run inside the choice's mouseUp:
        [[choice retain] autorelease];
        [m_Controls removeLastObject];
    }
    // This may run inside the scrim's mouseDown:
    [[m_ListView retain] autorelease];
    [[m_ListScrim retain] autorelease];
    [m_ListView removeFromSuperview];
    [m_ListScrim removeFromSuperview];
    m_ListView = nil;
    m_ListScrim = nil;
    ForkMenuControl* opener = m_ListOpener;
    m_ListOpener = nil;
    [opener setAccessibilityExpanded:NO];
    if (opener != nil && opener->m_Local == ForkMenuLocalRow) {
        opener->m_On = NO;
        [opener refreshAppearance];
    }
    NSUInteger index = opener != nil ? [m_Controls indexOfObject:opener] : NSNotFound;
    [self select:index != NSNotFound && m_KeyboardSelection ? (int)index : -1 keyboard:m_KeyboardSelection];
}

- (void)closeQuietly
{
    [self removePanel];
    m_Open = NotchMenus::Menu::None;
    if (m_ClickMonitor != nil) {
        [NSEvent removeMonitor:m_ClickMonitor];
        [m_ClickMonitor release];
        m_ClickMonitor = nil;
    }
}

- (void)close
{
    if (m_Open == NotchMenus::Menu::None) {
        return;
    }
    [self closeQuietly];
    [m_Host menusChanged:NotchMenus::Menu::None];
}

- (void)refresh
{
    if (m_Open == NotchMenus::Menu::None || m_Panel == nil) {
        return;
    }
    if (m_Open == NotchMenus::Menu::Status) {
        // In place, keeping what the pointer is on; rebuilding would lose it, and MenusOpened
        // refreshes right after the menu opens
        [self statusChanged];
        return;
    }
    if (m_Open == NotchMenus::Menu::Quality) {
        // In place too: a drag on the slider goes on while the PC answers
        [self qualityChanged];
        return;
    }
    if (m_Open == NotchMenus::Menu::Battery) {
        // In place, as the battery changes every few seconds under a pointer on its switch
        [self batteryChanged];
        return;
    }
    [self rebuild];
}

- (BOOL)controlTakesPointer:(NSView*)control
{
    return m_ListView == nil || ((ForkMenuControl*)control)->m_Kind == ForkMenuControlChoice;
}

// Builds the open menu again in its panel, keeping the selection where it can
- (void)rebuild
{
    if (m_Open == NotchMenus::Menu::None || m_Panel == nil) {
        return;
    }
    // A list over it goes, its opener selected again, rather than vanish with the old content
    [self closeList];
    int selected = m_Selected;
    BOOL keyboard = m_KeyboardSelection;

    NSSize size;
    NSView* content = [self buildContent:&size];
    NSView* effect = m_Panel.contentView;
    for (NSView* old in [[effect.subviews copy] autorelease]) {
        [old removeFromSuperview];
    }
    [effect addSubview:content];

    // Same place, the same top edge if its height changed
    NSRect frame = m_Panel.frame;
    [m_Panel setFrame:NSMakeRect(NSMinX(frame), NSMaxY(frame) - size.height, size.width, size.height) display:YES];
    if (selected >= 0 && [self selectable:selected]) {
        [self select:selected keyboard:keyboard];
    }
}

- (void)statusChanged
{
    if (m_StatusView == nil || m_Host == nil) {
        return;
    }
    ForkStatusModel model;
    [m_Host menusStatus:&model];
    [m_StatusView update:model];

    // Control-Option-Shift-S reaches the stream while the menu is open, so the row follows it
    for (ForkMenuControl* control in m_Controls) {
        if (control->m_Action == NotchMenus::Action::ToggleStatsOverlay) {
            [control setTitle:[m_Host menusState].statsOverlayShown ? tr("Hide Stats Overlay") : tr("Show Stats Overlay")
                       detail:@"⌃⌥⇧S" symbol:nil];
        }
    }
}

// Quality: the bitrate now, the switch for adaptive bitrate and why it's where it is, and the slider
// that sets it by hand. qualityChanged updates the parts in place.
- (void)buildQuality:(NSView*)content state:(const NotchBar::MenuState&)menuState
{
    const NotchQuality::State& state = menuState.bitrate;
    m_QualityContent = content;
    m_QualityTitle = makeText(tr("Bitrate"), [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
    [content addSubview:m_QualityTitle];
    m_QualityValue = makeText(@"", [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular], NSColor.secondaryLabelColor);
    m_QualityValue.alignment = NSTextAlignmentRight;
    [content addSubview:m_QualityValue];

    // Stream Battery Saver's note, in a yellow box with a dot, as on the canvas
    m_SaverBox = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    m_SaverBox.wantsLayer = YES;
    m_SaverBox.layer.cornerRadius = 6;
    m_SaverBox.layer.backgroundColor = [saverColor() colorWithAlphaComponent:0.12].CGColor;
    NSView* saverDot = [[[NSView alloc] initWithFrame:NSMakeRect(6, 0, 7, 7)] autorelease];
    saverDot.wantsLayer = YES;
    saverDot.layer.cornerRadius = 3.5;
    saverDot.layer.backgroundColor = saverColor().CGColor;
    saverDot.identifier = @"dot";
    [m_SaverBox addSubview:saverDot];
    m_SaverText = makeWrappingText([NSFont systemFontOfSize:12], NSColor.labelColor);
    [m_SaverBox addSubview:m_SaverText];
    [content addSubview:m_SaverBox];
    m_SaverReconnect = [self reconnectAtSaverRow];
    [content addSubview:m_SaverReconnect];
    [m_Controls addObject:m_SaverReconnect];

    m_AdaptSwitch = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlSwitch owner:self] autorelease];
    m_AdaptSwitch->m_Action = NotchMenus::Action::ToggleAdaptiveBitrate;
    [m_AdaptSwitch setTitle:tr("Adapt to the network") detail:nil symbol:nil];
    [content addSubview:m_AdaptSwitch];
    [m_Controls addObject:m_AdaptSwitch];

    m_ReasonDot = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 7, 7)] autorelease];
    m_ReasonDot.wantsLayer = YES;
    m_ReasonDot.layer.cornerRadius = 3.5;
    m_ReasonDot.layer.backgroundColor = loweredColor().CGColor;
    [content addSubview:m_ReasonDot];
    m_Reason = makeWrappingText([NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [content addSubview:m_Reason];

    m_Slider = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlSlider owner:self] autorelease];
    m_Slider->m_Action = NotchMenus::Action::SetBitrate;
    [m_Slider setAccessibilityLabel:tr("Bitrate")];
    [content addSubview:m_Slider];
    [m_Controls addObject:m_Slider];
    m_SliderLow = makeText(@"", [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular], NSColor.secondaryLabelColor);
    m_SliderHigh = makeText(@"", [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular], NSColor.secondaryLabelColor);
    m_SliderHigh.alignment = NSTextAlignmentRight;
    [content addSubview:m_SliderLow];
    [content addSubview:m_SliderHigh];
    m_Caption = makeWrappingText([NSFont systemFontOfSize:11], NSColor.secondaryLabelColor);
    [content addSubview:m_Caption];

    // Frame rate and resolution, which reconnect: the stream's own lit or ticked
    m_QualityLine = makeSeparatorLine();
    [content addSubview:m_QualityLine];
    m_FpsTitle = makeText(tr("Frame rate"), [NSFont systemFontOfSize:13], NSColor.labelColor);
    [content addSubview:m_FpsTitle];
    m_FpsGroup = [[[ForkFlippedView alloc] initWithFrame:NSZeroRect] autorelease];
    m_FpsGroup.wantsLayer = YES;
    m_FpsGroup.layer.cornerRadius = 7;
    m_FpsGroup.layer.backgroundColor = white(0.08);
    [m_FpsGroup setAccessibilityElement:YES];
    [m_FpsGroup setAccessibilityRole:NSAccessibilityRadioGroupRole];
    [m_FpsGroup setAccessibilityLabel:tr("Frame rate")];
    [content addSubview:m_FpsGroup];
    NSScreen* screen = [m_Host menusBarWindow].screen;
    int screenFps = 60;
    if (@available(macOS 12.0, *)) {
        screenFps = screen != nil ? (int)screen.maximumFramesPerSecond : 60;
    }
    for (int fps : ReconnectRules::fpsChoices(menuState.streamFps, screenFps)) {
        ForkMenuControl* chip = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlChip owner:self] autorelease];
        BOOL current = fps == menuState.streamFps;
        chip->m_On = current;
        chip->m_Action = current ? NotchMenus::Action::None : NotchMenus::Action::ReconnectAtFps;
        chip->m_Value = fps;
        [chip setTitle:[NSString stringWithFormat:@"%d", fps] detail:nil symbol:nil];
        [chip setAccessibilityLabel:QCoreApplication::translate("NotchBar", "%1 frames per second").arg(fps).toNSString()];
        [chip setAccessibilityValue:current ? @1 : @0];
        [m_FpsGroup addSubview:chip];
        [m_Controls addObject:chip];
    }

    ReconnectRules::Size streamSize { menuState.streamWidth, menuState.streamHeight };
    m_ResolutionTitle = makeText(tr("Resolution"), [NSFont systemFontOfSize:13], NSColor.labelColor);
    [content addSubview:m_ResolutionTitle];
    m_ResolutionButton = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlPopup owner:self] autorelease];
    m_ResolutionButton->m_On = m_ResolutionsShown;
    [m_ResolutionButton setTitle:[NSString stringWithFormat:@"%d × %d", streamSize.width, streamSize.height] detail:nil symbol:nil];
    [m_ResolutionButton setAccessibilityLabel:tr("Resolution")];
    [m_ResolutionButton setAccessibilityValue:QCoreApplication::translate("NotchBar", "%1 by %2")
                                                  .arg(streamSize.width).arg(streamSize.height).toNSString()];
    [m_ResolutionButton setAccessibilityExpanded:m_ResolutionsShown];
    [content addSubview:m_ResolutionButton];
    [m_Controls addObject:m_ResolutionButton];
    [m_ResolutionChoices release];
    m_ResolutionChoices = [[NSMutableArray alloc] init];
    if (m_ResolutionsShown) {
        // The screen's area below the notch, in pixels
        ReconnectRules::Size screenSize;
        if (screen != nil) {
            CGFloat scale = screen.backingScaleFactor;
            CGFloat top = 0;
            if (@available(macOS 12.0, *)) {
                top = screen.safeAreaInsets.top;
            }
            screenSize = { (int)lround(NSWidth(screen.frame) * scale), (int)lround((NSHeight(screen.frame) - top) * scale) };
        }
        for (const ReconnectRules::Size& size : ReconnectRules::resolutionChoices(streamSize, screenSize)) {
            ForkMenuControl* row = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlRow owner:self] autorelease];
            BOOL current = size == streamSize;
            row->m_Action = current ? NotchMenus::Action::None : NotchMenus::Action::ReconnectAtResolution;
            row->m_Value = ReconnectRules::packSize(size);
            [row setTitle:[NSString stringWithFormat:@"    %d × %d", size.width, size.height] detail:current ? @"✓" : nil symbol:nil];
            [row setAccessibilityLabel:QCoreApplication::translate("NotchBar", "%1 by %2").arg(size.width).arg(size.height).toNSString()];
            [row setAccessibilitySelected:current];
            [content addSubview:row];
            [m_Controls addObject:row];
            [m_ResolutionChoices addObject:row];
        }
    }
    m_ReconnectCaption = makeWrappingText([NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    m_ReconnectCaption.stringValue = tr("Changing these reconnects the stream.");
    [content addSubview:m_ReconnectCaption];

    // Every setting of the app's, in Stream Settings
    m_QualitySettingsLine = makeSeparatorLine();
    [content addSubview:m_QualitySettingsLine];
    m_QualitySettingsRow = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlRow owner:self] autorelease];
    m_QualitySettingsRow->m_Action = NotchMenus::Action::OpenStreamSettings;
    [m_QualitySettingsRow setTitle:QCoreApplication::translate("NotchBar", "Stream Settings for %1…").arg(shortName(m_AppName)).toNSString()
                            detail:nil symbol:nil];
    [content addSubview:m_QualitySettingsRow];
    [m_Controls addObject:m_QualitySettingsRow];

    [self showQuality:state];
}

// "Reconnect at 10 Mb/s": Stream Battery Saver's cap on a PC that can't change the bitrate live
- (ForkMenuControl*)reconnectAtSaverRow
{
    ForkMenuControl* row = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlRow owner:self] autorelease];
    row->m_Action = NotchMenus::Action::ReconnectAtBitrate;
    row->m_Value = PowerRules::k_SaverKbps;
    [row setTitle:QCoreApplication::translate("NotchBar", "Reconnect at %1").arg(mbpsText(PowerRules::k_SaverKbps)).toNSString()
           detail:nil symbol:nil];
    return row;
}

// Puts the state in Quality's parts; layoutQuality places them
- (void)showQuality:(const NotchQuality::State&)state
{
    m_Bitrate = state;
    NotchQuality::Range range = NotchQuality::range(state);
    int shown = NotchQuality::shownKbps(state);
    if (m_HeldKbps > 0 && (shown == m_HeldKbps || !NotchQuality::sliderEnabled(state) || CACurrentMediaTime() >= m_HeldUntil)) {
        m_HeldKbps = 0;
    }

    switch (NotchQuality::saverNote(state)) {
    case NotchQuality::SaverNote::Caps:
        m_SaverText.stringValue = QCoreApplication::translate("NotchBar", "Stream Battery Saver caps the bitrate at %1.")
                                      .arg(mbpsText(PowerRules::k_SaverKbps)).toNSString();
        break;
    case NotchQuality::SaverNote::NeedsReconnect:
        m_SaverText.stringValue = tr("On this PC, Stream Battery Saver needs a reconnect to cap the bitrate.");
        break;
    case NotchQuality::SaverNote::None:
        m_SaverText.stringValue = @"";
        break;
    }
    m_SaverBox.hidden = m_SaverText.stringValue.length == 0;
    BOOL saverReconnect = NotchQuality::saverNote(state) == NotchQuality::SaverNote::NeedsReconnect;
    m_SaverReconnect.hidden = !saverReconnect;
    m_SaverReconnect->m_Enabled = saverReconnect;

    m_AdaptSwitch->m_On = state.adapting;
    m_AdaptSwitch->m_Enabled = NotchQuality::switchEnabled(state);
    [m_AdaptSwitch setAccessibilityValue:state.adapting ? @1 : @0];
    [m_AdaptSwitch setAccessibilityEnabled:m_AdaptSwitch->m_Enabled];
    [m_AdaptSwitch refreshAppearance];

    QString own = QString::fromStdString(NotchQuality::mbps(state.ownKbps));
    QString line;
    BOOL lowered = NO;
    switch (NotchQuality::line(state)) {
    case NotchQuality::Line::LoweredLoss:
        line = QCoreApplication::translate("NotchBar", "Lowered %1: %2% of frames lost")
                   .arg(agoText(state.changeAgoSeconds), QString::fromStdString(NotchQuality::percent(state.changeDropPercent)));
        lowered = YES;
        break;
    case NotchQuality::Line::LoweredPoor:
        line = QCoreApplication::translate("NotchBar", "Lowered %1: the connection was poor").arg(agoText(state.changeAgoSeconds));
        lowered = YES;
        break;
    case NotchQuality::Line::LoweredRoundTrip:
        line = QCoreApplication::translate("NotchBar", "Lowered %1: round-trip %2 ms, usually %3 ms")
                   .arg(agoText(state.changeAgoSeconds)).arg(state.changeRttMs).arg(state.changeBaseRttMs);
        lowered = YES;
        break;
    case NotchQuality::Line::Climbing:
        // To the user's own, or to the saver's cap while it holds the stream down
        line = NotchQuality::saverCaps(state) ?
                   QCoreApplication::translate("NotchBar", "Climbing back to %1").arg(mbpsText(NotchQuality::climbKbps(state))) :
                   QCoreApplication::translate("NotchBar", "Climbing back to your %1 Mb/s").arg(own);
        break;
    case NotchQuality::Line::Holding:
        line = QCoreApplication::translate("NotchBar", "Holding the bitrate you set");
        break;
    case NotchQuality::Line::EncoderCant:
        line = QCoreApplication::translate("NotchBar", "This PC's encoder can't change the bitrate during a stream.");
        break;
    case NotchQuality::Line::ApolloCant:
        line = QCoreApplication::translate("NotchBar", "This PC's Apollo can't change the bitrate during a stream.");
        break;
    case NotchQuality::Line::PcCant:
        line = QCoreApplication::translate("NotchBar", "This PC can't change the bitrate during a stream.");
        break;
    case NotchQuality::Line::None:
        break;
    }
    m_Reason.stringValue = line.toNSString();
    m_ReasonDot.hidden = !lowered;

    m_Slider->m_MinKbps = range.minKbps;
    m_Slider->m_MaxKbps = range.maxKbps;
    m_Slider->m_StepKbps = range.stepKbps;
    m_Slider->m_Enabled = NotchQuality::sliderEnabled(state);
    if (!m_Slider->m_Enabled) {
        // Adaptive bitrate came on, or the PC turned out unable: a drag in progress ends here
        m_Slider->m_Dragging = NO;
    }
    if (!m_Slider->m_Dragging) {
        m_Slider->m_ValueKbps = MAX(range.minKbps, MIN(m_HeldKbps > 0 ? m_HeldKbps : shown, range.maxKbps));
    }
    [m_Slider setAccessibilityMinValue:@(range.minKbps / 1000.0)];
    [m_Slider setAccessibilityMaxValue:@(range.maxKbps / 1000.0)];
    [m_Slider setAccessibilityEnabled:m_Slider->m_Enabled];
    [m_Slider refreshAppearance];
    m_SliderLow.stringValue = mbpsText(range.minKbps).toNSString();
    m_SliderHigh.stringValue = mbpsText(range.maxKbps).toNSString();

    switch (NotchQuality::caption(state)) {
    case NotchQuality::Caption::Adapting:
        m_Caption.stringValue = QCoreApplication::translate("NotchBar", "Adapting never goes above your %1 Mb/s.").arg(own).toNSString();
        break;
    case NotchQuality::Caption::ByHand:
        m_Caption.stringValue = QCoreApplication::translate("NotchBar", "Up to %1 without reconnecting.").arg(mbpsText(range.maxKbps)).toNSString();
        break;
    case NotchQuality::Caption::CantChange:
        m_Caption.stringValue = tr("Stream Settings can change it; that reconnects.");
        break;
    }

    // A control selected from the keyboard that can't be used now gives up the selection
    if (m_Selected >= 0 && ![self selectable:m_Selected]) {
        int next = m_KeyboardSelection ? NotchMenus::nextSelectable((int)m_Controls.count, m_Selected, 1, [self](int i) { return [self selectable:i]; }) : -1;
        [self select:next keyboard:m_KeyboardSelection];
    }

    [self showBitrateValue];
}

// "18 of 20 Mb/s" while adapting, "18 Mb/s" otherwise; where the slider is while it moves
- (void)showBitrateValue
{
    int kbps = m_Slider->m_Dragging || m_HeldKbps > 0 ? m_Slider->m_ValueKbps : NotchQuality::shownKbps(m_Bitrate);
    QString value = QString::fromStdString(NotchQuality::mbps(kbps));
    m_QualityValue.stringValue = (m_Bitrate.adapting ?
                                      QCoreApplication::translate("NotchBar", "%1 of %2 Mb/s").arg(value, QString::fromStdString(NotchQuality::mbps(m_Bitrate.ownKbps))) :
                                      mbpsText(kbps)).toNSString();
    [m_Slider setAccessibilityValue:@(m_Slider->m_ValueKbps / 1000.0)];
    [m_Slider setAccessibilityValueDescription:QCoreApplication::translate("NotchBar", "%1 megabits per second")
                                                   .arg(QString::fromStdString(NotchQuality::mbps(m_Slider->m_ValueKbps))).toNSString()];
}

// Places Quality's parts top down, and returns the height they take
- (CGFloat)layoutQuality
{
    CGFloat width = k_QualityWidth - 2 * k_QualityPadding;
    CGFloat left = k_QualityPadding + 9;    // the rows' text inset
    CGFloat inner = width - 18;
    CGFloat y = k_QualityPadding;

    [m_QualityTitle sizeToFit];
    [m_QualityValue sizeToFit];
    CGFloat valueWidth = NSWidth(m_QualityValue.frame);
    m_QualityValue.frame = NSMakeRect(left + inner - valueWidth, y + round((k_QualityHeaderHeight - NSHeight(m_QualityValue.frame)) / 2),
                                      valueWidth, NSHeight(m_QualityValue.frame));
    m_QualityTitle.frame = NSMakeRect(left, y + round((k_QualityHeaderHeight - NSHeight(m_QualityTitle.frame)) / 2),
                                      MAX(inner - valueWidth - 12, 0), NSHeight(m_QualityTitle.frame));
    y += k_QualityHeaderHeight;

    // The saver's note: inset 3 from the rows, 6 inside, the dot then the text
    if (!m_SaverBox.hidden) {
        CGFloat boxWidth = width - 6;
        CGFloat textWidth = boxWidth - 6 - 7 - 7 - 6;
        CGFloat noteHeight = textHeight(m_SaverText, textWidth);
        CGFloat boxHeight = MAX(noteHeight + 6, 22);
        m_SaverBox.frame = NSMakeRect(k_QualityPadding + 3, y, boxWidth, boxHeight);
        m_SaverText.frame = NSMakeRect(6 + 7 + 7, round((boxHeight - noteHeight) / 2), textWidth, noteHeight);
        for (NSView* view in m_SaverBox.subviews) {
            if ([view.identifier isEqualToString:@"dot"]) {
                [view setFrameOrigin:NSMakePoint(6, round((boxHeight - 7) / 2))];
            }
        }
        y += boxHeight + 4;
    }
    if (!m_SaverReconnect.hidden) {
        m_SaverReconnect.frame = NSMakeRect(k_QualityPadding, y, width, k_RowHeight);
        y += k_RowHeight + 4;
    }

    m_AdaptSwitch.frame = NSMakeRect(k_QualityPadding, y, width, k_SwitchRowHeight);
    y += k_SwitchRowHeight;

    // After the dot when there is one; at least 18 pt even when empty, as on the canvas, so it rarely
    // moves the slider
    CGFloat textLeft = m_ReasonDot.hidden ? left : left + 7 + 6;
    CGFloat textWidth = left + inner - textLeft;
    CGFloat fit = m_Reason.stringValue.length > 0 ? textHeight(m_Reason, textWidth) : 0;
    CGFloat lines = fit > 18 ? 2 : 1;
    CGFloat reasonHeight = MAX(fit, 18);
    // One line sits in the middle of its 18 pt; the dot beside the first line
    m_Reason.frame = NSMakeRect(textLeft, y + round((reasonHeight - fit) / 2), textWidth, fit);
    [m_ReasonDot setFrameOrigin:NSMakePoint(left, y + round((reasonHeight / lines - 7) / 2))];
    y += reasonHeight + 2 + 8;

    // The track runs from the text inset to the right one; the knob's half hangs over each end
    m_Slider.frame = NSMakeRect(left - k_Knob / 2, y, inner + k_Knob, k_SliderHeight);
    y += k_SliderHeight + 3;
    [m_SliderLow sizeToFit];
    [m_SliderHigh sizeToFit];
    m_SliderLow.frame = NSMakeRect(left, y, NSWidth(m_SliderLow.frame), NSHeight(m_SliderLow.frame));
    m_SliderHigh.frame = NSMakeRect(left + inner - NSWidth(m_SliderHigh.frame), y, NSWidth(m_SliderHigh.frame), NSHeight(m_SliderHigh.frame));
    y += NSHeight(m_SliderLow.frame) + 4;

    CGFloat captionHeight = textHeight(m_Caption, inner);
    m_Caption.frame = NSMakeRect(left, y, inner, captionHeight);
    y += captionHeight + 6;

    // Frame rate: the title, the chips at the right in their group, 32 pt
    m_QualityLine.frame = NSMakeRect(left, y + 5, inner, 1);
    y += 11;
    NSArray<NSView*>* chips = m_FpsGroup.subviews;
    CGFloat chipX = 2;
    for (NSView* chip in chips) {
        CGFloat chipWidth = MAX(40, [(ForkMenuControl*)chip naturalWidth] - 2);
        chip.frame = NSMakeRect(chipX, 2, chipWidth, 22);
        chipX += chipWidth + 2;
    }
    m_FpsGroup.frame = NSMakeRect(left + inner - chipX, y + 3, chipX, 26);
    [m_FpsTitle sizeToFit];
    m_FpsTitle.frame = NSMakeRect(left, y + round((32 - NSHeight(m_FpsTitle.frame)) / 2), MAX(inner - chipX - 12, 0), NSHeight(m_FpsTitle.frame));
    y += 32;

    // Resolution: the title, the stream's size in its capsule at the right, 32 pt; its choices under
    // it while they're open
    CGFloat buttonWidth = MIN([m_ResolutionButton naturalWidth], inner);
    m_ResolutionButton.frame = NSMakeRect(left + inner - buttonWidth, y + 5, buttonWidth, 22);
    [m_ResolutionTitle sizeToFit];
    m_ResolutionTitle.frame = NSMakeRect(left, y + round((32 - NSHeight(m_ResolutionTitle.frame)) / 2), MAX(inner - buttonWidth - 12, 0),
                                         NSHeight(m_ResolutionTitle.frame));
    y += 32;
    for (ForkMenuControl* choice in m_ResolutionChoices) {
        choice.frame = NSMakeRect(k_QualityPadding, y, width, k_RowHeight);
        y += k_RowHeight;
    }
    CGFloat reconnectHeight = textHeight(m_ReconnectCaption, inner);
    m_ReconnectCaption.frame = NSMakeRect(left, y + 2, inner, reconnectHeight);
    y += 2 + reconnectHeight + 4;

    m_QualitySettingsLine.frame = NSMakeRect(left, y + 5, inner, 1);
    y += 11;
    m_QualitySettingsRow.frame = NSMakeRect(k_QualityPadding, y, width, k_RowHeight);
    y += k_RowHeight;
    return y + k_QualityPadding;
}

// Lays Quality out again, its panel's top edge where it was if its height changed
- (void)relayoutQuality
{
    CGFloat height = [self layoutQuality];
    NSRect frame = m_Panel.frame;
    if (m_Panel != nil && height != NSHeight(frame)) {
        m_QualityContent.frame = NSMakeRect(0, 0, k_QualityWidth, height);
        [m_Panel setFrame:NSMakeRect(NSMinX(frame), NSMaxY(frame) - height, NSWidth(frame), height) display:YES];
    }
}

- (void)qualityChanged
{
    if (m_Slider == nil || m_Host == nil) {
        return;
    }
    [self showQuality:[m_Host menusState].bitrate];
    [self relayoutQuality];
}

- (void)sliderMoved:(NSView*)view final:(BOOL)final
{
    if (view != m_Slider || m_Host == nil) {
        return;
    }
    if (final) {
        // Shown until the PC runs at it, so the slider doesn't jump back while it's asked
        m_HeldKbps = m_Slider->m_ValueKbps;
        m_HeldUntil = CACurrentMediaTime() + k_HeldSeconds;
        if (m_HeldKbps != NotchQuality::shownKbps(m_Bitrate)) {
            [m_Host menusPerform:NotchMenus::Action::SetBitrate value:m_HeldKbps];
        }
    }
    [self showBitrateValue];
    [self relayoutQuality];
}

- (void)slider:(NSView*)view step:(int)direction
{
    if (view != m_Slider || !m_Slider->m_Enabled || m_Slider->m_Dragging) {
        return;
    }
    NotchQuality::Range range;
    range.minKbps = m_Slider->m_MinKbps;
    range.maxKbps = m_Slider->m_MaxKbps;
    range.stepKbps = m_Slider->m_StepKbps;
    int value = NotchQuality::snap(m_Slider->m_ValueKbps + (direction > 0 ? 1 : -1) * range.stepKbps, range);
    if (value == m_Slider->m_ValueKbps) {
        return;
    }
    m_Slider->m_ValueKbps = value;
    m_Slider.needsDisplay = YES;
    [self sliderMoved:m_Slider final:YES];
}

// Battery: the battery view, then Stream Battery Saver's switch and its captions, then Battery
// Settings…. batteryChanged updates it in place.
- (void)buildBattery:(NSView*)content
{
    m_BatteryContent = content;
    m_BatteryView = [[[ForkBatteryView alloc] initWithWidth:k_BatteryWidth - 2 * k_BatteryPadding] autorelease];
    [content addSubview:m_BatteryView];
    for (int i = 0; i < 2; i++) {
        m_BatteryLines[i] = makeSeparatorLine();
        [content addSubview:m_BatteryLines[i]];
    }

    m_SaverSwitch = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlSwitch owner:self] autorelease];
    m_SaverSwitch->m_Action = NotchMenus::Action::ToggleBatterySaver;
    [m_SaverSwitch setTitle:tr("Stream Battery Saver") detail:nil symbol:nil];
    [content addSubview:m_SaverSwitch];
    [m_Controls addObject:m_SaverSwitch];
    for (int i = 0; i < 2; i++) {
        m_SaverCaptions[i] = makeWrappingText([NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
        [content addSubview:m_SaverCaptions[i]];
    }
    m_SaverCaptions[1].stringValue = tr("Turns on with Low Power Mode. Turning it off isn’t remembered.");
    m_BatteryReconnect = [self reconnectAtSaverRow];
    [content addSubview:m_BatteryReconnect];
    [m_Controls addObject:m_BatteryReconnect];

    m_BatterySettingsRow = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlRow owner:self] autorelease];
    m_BatterySettingsRow->m_Action = NotchMenus::Action::OpenBatterySettings;
    [m_BatterySettingsRow setTitle:tr("Battery Settings…") detail:nil symbol:nil];
    [content addSubview:m_BatterySettingsRow];
    [m_Controls addObject:m_BatterySettingsRow];
}

// Puts the state in Battery's parts and places them top down; returns the height they take
- (CGFloat)layoutBattery:(const NotchBar::MenuState&)state
{
    CGFloat width = k_BatteryWidth - 2 * k_BatteryPadding;
    CGFloat left = k_BatteryPadding + 9;
    CGFloat inner = width - 18;
    CGFloat y = k_BatteryPadding;

    CGFloat height = [m_BatteryView update:state];
    [m_BatteryView setFrameOrigin:NSMakePoint(k_BatteryPadding, y)];
    y += height;

    m_BatteryLines[0].frame = NSMakeRect(left, y + 5, inner, 1);
    y += 11;

    // The switch, then what it does: live, or only with a reconnect on a PC that can't
    m_SaverSwitch->m_On = state.saverOn;
    [m_SaverSwitch setAccessibilityValue:state.saverOn ? @1 : @0];
    [m_SaverSwitch refreshAppearance];
    m_SaverSwitch.frame = NSMakeRect(k_BatteryPadding, y + 4, width, 26);
    y += 4 + 26;
    m_SaverCaptions[0].stringValue = state.bitrate.live ?
        QCoreApplication::translate("NotchBar", "Caps the bitrate at %1, without reconnecting.").arg(mbpsText(PowerRules::k_SaverKbps)).toNSString() :
        tr("On this PC, it needs a reconnect to cap the bitrate.");
    for (int i = 0; i < 2; i++) {
        CGFloat captionHeight = textHeight(m_SaverCaptions[i], inner);
        m_SaverCaptions[i].frame = NSMakeRect(left, y + (i == 1 ? 2 : 0), inner, captionHeight);
        y += captionHeight + (i == 1 ? 2 : 0);
    }
    y += 6;
    // The saver on, with a bitrate above its cap, and a PC that can't cap it live: a reconnect can
    BOOL reconnect = state.saverOn && !state.bitrate.live && state.bitrate.ownKbps > PowerRules::k_SaverKbps;
    m_BatteryReconnect.hidden = !reconnect;
    m_BatteryReconnect->m_Enabled = reconnect;
    if (reconnect) {
        m_BatteryReconnect.frame = NSMakeRect(k_BatteryPadding, y, width, k_RowHeight);
        y += k_RowHeight + 4;
    }

    m_BatteryLines[1].frame = NSMakeRect(left, y + 5, inner, 1);
    y += 11;

    m_BatterySettingsRow.frame = NSMakeRect(k_BatteryPadding, y, width, k_RowHeight);
    y += k_RowHeight;
    return y + k_BatteryPadding;
}

- (void)batteryChanged
{
    if (m_BatteryView == nil || m_Host == nil) {
        return;
    }
    CGFloat height = [self layoutBattery:[m_Host menusState]];
    NSRect frame = m_Panel.frame;
    if (m_Panel != nil && height != NSHeight(frame)) {
        m_BatteryContent.frame = NSMakeRect(0, 0, k_BatteryWidth, height);
        [m_Panel setFrame:NSMakeRect(NSMinX(frame), NSMaxY(frame) - height, NSWidth(frame), height) display:YES];
    }
}

// Control Center's bitrate, to look at: "Adaptive · 18 Mb/s" over the slider, disabled. Quality
// changes it. showBitrateTile updates it in place.
- (NSView*)bitrateTile:(const NotchQuality::State&)state width:(CGFloat)width
{
    NSView* tile = [[[ForkFlippedView alloc] initWithFrame:NSMakeRect(0, 0, width, 62)] autorelease];
    tile.wantsLayer = YES;
    tile.layer.cornerRadius = 16;
    tile.layer.backgroundColor = white(0.08);

    NSTextField* title = makeText(tr("Bitrate"), [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
    [title sizeToFit];
    title.frame = NSMakeRect(12, 10, NSWidth(title.frame), NSHeight(title.frame));
    [tile addSubview:title];
    m_BitrateTileDetail = makeText(@"", [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular], NSColor.secondaryLabelColor);
    m_BitrateTileDetail.alignment = NSTextAlignmentRight;
    [tile addSubview:m_BitrateTileDetail];

    m_BitrateTileBar = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlSlider owner:nil] autorelease];
    m_BitrateTileBar->m_ReadOnly = YES;
    m_BitrateTileBar->m_Enabled = NO;
    m_BitrateTileBar.frame = NSMakeRect(12 - k_Knob / 2, 34, width - 24 + k_Knob, 16);
    [m_BitrateTileBar setAccessibilityElement:NO];
    [tile addSubview:m_BitrateTileBar];

    [tile setAccessibilityElement:YES];
    [tile setAccessibilityRole:NSAccessibilityStaticTextRole];
    [self showBitrateTile:state];
    return tile;
}

- (void)showBitrateTile:(const NotchQuality::State&)state
{
    NSView* tile = m_BitrateTileDetail.superview;
    CGFloat width = NSWidth(tile.frame);
    int shown = NotchQuality::shownKbps(state);
    NSString* detail = (NotchQuality::saverCaps(state) && shown <= PowerRules::k_SaverKbps ? QCoreApplication::translate("NotchBar", "Battery Saver · %1") :
                        state.adapting ? QCoreApplication::translate("NotchBar", "Adaptive · %1")
                                       : QCoreApplication::translate("NotchBar", "Fixed · %1")).arg(mbpsText(shown)).toNSString();
    m_BitrateTileDetail.stringValue = detail;
    [m_BitrateTileDetail sizeToFit];
    CGFloat detailWidth = MIN(NSWidth(m_BitrateTileDetail.frame), width - 24);
    // On the title's line, at the right
    m_BitrateTileDetail.frame = NSMakeRect(width - 12 - detailWidth, 11, detailWidth, NSHeight(m_BitrateTileDetail.frame));

    NotchQuality::Range range = NotchQuality::range(state);
    m_BitrateTileBar->m_MinKbps = range.minKbps;
    m_BitrateTileBar->m_MaxKbps = range.maxKbps;
    m_BitrateTileBar->m_ValueKbps = MAX(range.minKbps, MIN(shown, range.maxKbps));
    [m_BitrateTileBar refreshAppearance];

    [tile setAccessibilityLabel:[NSString stringWithFormat:@"%@, %@", tr("Bitrate"), detail]];
}

- (void)powerChanged
{
    [self batteryChanged];
}

- (void)bitrateChanged
{
    if (m_Host == nil) {
        return;
    }
    if (m_BatteryView != nil) {
        // Whether the saver caps it live
        [self batteryChanged];
    }
    if (m_Slider != nil) {
        [self qualityChanged];
    }
    else if (m_BitrateTileDetail != nil) {
        [self showBitrateTile:[m_Host menusState].bitrate];
    }
}

// "This Mac is drive M:", "On GAMING-PC, over the LAN": shows only
- (NSView*)driveTile:(const NotchBar::MenuState&)state width:(CGFloat)width
{
    NSView* tile = [[[ForkFlippedView alloc] initWithFrame:NSMakeRect(0, 0, width, 56)] autorelease];
    tile.wantsLayer = YES;
    tile.layer.cornerRadius = 16;
    tile.layer.backgroundColor = white(0.08);

    NSView* circle = [[[NSView alloc] initWithFrame:NSMakeRect(10, 14, k_Circle, k_Circle)] autorelease];
    circle.wantsLayer = YES;
    circle.layer.cornerRadius = k_Circle / 2;
    circle.layer.backgroundColor = NSColor.controlAccentColor.CGColor;
    NSImage* image = symbol(@"externaldrive.fill", 14, NSFontWeightMedium);
    if (image != nil) {
        NSImageView* icon = [[[NSImageView alloc] initWithFrame:NSZeroRect] autorelease];
        icon.image = image;
        icon.imageScaling = NSImageScaleNone;
        icon.contentTintColor = NSColor.whiteColor;
        [icon setFrameSize:image.size];
        [icon setFrameOrigin:NSMakePoint(round((k_Circle - image.size.width) / 2), round((k_Circle - image.size.height) / 2))];
        [circle addSubview:icon];
    }
    [tile addSubview:circle];

    QString letter = state.driveLetter;
    NSString* title = (state.driveHomeFolder ? QCoreApplication::translate("NotchBar", "Your home folder is drive %1:")
                                             : QCoreApplication::translate("NotchBar", "This Mac is drive %1:")).arg(letter).toNSString();
    NSString* detail = QCoreApplication::translate("NotchBar", "On %1, over the LAN").arg(QString::fromNSString(m_HostName)).toNSString();
    CGFloat x = 10 + k_Circle + 9;
    NSTextField* titleLabel = makeText(title, [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
    titleLabel.frame = NSMakeRect(x, 11, width - x - 10, 17);
    [tile addSubview:titleLabel];
    NSTextField* detailLabel = makeText(detail, [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    detailLabel.frame = NSMakeRect(x, 28, width - x - 10, 16);
    [tile addSubview:detailLabel];

    [tile setAccessibilityElement:YES];
    [tile setAccessibilityRole:NSAccessibilityStaticTextRole];
    [tile setAccessibilityLabel:[NSString stringWithFormat:@"%@ %@", title, detail]];
    return tile;
}

- (void)controlHovered:(NSView*)control
{
    NSUInteger index = [m_Controls indexOfObject:(ForkMenuControl*)control];
    if (index != NSNotFound && [self selectable:(int)index]) {
        [self select:(int)index keyboard:NO];
    }
}

- (void)controlUnhovered:(NSView*)control
{
    // The pointer left what it selected; a selection the keyboard made stays
    NSUInteger index = [m_Controls indexOfObject:(ForkMenuControl*)control];
    if (index != NSNotFound && (int)index == m_Selected && !m_KeyboardSelection) {
        [self select:-1 keyboard:NO];
    }
}

- (void)controlActivated:(NSView*)view
{
    ForkMenuControl* control = (ForkMenuControl*)view;
    if (!control->m_Enabled || m_Host == nil) {
        return;
    }
    if (control->m_Kind == ForkMenuControlSlider) {
        // Dragged, or moved a step with the arrow keys
        return;
    }
    // Rebuilding drops the menu's controls, and this may run inside this one's mouseUp:
    [[control retain] autorelease];
    if (m_ListView != nil && control->m_Kind != ForkMenuControlChoice) {
        // Under an open list (VoiceOver can reach it there), or its opener again: the list closes
        [self closeList];
        return;
    }
    // Stream Settings' draft changes in the menus, at once; Apply and Save are actions
    switch (control->m_Local) {
    case ForkMenuLocalPreset:
        [m_Host menusStreamSettingsPreset:control->m_Value];
        [self rebuild];
        return;
    case ForkMenuLocalRow:
        [self openStreamSettingsList:control];
        return;
    case ForkMenuLocalPick: {
        int value = control->m_Value;
        [self closeList];
        [m_Host menusStreamSettingsPick:value >> 8 choice:value & 0xff];
        [self rebuild];
        return;
    }
    case ForkMenuLocalReset:
        [m_Host menusStreamSettingsReset];
        [self rebuild];
        return;
    case ForkMenuLocalNone:
        break;
    }
    if (control->m_Action == NotchMenus::Action::OpenStreamSettings) {
        [self open:NotchMenus::Menu::StreamSettings keyboard:m_KeyboardSelection];
        return;
    }
    if (control == m_TrackpadTile) {
        [self openTrackpadList];
        return;
    }
    if (control->m_Kind == ForkMenuControlChoice) {
        // The list goes, and the menu stays open to show what changed; the stream ends for a reconnect
        BOOL current = control->m_On;
        NotchMenus::Action action = control->m_Action;
        int value = control->m_Value;
        [self closeList];
        if (!current) {
            [m_Host menusPerform:action value:value];
        }
        return;
    }
    if (control == m_ResolutionButton) {
        // Opens or closes the resolutions under it
        m_ResolutionsShown = !m_ResolutionsShown;
        [self rebuild];
        return;
    }
    if (control->m_Action == NotchMenus::Action::None) {
        // The stream's own frame rate or resolution: nothing to reconnect for
        if (m_ResolutionsShown && control->m_Kind == ForkMenuControlRow) {
            m_ResolutionsShown = NO;
            BOOL keyboard = m_KeyboardSelection;
            [self rebuild];
            // Back on Resolution, as the choice it was on has gone
            NSUInteger row = [m_Controls indexOfObject:m_ResolutionButton];
            if (row != NSNotFound) {
                [self select:(int)row keyboard:keyboard];
            }
        }
        return;
    }
    NotchMenus::Action action = control->m_Action;
    // Switches stay open to show their new state; everything else ends with the menu
    BOOL staysOpen = control->m_Kind == ForkMenuControlToggle || control->m_Kind == ForkMenuControlSwitch ||
                     control->m_Kind == ForkMenuControlModule;
    if (control->m_Value != 0) {
        [m_Host menusPerform:action value:control->m_Value];
    }
    else {
        [m_Host menusPerform:action];
    }
    if (!staysOpen) {
        [self close];
    }
}

- (BOOL)handleKey:(int)scancode pressed:(BOOL)pressed shift:(BOOL)shift
{
    NSNumber* key = @(scancode);
    if (!pressed) {
        if ([m_OwedReleases containsObject:key]) {
            [m_OwedReleases removeObject:key];
            return YES;
        }
        return NO;
    }
    if (m_Open == NotchMenus::Menu::None || !isNavigationKey(scancode)) {
        return NO;
    }
    [m_OwedReleases addObject:key];

    int count = (int)m_Controls.count;
    auto selectable = [self](int i) { return [self selectable:i]; };
    switch (scancode) {
    case SDL_SCANCODE_ESCAPE:
        if (m_ListView != nil) {
            [self closeList];
        }
        else {
            [self close];
        }
        break;
    case SDL_SCANCODE_DOWN:
        [self select:NotchMenus::nextSelectable(count, m_Selected, 1, selectable) keyboard:YES];
        break;
    case SDL_SCANCODE_TAB:
        [self select:NotchMenus::nextSelectable(count, m_Selected, shift ? -1 : 1, selectable) keyboard:YES];
        break;
    case SDL_SCANCODE_UP:
        [self select:NotchMenus::nextSelectable(count, m_Selected, -1, selectable) keyboard:YES];
        break;
    case SDL_SCANCODE_HOME:
        [self select:NotchMenus::nextSelectable(count, -1, 1, selectable) keyboard:YES];
        break;
    case SDL_SCANCODE_END:
        [self select:NotchMenus::nextSelectable(count, -1, -1, selectable) keyboard:YES];
        break;
    case SDL_SCANCODE_LEFT:
    case SDL_SCANCODE_RIGHT: {
        int step = scancode == SDL_SCANCODE_LEFT ? -1 : 1;
        // A slider the keyboard selected moves, as a focused one does in macOS
        ForkMenuControl* selected = [self selectable:m_Selected] ? m_Controls[(NSUInteger)m_Selected] : nil;
        if (m_KeyboardSelection && selected != nil && selected->m_Kind == ForkMenuControlSlider) {
            [self slider:selected step:step];
            break;
        }
        if (m_ListView != nil) {
            // A list stays put, as a macOS menu's submenu-less items do
            break;
        }
        // Along a segmented control the keyboard selected, as in macOS; it stays at either end
        if (m_KeyboardSelection && selected != nil && selected->m_Kind == ForkMenuControlChip) {
            int next = m_Selected + step;
            if ([self selectable:next] && ((ForkMenuControl*)m_Controls[(NSUInteger)next])->m_Kind == ForkMenuControlChip) {
                [self select:next keyboard:YES];
            }
            break;
        }
        // To the next menu whose item is on screen; none, and this one stays open
        int menus = (int)NotchMenus::order().size();
        for (int i = 1; i < menus; i++) {
            NotchMenus::Menu next = NotchMenus::neighbour(m_Open, step * i);
            BOOL alignRight = NO;
            if (next != m_Open && !NSIsEmptyRect([m_Host menusAnchorFor:next alignRight:&alignRight])) {
                [self open:next keyboard:YES];
                break;
            }
        }
        break;
    }
    case SDL_SCANCODE_RETURN:
    case SDL_SCANCODE_KP_ENTER:
    case SDL_SCANCODE_SPACE:
        if ([self selectable:m_Selected]) {
            [self controlActivated:m_Controls[(NSUInteger)m_Selected]];
        }
        break;
    default:
        break;
    }
    return YES;
}
@end
