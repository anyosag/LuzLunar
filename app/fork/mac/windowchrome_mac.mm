#include "fork/windowchrome.h"

#include <QGuiApplication>

#include <cstdlib>
#include <cstring>

#import <AppKit/AppKit.h>

// The main window draws its own 52 px header in QML, under a transparent title bar, in a full-size
// content view (the QML window asks for that with Qt::ExpandedClientAreaHint and
// Qt::NoTitleBarBackgroundHint, because Qt rewrites the style mask on every flags change). What is
// left to do natively lives here:
//   - hide the title and the title bar's separator, and give the window the sky's ground colour, so
//     a live resize never flashes anything else;
//   - put the real traffic lights where the design has them: 12 pt discs at x 20, 40 and 60, their
//     centres 25.5 pt below the top (an empty unified toolbar would centre them in 52 pt too, but
//     an NSToolbar can take the clicks of the band under it, which the header's buttons need).
//     Setting LUZLUNAR_LIGHTS=toolbar in the environment tries that instead.
@interface ForkChromeController : NSObject
{
    NSWindow* m_Window;        // weak: the window outlives its observers, which are removed in dealloc
    NSMutableArray* m_Tokens;  // notification observers
    BOOL m_ToolbarMode;
}
- (void)attachToWindow:(NSWindow*)window;
- (void)relayout;
@end

@implementation ForkChromeController

- (instancetype)init
{
    self = [super init];
    if (self) {
        m_Tokens = [[NSMutableArray alloc] init];
        const char* mode = getenv("LUZLUNAR_LIGHTS");
        m_ToolbarMode = mode != nullptr && strcmp(mode, "toolbar") == 0;
    }
    return self;
}

- (void)dealloc
{
    for (id token in m_Tokens) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
    }
    [m_Tokens release];
    [super dealloc];
}

- (void)attachToWindow:(NSWindow*)window
{
    if (window == nil || window == m_Window) {
        return;
    }
    m_Window = window;

    // AppKit lays the title bar out again on these, putting the lights back where it wants them
    NSArray* names = @[NSWindowDidResizeNotification,
                       NSWindowDidEndLiveResizeNotification,
                       NSWindowDidExitFullScreenNotification,
                       NSWindowDidBecomeMainNotification,
                       NSWindowDidChangeScreenNotification,
                       NSWindowDidChangeBackingPropertiesNotification];
    for (NSString* name in names) {
        id token = [NSNotificationCenter.defaultCenter
            addObserverForName:name
                        object:window
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification*) {
                        [self relayout];
                        // AppKit's own layout can run after the notification
                        dispatch_async(dispatch_get_main_queue(), ^{ [self relayout]; });
                    }];
        [m_Tokens addObject:token];
    }

    [self install];
}

// The window's ground and title bar look. Safe to repeat.
- (void)install
{
    NSWindow* window = m_Window;
    if (window == nil) {
        return;
    }

    if (!(window.styleMask & NSWindowStyleMaskFullSizeContentView)) {
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    }
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    if (@available(macOS 11.0, *)) {
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    }

    // The top of the sky (ForkWindowGlass's flat colour is this under the bar's tint): Night
    // #0A0D1A, Dawn #F2F0FD
    window.opaque = YES;
    window.backgroundColor = [NSColor colorWithName:nil dynamicProvider:^NSColor*(NSAppearance* appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
                     isEqualToString:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithSRGBRed:10 / 255.0 green:13 / 255.0 blue:26 / 255.0 alpha:1]
                    : [NSColor colorWithSRGBRed:242 / 255.0 green:240 / 255.0 blue:253 / 255.0 alpha:1];
    }];

    if (m_ToolbarMode) {
        if (window.toolbar == nil) {
            NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"LuzLunarEmptyToolbar"];
            toolbar.displayMode = NSToolbarDisplayModeIconOnly;
            window.toolbar = toolbar;
            [toolbar release];
        }
        window.toolbarStyle = NSWindowToolbarStyleUnified;
    }
    else if (window.toolbar != nil) {
        window.toolbar = nil;
    }

    [self relayout];
}

