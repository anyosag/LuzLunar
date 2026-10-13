#include "fork/windowchrome.h"

#include <QVariantMap>

#import <AppKit/AppKit.h>

// Owns the NSToolbar and its items. The toolbar's delegate is a weak reference, so this
// controller lives as long as ForkWindowChrome.
@interface ForkToolbarController : NSObject <NSToolbarDelegate>
{
    ForkWindowChrome* m_Owner;
    NSToolbar* m_Toolbar;
    NSArray<NSString*>* m_ItemIds;          // the items QML declared, in its order
    NSArray<NSString*>* m_ToolbarOrder;     // the same with the system spacers
    NSMutableDictionary<NSString*, NSToolbarItem*>* m_Items;
    NSMutableDictionary<NSString*, NSString*>* m_Symbols;   // the SF Symbol each item shows
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
        m_Items = [[NSMutableDictionary alloc] init];
        m_Symbols = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    m_Toolbar.delegate = nil;
    [m_Toolbar release];
    [m_ItemIds release];
    [m_ToolbarOrder release];
    [m_Items release];
    [m_Symbols release];
    [super dealloc];
}

// Creates a fresh toolbar for this set of item ids
- (void)rebuildWithIds:(NSArray<NSString*>*)ids items:(const QVariantList&)items
{
    m_Toolbar.delegate = nil;
    [m_Toolbar release];
    [m_Items removeAllObjects];
    [m_Symbols removeAllObjects];

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

    for (NSString* itemId in ids) {
        NSToolbarItem* toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemId] autorelease];
        toolbarItem.target = self;
        toolbarItem.action = @selector(itemClicked:);
        toolbarItem.bordered = YES;
        m_Items[itemId] = toolbarItem;
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
        [self rebuildWithIds:ids items:items];
    }

    for (const QVariant& value : items) {
        QVariantMap item = value.toMap();
        NSToolbarItem* toolbarItem = m_Items[item.value("id").toString().toNSString()];
        NSString* label = item.value("label").toString().toNSString();
        NSString* symbol = item.value("symbol").toString().toNSString();
        QString toolTip = item.value("toolTip").toString();

        if (![toolbarItem.label isEqualToString:label]) {
            toolbarItem.label = label;
        }
        if (![m_Symbols[toolbarItem.itemIdentifier] isEqualToString:symbol]) {
            toolbarItem.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
            m_Symbols[toolbarItem.itemIdentifier] = symbol;
        }
        toolbarItem.toolTip = (toolTip.isEmpty() ? item.value("label").toString() : toolTip).toNSString();
        toolbarItem.navigational = item.value("navigational").toBool();
        if (@available(macOS 15.0, *)) {
            toolbarItem.hidden = !item.value("visible", true).toBool();
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
    return m_Items[itemIdentifier];
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

    NSView* view = reinterpret_cast<NSView*>(m_Window->winId());
    NSWindow* window = view.window;
    if (window == nil) {
        return;
    }

    [(ForkToolbarController*)m_Platform applyItems:m_Items
                                          toWindow:window
                                           visible:m_ToolbarVisible
                                          subtitle:m_Subtitle.toNSString()];

    if (!m_Active) {
        m_Active = true;
        emit activeChanged();
    }
}
