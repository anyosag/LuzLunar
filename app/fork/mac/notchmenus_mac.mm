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
    const CGFloat k_MenuGap = 4;        // between the bar and a menu
    const CGFloat k_ScreenMargin = 6;   // between a menu and the screen's edge

    // Session menu
    const CGFloat k_SessionWidth = 260;
    const CGFloat k_SessionPadding = 5;
    const CGFloat k_HeaderHeight = 22;
    const CGFloat k_RowHeight = 24;
    const CGFloat k_SeparatorHeight = 11;

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
    return self;
}

- (void)dealloc
{
    [_onPress release];
    [m_Icon release];
    [m_Label release];
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

- (CGFloat)naturalWidth
{
    CGFloat width = 2 * k_ItemPadding;
    CGFloat iconWidth = m_Icon != nil ? NSWidth(m_Icon.frame) : 0;
    CGFloat labelWidth = m_Label.hidden ? 0 : NSWidth(m_Label.frame);
    width += iconWidth + labelWidth;
    if (iconWidth > 0 && labelWidth > 0) {
        width += k_ItemGap;
    }
    return ceil(width);
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
    if (!m_Label.hidden) {
        CGFloat labelHeight = NSHeight(m_Label.frame);
        m_Label.frame = NSMakeRect(x, round((size.height - labelHeight) / 2), MAX(size.width - x - k_ItemPadding, 0), labelHeight);
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
};

@class ForkNotchMenus;

@interface ForkNotchMenus ()
- (void)controlHovered:(NSView*)control;
- (void)controlActivated:(NSView*)control;
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
}
- (instancetype)initWithKind:(ForkMenuControlKind)kind owner:(ForkNotchMenus*)owner;
- (void)setTitle:(NSString*)title detail:(NSString*)detail symbol:(NSString*)name;
- (void)refreshAppearance;
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
    }

    BOOL actionable = kind == ForkMenuControlRow || kind == ForkMenuControlToggle || kind == ForkMenuControlTile;
    [self setAccessibilityElement:kind != ForkMenuControlSeparator];
    [self setAccessibilityRole:kind == ForkMenuControlRow ? NSAccessibilityMenuItemRole :
                               kind == ForkMenuControlToggle ? NSAccessibilityCheckBoxRole :
                               actionable ? NSAccessibilityButtonRole : NSAccessibilityStaticTextRole];
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
    [self setAccessibilityLabel:title];
    if (m_Kind == ForkMenuControlToggle) {
        [self setAccessibilityValue:detail];
    }
    else if (m_Kind == ForkMenuControlRow && detail.length > 0) {
        [self setAccessibilityHelp:detail];
    }
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
    }
}

- (void)centerIcon
{
    NSSize iconSize = m_Icon.frame.size;
    [m_Icon setFrameOrigin:NSMakePoint(round((k_Circle - iconSize.width) / 2), round((k_Circle - iconSize.height) / 2))];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    if (m_Kind == ForkMenuControlSeparator) {
        [[NSColor colorWithWhite:1 alpha:0.12] setFill];
        NSRectFill(NSMakeRect(9, round(NSHeight(self.bounds) / 2), NSWidth(self.bounds) - 18, 1));
    }
}

- (BOOL)wantsUpdateLayer
{
    return m_Kind != ForkMenuControlSeparator;
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
    [self refreshAppearance];
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent*)event
{
    (void)event;
    m_Pressed = m_Enabled && m_Kind != ForkMenuControlHeader && m_Kind != ForkMenuControlSeparator;
    [self refreshAppearance];
}

