#pragma once

// [fork] The notch bar's clickable items and the menus under them (notchmenus_mac.mm), for
// notchbar.mm. Objective-C++ only.

#ifdef __OBJC__

#import <AppKit/AppKit.h>

#include "fork/notchmenus.h"
#include "notchbar.h"
#include "notchstatus_mac.h"

// An item on the bar: an SF Symbol and a title, lit while the pointer is over it or its menu is open.
// It answers the first click without taking focus from the stream.
@interface ForkBarItem : NSView
- (instancetype)initWithSymbol:(NSString*)symbol;
// Another SF Symbol, or none for nil
- (void)setSymbol:(NSString*)symbol;
// In a color of its own; nil for the title's
- (void)setSymbol:(NSString*)symbol tint:(NSColor*)tint;
// Called on mouse down, as macOS's menu bar opens its menus
@property (nonatomic, copy) void (^onPress)(void);
// False for an item that only shows something (the stats)
@property (nonatomic) BOOL interactive;
@property (nonatomic) BOOL open;
- (void)setTitle:(NSAttributedString*)title;
// The width the icon and title need
- (CGFloat)naturalWidth;
// The width the icon needs alone
- (CGFloat)iconOnlyWidth;
@end

// What the menus need from the bar
@protocol ForkNotchMenusHost <NSObject>
- (void)menusPerform:(NotchMenus::Action)action;
// SetBitrate's kbps
- (void)menusPerform:(NotchMenus::Action)action value:(int)value;
- (NotchBar::MenuState)menusState;
// What Stream status shows now
- (void)menusStatus:(ForkStatusModel*)model;
// Where a menu hangs from: its item on screen (in the bar's strip), and whether the menu lines up
// with the item's right edge. NSZeroRect when the item isn't on screen.
- (NSRect)menusAnchorFor:(NotchMenus::Menu)menu alignRight:(BOOL*)alignRight;
// The menu that's open now, or None
- (void)menusChanged:(NotchMenus::Menu)menu;
// Clicks in the bar don't close the menus; the bar's items do that themselves
- (NSWindow*)menusBarWindow;
@end

// The open menu: one at a time, in a panel under its item that never takes focus from the stream.
// Clicking the stream or pressing Escape closes it; the click doesn't reach the PC.
@interface ForkNotchMenus : NSObject
- (instancetype)initWithHost:(id<ForkNotchMenusHost>)host appName:(NSString*)appName hostName:(NSString*)hostName;
// keyboard: opened with Control-Option-Shift-N, so the first row is selected
- (void)open:(NotchMenus::Menu)menu keyboard:(BOOL)keyboard;
- (void)close;
- (NotchMenus::Menu)openMenu;
// An SDL scancode; YES when the menu took it. Releases of keys it took are its own too. shift:
// Shift-Tab goes up.
- (BOOL)handleKey:(int)scancode pressed:(BOOL)pressed shift:(BOOL)shift;
// Shows MenuState again; Stream status updates in place
- (void)refresh;
// Stream status shows what's new, if it's open
- (void)statusChanged;
// Quality shows what's new, if it's open
- (void)qualityChanged;
- (void)invalidate;
@end

#endif
