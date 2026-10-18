#include "fork/windowchrome.h"

#include <QGuiApplication>
#include <QVariantMap>

#import <AppKit/AppKit.h>

// Owns the NSToolbar. The toolbar's delegate is a weak reference, so this controller lives as
// long as ForkWindowChrome. AppKit asks the delegate for a new item whenever it needs one, so
// what each item shows is kept as state, used for new items and copied onto the live ones.
@interface ForkToolbarController : NSObject <NSToolbarDelegate>
{
    ForkWindowChrome* m_Owner;
    NSToolbar* m_Toolbar;
    NSArray<NSString*>* m_ItemIds;          // the items QML declared, in its order
    NSArray<NSString*>* m_ToolbarOrder;     // the same with the system spacers
    // Per item id: label, symbol, image (built once per symbol), toolTip, navigational, hidden,
    // focused, labeled
    NSMutableDictionary<NSString*, NSMutableDictionary*>* m_State;
}
- (instancetype)initWithOwner:(ForkWindowChrome*)owner;
- (void)applyItems:(const QVariantList&)items
          toWindow:(NSWindow*)window
           visible:(BOOL)visible
          subtitle:(NSString*)subtitle;
@end

@implementation ForkToolbarController

- (instancetype)initWithOwner:(ForkWindowChrome*)owner
{
    self = [super init];
    if (self) {
        m_Owner = owner;
        m_State = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    m_Toolbar.delegate = nil;
    [m_Toolbar release];
    [m_ItemIds release];
    [m_ToolbarOrder release];
    [m_State release];
    [super dealloc];
}

// The window's ground, opaque as in the design: the title bar and the native toolbar sit on the
// toolbar color (Night #0E1328 in dark mode, Day #E4E7F1 in light, as ForkTheme.bar in
// app/gui/ForkThemeData.qml) above a hairline, and QML draws the page below in ForkTheme.bg
- (void)installGroundInWindow:(NSWindow*)window
{
    window.opaque = YES;
    window.backgroundColor = [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
                     isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithSRGBRed:14 / 255.0 green:19 / 255.0 blue:40 / 255.0 alpha:1]
                    : [NSColor colorWithSRGBRed:228 / 255.0 green:231 / 255.0 blue:241 / 255.0 alpha:1];
    }];
    window.titlebarAppearsTransparent = YES;
    window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
}

// Creates a fresh toolbar for this set of item ids
- (void)rebuildWithIds:(NSArray<NSString*>*)ids items:(const QVariantList&)items
{
    m_Toolbar.delegate = nil;
    [m_Toolbar release];

    // Back buttons first (the system places navigational items before the title),
    // then a flexible space so the other buttons sit at the trailing edge
    NSMutableArray<NSString*>* order = [NSMutableArray array];
    for (const QVariant& value : items) {
        QVariantMap item = value.toMap();
        if (item.value("navigational").toBool()) {
            [order addObject:item.value("id").toString().toNSString()];
        }
    }
    [order addObject:NSToolbarFlexibleSpaceItemIdentifier];
    for (const QVariant& value : items) {
        QVariantMap item = value.toMap();
        if (!item.value("navigational").toBool()) {
            [order addObject:item.value("id").toString().toNSString()];
        }
    }

    [m_ItemIds release];
    m_ItemIds = [ids copy];
    [m_ToolbarOrder release];
    m_ToolbarOrder = [order copy];

    m_Toolbar = [[NSToolbar alloc] initWithIdentifier:@"LuzLunarMainToolbar"];
    m_Toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    m_Toolbar.allowsUserCustomization = NO;
    m_Toolbar.autosavesConfiguration = NO;
    m_Toolbar.delegate = self;
}

