#include "fork/windowchrome.h"

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
    // Per item id: label, symbol, image (built once per symbol), toolTip, navigational, hidden
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

    if (window.toolbar != m_Toolbar) {
        window.toolbar = m_Toolbar;
    }
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.titleVisibility = NSWindowTitleVisible;
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
    }
}

- (void)configureItem:(NSToolbarItem*)toolbarItem fromState:(NSDictionary*)state
{
    NSString* label = state[@"label"];
    if (![toolbarItem.label isEqualToString:label]) {
        toolbarItem.label = label;
    }
    NSImage* image = state[@"image"];
    if (toolbarItem.image != image) {
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
}

- (void)itemClicked:(NSToolbarItem*)sender
{
    m_Owner->notifyTriggered(QString::fromNSString(sender.itemIdentifier));
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
