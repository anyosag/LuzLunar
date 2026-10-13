#include "macintegration.h"

#include <QWindow>

#import <AppKit/AppKit.h>

namespace
{
    id s_ShortcutMonitor = nil;
}

void MacIntegration::setStreamShortcutGuard(bool enabled)
{
    if (enabled && s_ShortcutMonitor == nil) {
        // Local monitors run from -[NSApplication sendEvent:]. SDL's event pump handles the key
        // before calling sendEvent:, so dropping the event here only stops AppKit's own handling,
        // such as the app menu's key equivalents.
        s_ShortcutMonitor = [[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                   handler:^NSEvent*(NSEvent* event) {
            if (event.modifierFlags & NSEventModifierFlagCommand) {
                return nil;
            }
            return event;
        }] retain];
    }
    else if (!enabled && s_ShortcutMonitor != nil) {
        [NSEvent removeMonitor:s_ShortcutMonitor];
        [s_ShortcutMonitor release];
        s_ShortcutMonitor = nil;
    }
}

bool MacIntegration::clipboardHasConcealedContent()
{
    @autoreleasepool {
        NSArray<NSPasteboardType>* types = [[NSPasteboard generalPasteboard] types];
        return [types containsObject:@"org.nspasteboard.ConcealedType"] ||
               [types containsObject:@"org.nspasteboard.TransientType"];
    }
}

long MacIntegration::windowNumber(QWindow* window)
{
    NSView* view = reinterpret_cast<NSView*>(window->winId());
    return view.window != nil ? view.window.windowNumber : 0;
}
