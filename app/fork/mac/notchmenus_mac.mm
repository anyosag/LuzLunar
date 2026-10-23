#include "notchmenus_mac.h"

#include "SDL_compat.h"

#include <QCoreApplication>
#include <QString>

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
}
- (instancetype)initWithKind:(ForkMenuControlKind)kind owner:(ForkNotchMenus*)owner;
- (void)setTitle:(NSString*)title detail:(NSString*)detail symbol:(NSString*)name;
// The width a row or header needs for its title and shortcut
- (CGFloat)naturalWidth;
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
        self.layer.cornerRadius = kind == ForkMenuControlTile ? 16 : 8;
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
            m_Detail = [makeText(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor) retain];
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
    }

    BOOL actionable = kind == ForkMenuControlRow || kind == ForkMenuControlToggle || kind == ForkMenuControlTile;
    [self setAccessibilityElement:kind != ForkMenuControlSeparator];
    [self setAccessibilityRole:kind == ForkMenuControlRow ? NSAccessibilityMenuItemRole :
                               kind == ForkMenuControlToggle || kind == ForkMenuControlSwitch ? NSAccessibilityCheckBoxRole :
                               kind == ForkMenuControlSlider ? NSAccessibilitySliderRole :
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
    if (m_Icon != nil) {
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
    CGFloat width = 18 + NSWidth(m_Title.frame);
    if (m_Detail != nil && m_Detail.stringValue.length > 0) {
        [m_Detail sizeToFit];
        width += 12 + NSWidth(m_Detail.frame);
    }
    return ceil(width);
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
        [m_Detail sizeToFit];
        CGFloat x = k_Circle + 9;
        CGFloat width = MAX(size.width - x, 0);
        CGFloat titleHeight = NSHeight(m_Title.frame);
        CGFloat detailHeight = NSHeight(m_Detail.frame);
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
    case ForkMenuControlTile: {
        CGFloat background = m_Kind == ForkMenuControlTile ? (m_Pressed ? 0.20 : (m_Hovered ? 0.12 : 0.08))
                                                            : (m_Pressed ? 0.12 : (m_Hovered ? 0.06 : 0));
        self.layer.backgroundColor = white(background);
        self.layer.borderWidth = m_KeyboardSelected && m_Selected ? 2 : 0;
        self.layer.borderColor = accent.CGColor;
        BOOL filled = m_Kind == ForkMenuControlToggle && m_On;
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
    m_Hovered = YES;
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
    // Quality's Stream Battery Saver note
    NSView* m_SaverBox;
    NSTextField* m_SaverText;
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
        [self buildQuality:content state:state.bitrate];
        *size = NSMakeSize(k_QualityWidth, [self layoutQuality]);
    }
    else if (m_Open == NotchMenus::Menu::Battery) {
        [self buildBattery:content];
        *size = NSMakeSize(k_BatteryWidth, [self layoutBattery:state]);
    }
    else if (m_Open == NotchMenus::Menu::ControlCenter) {
        CGFloat width = k_CenterWidth - 2 * k_CenterPadding;
        CGFloat y = k_CenterPadding;

        // The switches, in one tile
        NSView* group = [[[ForkFlippedView alloc] initWithFrame:NSZeroRect] autorelease];
        group.wantsLayer = YES;
        group.layer.cornerRadius = 16;
        group.layer.backgroundColor = white(0.08);
        [content addSubview:group];
        CGFloat groupY = k_CenterPadding;
        auto addToggle = [&](NSString* title, NSString* detail, NSString* name, BOOL on, NotchMenus::Action action, BOOL enabled) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlToggle owner:self] autorelease];
            control->m_Action = action;
            control->m_On = on;
            control->m_Enabled = enabled;
            [control setTitle:title detail:detail symbol:name];
            [control setAccessibilityValue:on ? @1 : @0];
            control.frame = NSMakeRect(10, groupY, width - 20, k_ToggleHeight);
            [group addSubview:control];
            [m_Controls addObject:control];
            groupY += k_ToggleHeight + 6;
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
        addToggle(tr("Notch Stats"), state.notchStatsShown ? tr("Shown") : tr("Hidden"),
                  @"chart.bar.fill", state.notchStatsShown, NotchMenus::Action::ToggleNotchStats, YES);
        // The last switch's gap below it becomes the tile's padding
        group.frame = NSMakeRect(k_CenterPadding, y, width, groupY - 6 + k_CenterPadding);
        y += NSHeight(group.frame) + k_TileGap;

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
    NSView* content = [self buildContent:&size];

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
                                menu == NotchMenus::Menu::Battery ? 14 : 12;
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
                                  menu == NotchMenus::Menu::Battery ? tr("Battery") : tr("Stream Control Center")];

    // Under its item, kept on the screen
    NSScreen* screen = [m_Host menusBarWindow].screen;
    NSRect screenFrame = screen != nil ? screen.frame : NSMakeRect(0, 0, 10000, 10000);
    CGFloat x = alignRight ? NSMaxX(anchor) - size.width : NSMinX(anchor);
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
- (void)buildQuality:(NSView*)content state:(const NotchQuality::State&)state
{
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

    [self showQuality:state];
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
        m_Caption.stringValue = tr("Changing it takes a new stream.");
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
    y += captionHeight;
    return y + 6 + k_QualityPadding;
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
    NotchMenus::Action action = control->m_Action;
    // Switches stay open to show their new state; everything else ends with the menu
    BOOL staysOpen = control->m_Kind == ForkMenuControlToggle || control->m_Kind == ForkMenuControlSwitch;
    [m_Host menusPerform:action];
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
        [self close];
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