// The traffic lights at the design's place
- (void)relayout
{
    NSWindow* window = m_Window;
    if (window == nil || m_ToolbarMode) {
        return;
    }
    // Full screen has no lights (the menu bar's are AppKit's)
    if (window.styleMask & NSWindowStyleMaskFullScreen) {
        return;
    }

    NSButton* close = [window standardWindowButton:NSWindowCloseButton];
    NSButton* mini = [window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton* zoom = [window standardWindowButton:NSWindowZoomButton];
    NSView* titlebar = close.superview;       // the buttons' own container
    NSView* container = titlebar.superview;   // the title bar container, a child of the window's frame view
    if (close == nil || mini == nil || zoom == nil || titlebar == nil || container == nil
            || container.superview == nil) {
        return;
    }

    const CGFloat barHeight = 52;
    const CGFloat centerFromTop = 25.5;

    // A 52 pt high container at the top of the window's frame view
    NSRect frame = container.frame;
    frame.size.height = barHeight;
    frame.origin.y = NSHeight(container.superview.bounds) - barHeight;
    if (!NSEqualRects(container.frame, frame)) {
        container.frame = frame;
    }
    if (!NSEqualRects(titlebar.frame, container.bounds)) {
        titlebar.frame = container.bounds;
    }

    // 12 pt discs 8 pt apart: left edges at 20, 40 and 60, whatever the buttons' own frames are
    NSArray<NSButton*>* buttons = @[close, mini, zoom];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton* button = buttons[i];
        const CGFloat width = NSWidth(button.frame);
        const CGFloat height = NSHeight(button.frame);
        const CGFloat x = 20 + 20 * (CGFloat)i - (width - 12) / 2;
        const CGFloat y = titlebar.isFlipped ? centerFromTop - height / 2
                                             : barHeight - centerFromTop - height / 2;
        const NSPoint origin = NSMakePoint(x, y);
        if (!NSEqualPoints(button.frame.origin, origin)) {
            [button setFrameOrigin:origin];
        }
    }
}

@end

ForkWindowChrome::~ForkWindowChrome()
{
    [(ForkChromeController*)m_Platform release];
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
    if (window == nullptr || window == m_Window) {
        return;
    }

    // Only a Cocoa window has an NSView behind winId(); the offscreen platform (screenshots) has none
    if (QGuiApplication::platformName() != QLatin1String("cocoa")) {
        return;
    }
    m_Window = window;

    if (m_Platform == nullptr) {
        m_Platform = [[ForkChromeController alloc] init];
    }

    // The NSWindow may only exist once the window is shown; the window is also hidden and shown around
    // every stream, which resets nothing here but is cheap to repeat
    connect(window, &QWindow::visibleChanged, this, [this](bool) { apply(); });
    apply();
}

void ForkWindowChrome::apply()
{
    if (m_Platform == nullptr || m_Window == nullptr) {
        return;
    }

    // The first call comes from QML's Component.onCompleted, before the event loop's pool exists
    @autoreleasepool {
        NSView* view = reinterpret_cast<NSView*>(m_Window->winId());
        NSWindow* window = view.window;
        if (window == nil) {
            return;
        }

        [(ForkChromeController*)m_Platform attachToWindow:window];
        [(ForkChromeController*)m_Platform relayout];
    }

    if (!m_Active) {
        m_Active = true;
        emit activeChanged();
    }
}

void ForkWindowChrome::zoomWindow(QWindow* window)
{
    if (window == nullptr) {
        return;
    }

    @autoreleasepool {
        NSView* view = reinterpret_cast<NSView*>(window->winId());
        NSWindow* nsWindow = view.window;
        if (nsWindow == nil) {
            return;
        }

        // System Settings > Desktop & Dock > "Double-click a window's title bar to": Maximize
        // (zoom), Minimize, or None. Unset means zoom.
        NSString* action = [NSUserDefaults.standardUserDefaults stringForKey:@"AppleActionOnDoubleClick"];
        if ([action isEqualToString:@"None"]) {
            return;
        }
        if ([action isEqualToString:@"Minimize"]) {
            [nsWindow performMiniaturize:nil];
        }
        else {
            [nsWindow performZoom:nil];
        }
    }
}