- (void)applyItems:(const QVariantList&)items
          toWindow:(NSWindow*)window
           visible:(BOOL)visible
          subtitle:(NSString*)subtitle
{
    NSMutableArray<NSString*>* ids = [NSMutableArray array];
    for (const QVariant& value : items) {
        [ids addObject:value.toMap().value("id").toString().toNSString()];
    }
    if (m_Toolbar == nil || ![ids isEqualToArray:m_ItemIds]) {
        // Toolbars with the same identifier stay in sync, so detach the old one first
        if (m_Toolbar != nil && window.toolbar == m_Toolbar) {
            window.toolbar = nil;
        }
        [self rebuildWithIds:ids items:items];
    }

    // The state has to be complete before AppKit asks for items, which reading
    // m_Toolbar.items or attaching the toolbar can do
    [self updateStateWithItems:items];
    for (NSToolbarItem* toolbarItem in m_Toolbar.items) {
        NSDictionary* state = m_State[toolbarItem.itemIdentifier];
        if (state != nil) {
            [self configureItem:toolbarItem fromState:state];
        }
    }

    // Keyboard and gamepad focus lives on the clipped QML buttons, so show it on the native item.
    // macOS 26 makes the focused item prominent (configureItem); earlier versions select it.
    if (@available(macOS 26.0, *)) {
    }
    else {
        NSString* focusedId = nil;
        for (NSString* itemId in m_ItemIds) {
            NSDictionary* state = m_State[itemId];
            if ([state[@"focused"] boolValue] && ![state[@"hidden"] boolValue]) {
                focusedId = itemId;
                break;
            }
        }
        if (!(focusedId == m_Toolbar.selectedItemIdentifier || [focusedId isEqualToString:m_Toolbar.selectedItemIdentifier])) {
            m_Toolbar.selectedItemIdentifier = focusedId;
        }
    }

    if (window.toolbar != m_Toolbar) {
        window.toolbar = m_Toolbar;
    }
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titleVisibility = NSWindowTitleVisible;
    [self installGroundInWindow:window];
    m_Toolbar.visible = visible;
    window.subtitle = subtitle ?: @"";
}

- (void)updateStateWithItems:(const QVariantList&)items
{
    for (const QVariant& value : items) {
        QVariantMap item = value.toMap();
        NSString* itemId = item.value("id").toString().toNSString();
        NSMutableDictionary* state = m_State[itemId];
        if (state == nil) {
            state = [NSMutableDictionary dictionary];
            m_State[itemId] = state;
        }

        NSString* label = item.value("label").toString().toNSString();
        NSString* symbol = item.value("symbol").toString().toNSString();
        QString toolTip = item.value("toolTip").toString();

        if (![state[@"symbol"] isEqualToString:symbol]) {
            state[@"symbol"] = symbol;
            NSImage* image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
            if (image != nil) {
                state[@"image"] = image;
            }
            else {
                [state removeObjectForKey:@"image"];
            }
        }
        state[@"label"] = label;
        state[@"toolTip"] = (toolTip.isEmpty() ? item.value("label").toString() : toolTip).toNSString();
        state[@"navigational"] = @(item.value("navigational").toBool());
        state[@"hidden"] = @(!item.value("visible", true).toBool());
        state[@"focused"] = @(item.value("focused").toBool());
        state[@"labeled"] = @(item.value("labeled").toBool());
    }
}

- (void)configureItem:(NSToolbarItem*)toolbarItem fromState:(NSDictionary*)state
{
    NSString* label = state[@"label"];
    if (![toolbarItem.label isEqualToString:label]) {
        toolbarItem.label = label;
    }
    NSImage* image = state[@"image"];
    if ([state[@"labeled"] boolValue]) {
        // A button with the symbol and its label side by side ("Add PC"), as its own view
        NSButton* button = [toolbarItem.view isKindOfClass:NSButton.class] ? (NSButton*)toolbarItem.view : nil;
        if (button == nil) {
            button = [NSButton buttonWithTitle:label target:self action:@selector(buttonClicked:)];
            button.bezelStyle = NSBezelStyleToolbar;
            button.imagePosition = NSImageLeading;
            button.identifier = toolbarItem.itemIdentifier;
            toolbarItem.view = button;
        }
        if (![button.title isEqualToString:label]) {
            button.title = label;
        }
        if (button.image != image) {
            button.image = image;
        }
        button.toolTip = state[@"toolTip"];
    }
    else if (toolbarItem.image != image) {
        toolbarItem.image = image;
    }
    toolbarItem.toolTip = state[@"toolTip"];
    toolbarItem.navigational = [state[@"navigational"] boolValue];
    if (@available(macOS 15.0, *)) {
        BOOL hidden = [state[@"hidden"] boolValue];
        if (toolbarItem.hidden != hidden) {
            toolbarItem.hidden = hidden;
        }
    }
    if (@available(macOS 26.0, *)) {
        // Tinted with the accent color while its QML button has keyboard focus
        NSToolbarItemStyle style = [state[@"focused"] boolValue] ? NSToolbarItemStyleProminent : NSToolbarItemStylePlain;
        if (toolbarItem.style != style) {
            toolbarItem.style = style;
        }
    }
}