- (void)mouseUp:(NSEvent*)event
{
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
    if (!m_Enabled || m_Kind == ForkMenuControlHeader || m_Kind == ForkMenuControlSeparator) {
        return NO;
    }
    [m_Owner controlActivated:self];
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
    [m_Controls removeAllObjects];
    NotchBar::MenuState state = m_Host != nil ? [m_Host menusState] : NotchBar::MenuState();

    ForkFlippedView* content = [[[ForkFlippedView alloc] initWithFrame:NSZeroRect] autorelease];

    if (m_Open == NotchMenus::Menu::Session) {
        CGFloat width = k_SessionWidth - 2 * k_SessionPadding;
        CGFloat y = k_SessionPadding;
        auto add = [&](ForkMenuControlKind kind, NSString* title, NSString* detail, NotchMenus::Action action, BOOL enabled) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:kind owner:self] autorelease];
            control->m_Action = action;
            control->m_Enabled = enabled;
            [control setTitle:title detail:detail symbol:nil];
            CGFloat height = kind == ForkMenuControlHeader ? k_HeaderHeight :
                             kind == ForkMenuControlSeparator ? k_SeparatorHeight : k_RowHeight;
            control.frame = NSMakeRect(k_SessionPadding, y, width, height);
            [content addSubview:control];
            [m_Controls addObject:control];
            y += height;
        };
        add(ForkMenuControlHeader,
            QCoreApplication::translate("NotchBar", "%1 on %2").arg(QString::fromNSString(m_AppName), QString::fromNSString(m_HostName)).toNSString(),
            nil, NotchMenus::Action::None, NO);
        add(ForkMenuControlRow, tr("Disconnect"), @"⌃⌥⇧Q", NotchMenus::Action::Disconnect, YES);
        add(ForkMenuControlRow, tr("Disconnect and Quit LuzLunar"), nil, NotchMenus::Action::DisconnectAndQuitLuzLunar, YES);
        add(ForkMenuControlSeparator, nil, nil, NotchMenus::Action::None, NO);
        add(ForkMenuControlRow,
            QCoreApplication::translate("NotchBar", "Quit %1 on PC").arg(QString::fromNSString(m_AppName)).toNSString(),
            nil, NotchMenus::Action::QuitAppOnPc, YES);
        add(ForkMenuControlRow,
            QCoreApplication::translate("NotchBar", "Quit %1 and Sleep PC").arg(QString::fromNSString(m_AppName)).toNSString(),
            nil, NotchMenus::Action::QuitAndSleepPc, state.canSleepPc);
        *size = NSMakeSize(k_SessionWidth, y + k_SessionPadding);
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
        CGFloat groupY = 10;
        auto addToggle = [&](NSString* title, NSString* detail, NSString* name, BOOL on, NotchMenus::Action action) {
            ForkMenuControl* control = [[[ForkMenuControl alloc] initWithKind:ForkMenuControlToggle owner:self] autorelease];
            control->m_Action = action;
            control->m_On = on;
            [control setTitle:title detail:detail symbol:name];
            [control setAccessibilityValue:on ? @1 : @0];
            control.frame = NSMakeRect(10, groupY, width - 20, k_ToggleHeight);
            [group addSubview:control];
            [m_Controls addObject:control];
            groupY += k_ToggleHeight + 6;
        };
        addToggle(tr("Mac Shortcuts"), state.systemKeysToPc ? tr("Sent to the PC") : tr("Kept on the Mac"),
                  @"keyboard", state.systemKeysToPc, NotchMenus::Action::ToggleSystemKeys);
        addToggle(tr("Mouse"), state.mouseCaptured ? tr("Captured · ⌃⌥⇧Z") : tr("Free · ⌃⌥⇧Z"),
                  @"cursorarrow", state.mouseCaptured, NotchMenus::Action::ToggleMouseCapture);
        groupY += 4;
        group.frame = NSMakeRect(k_CenterPadding, y, width, groupY - 6);
        y += NSHeight(group.frame) + k_TileGap;

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
    if (menu == NotchMenus::Menu::None || m_Host == nil) {
        [self close];
        return;
    }
    BOOL wasOpen = m_Open != NotchMenus::Menu::None;
    [self removePanel];
    m_Open = menu;
    m_Selected = -1;

    BOOL alignRight = NO;
    NSRect anchor = [m_Host menusAnchorFor:menu alignRight:&alignRight];
    if (NSIsEmptyRect(anchor)) {
        m_Open = NotchMenus::Menu::None;
        if (wasOpen) {
            [m_Host menusChanged:NotchMenus::Menu::None];
        }
        return;
    }

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
    effect.layer.cornerRadius = menu == NotchMenus::Menu::ControlCenter ? 22 : 12;
    effect.layer.masksToBounds = YES;
    effect.layer.borderWidth = 1;
    effect.layer.borderColor = white(0.10);
    [effect addSubview:content];
    m_Panel.contentView = effect;

    [m_Panel setAccessibilityRole:menu == NotchMenus::Menu::Session ? NSAccessibilityMenuRole : NSAccessibilityGroupRole];
    [m_Panel setAccessibilityLabel:menu == NotchMenus::Menu::Session ? tr("Session") : tr("Stream Control Center")];

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

    // A click anywhere but the menu and the bar closes it, and goes no further: not to the PC
    if (m_ClickMonitor == nil) {
        m_ClickMonitor = [[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown
                                                                handler:^NSEvent*(NSEvent* event) {
            if (m_Open == NotchMenus::Menu::None || event.window == m_Panel || event.window == [m_Host menusBarWindow]) {
                return event;
            }
            [self close];
            return nil;
        }] retain];
    }

    [m_Host menusChanged:menu];
}

// Closes the panel without telling the bar
- (void)removePanel
{
    [m_Panel orderOut:nil];
    [m_Panel close];
    [m_Panel release];
    m_Panel = nil;
    [m_Controls removeAllObjects];
    m_Selected = -1;
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

- (void)controlHovered:(NSView*)control
{
    NSUInteger index = [m_Controls indexOfObject:(ForkMenuControl*)control];
    if (index != NSNotFound && [self selectable:(int)index]) {
        [self select:(int)index keyboard:NO];
    }
}

- (void)controlActivated:(NSView*)view
{
    ForkMenuControl* control = (ForkMenuControl*)view;
    if (!control->m_Enabled || m_Host == nil) {
        return;
    }
    NotchMenus::Action action = control->m_Action;
    // Switches stay open to show their new state; everything else ends with the menu
    BOOL staysOpen = control->m_Kind == ForkMenuControlToggle;
    [m_Host menusPerform:action];
    if (!staysOpen) {
        [self close];
    }
}

- (BOOL)handleKey:(int)scancode pressed:(BOOL)pressed
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
    case SDL_SCANCODE_TAB:
        [self select:NotchMenus::nextSelectable(count, m_Selected, 1, selectable) keyboard:YES];
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
    case SDL_SCANCODE_RIGHT:
        [self open:NotchMenus::neighbour(m_Open, scancode == SDL_SCANCODE_LEFT ? -1 : 1) keyboard:YES];
        break;
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