- (void)itemClicked:(NSToolbarItem*)sender
{
    // A click selects a selectable item; only keyboard focus should leave it highlighted
    m_Toolbar.selectedItemIdentifier = nil;
    m_Owner->notifyTriggered(QString::fromNSString(sender.itemIdentifier));
}

- (void)buttonClicked:(NSButton*)sender
{
    m_Owner->notifyTriggered(QString::fromNSString(sender.identifier));
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    (void)toolbar;
    return m_ToolbarOrder;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    (void)toolbar;
    return m_ToolbarOrder;
}

// Before macOS 26, selection is how the item whose QML button has keyboard focus is highlighted.
// On macOS 26 selectable items lose the Liquid Glass button group, so none are selectable there.
- (NSArray<NSToolbarItemIdentifier>*)toolbarSelectableItemIdentifiers:(NSToolbar*)toolbar
{
    (void)toolbar;
    if (@available(macOS 26.0, *)) {
        return @[];
    }
    return m_ItemIds;
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar
    itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
willBeInsertedIntoToolbar:(BOOL)flag
{
    (void)toolbar;
    (void)flag;

    // AppKit requires a new item on every call. Never return nil: the toolbar would drop the item.
    NSToolbarItem* toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    toolbarItem.target = self;
    toolbarItem.action = @selector(itemClicked:);
    toolbarItem.bordered = YES;

    NSDictionary* state = m_State[itemIdentifier];
    if (state != nil) {
        [self configureItem:toolbarItem fromState:state];
    }
    return toolbarItem;
}

@end

ForkWindowChrome::~ForkWindowChrome()
{
    [(ForkToolbarController*)m_Platform release];
    if (m_MotionObserver != nullptr) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:(id)m_MotionObserver];
        [(id)m_MotionObserver release];
    }
}

bool ForkWindowChrome::reduceMotion()
{
    // Follow the setting from the first time QML asks
    if (m_MotionObserver == nullptr) {
        id observer = [NSWorkspace.sharedWorkspace.notificationCenter
            addObserverForName:NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification*) { emit reduceMotionChanged(); }];
        m_MotionObserver = [observer retain];
    }
    return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
}

void ForkWindowChrome::attach(QWindow* window)
{
    // Showing and hiding toolbar items needs macOS 15. Older versions keep the QML toolbar.
    if (@available(macOS 15.0, *)) {
    }
    else {
        return;
    }

    if (window == nullptr || window == m_Window) {
        return;
    }

    // Only a Cocoa window has an NSView behind winId(); the offscreen platform (screenshots) has none
    if (QGuiApplication::platformName() != QLatin1String("cocoa")) {
        return;
    }
    m_Window = window;

    if (m_Platform == nullptr) {
        m_Platform = [[ForkToolbarController alloc] initWithOwner:this];
    }

    // The NSWindow may only exist once the window is shown
    connect(window, &QWindow::visibleChanged, this, [this](bool) { apply(); });
    apply();
}

void ForkWindowChrome::apply()
{
    if (m_Platform == nullptr || m_Window == nullptr || m_Items.isEmpty()) {
        return;
    }

    // The first call comes from QML's Component.onCompleted, before the event loop's pool exists
    @autoreleasepool {
        NSView* view = reinterpret_cast<NSView*>(m_Window->winId());
        NSWindow* window = view.window;
        if (window == nil) {
            return;
        }

        [(ForkToolbarController*)m_Platform applyItems:m_Items
                                              toWindow:window
                                               visible:m_ToolbarVisible
                                              subtitle:m_Subtitle.toNSString()];
    }

    if (!m_Active) {
        m_Active = true;
        emit activeChanged();
    }
}
