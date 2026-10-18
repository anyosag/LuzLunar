#include "macintegration.h"

#include <QGuiApplication>

#include <QWindow>

#include <dlfcn.h>
#include <libproc.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#import <AppKit/AppKit.h>

namespace
{
    id s_ShortcutMonitor = nil;

    // SkyLight's symbolic hot key calls (CGError is 0 on success)
    typedef int (*SetHotKeyEnabledFn)(uint32_t id, bool enabled);
    typedef bool (*IsHotKeyEnabledFn)(uint32_t id);
    typedef int (*SetHotKeyEnabledForConnectionFn)(int connection, uint32_t id, bool enabled);
    typedef int (*MainConnectionFn)(void);
    typedef const char* (*HotKeyNameFn)(uint32_t id);

    struct HotKeyApi {
        SetHotKeyEnabledFn setEnabled;
        IsHotKeyEnabledFn isEnabled;
        SetHotKeyEnabledForConnectionFn setEnabledForConnection;
        MainConnectionFn mainConnection;
        HotKeyNameFn name;

        HotKeyApi()
        {
            setEnabled = reinterpret_cast<SetHotKeyEnabledFn>(dlsym(RTLD_DEFAULT, "CGSSetSymbolicHotKeyEnabled"));
            isEnabled = reinterpret_cast<IsHotKeyEnabledFn>(dlsym(RTLD_DEFAULT, "CGSIsSymbolicHotKeyEnabled"));
            setEnabledForConnection = reinterpret_cast<SetHotKeyEnabledForConnectionFn>(
                dlsym(RTLD_DEFAULT, "CGSSetSymbolicHotKeyEnabledForConnection"));
            mainConnection = reinterpret_cast<MainConnectionFn>(dlsym(RTLD_DEFAULT, "CGSMainConnectionID"));
            name = reinterpret_cast<HotKeyNameFn>(dlsym(RTLD_DEFAULT, "SLSSymbolicHotKeyName"));
        }

        bool available() const
        {
            return setEnabled && isEnabled && setEnabledForConnection && mainConnection && name;
        }
    };

    const HotKeyApi& hotKeyApi()
    {
        static const HotKeyApi s_Api;
        return s_Api;
    }
}

bool MacIntegration::symbolicHotKeysAvailable()
{
    return hotKeyApi().available();
}

bool MacIntegration::isSymbolicHotKeyEnabled(int id)
{
    const HotKeyApi& api = hotKeyApi();
    return api.available() && api.isEnabled(static_cast<uint32_t>(id));
}

bool MacIntegration::setSymbolicHotKeyEnabled(int id, bool enabled, bool forApp)
{
    const HotKeyApi& api = hotKeyApi();
    if (!api.available()) {
        return false;
    }

    int err = forApp ? api.setEnabledForConnection(api.mainConnection(), static_cast<uint32_t>(id), enabled)
                     : api.setEnabled(static_cast<uint32_t>(id), enabled);
    return err == 0;
}

std::string MacIntegration::symbolicHotKeyName(int id)
{
    const HotKeyApi& api = hotKeyApi();
    const char* name = api.available() ? api.name(static_cast<uint32_t>(id)) : nullptr;
    return name ? std::string(name) : std::string();
}

bool MacIntegration::screenshotOverlayVisible()
{
    // Window owners are readable without the screen recording permission (titles aren't)
    CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                    kCGNullWindowID);
    if (windows == nullptr) {
        return false;
    }

    bool visible = false;
    for (CFIndex i = 0; i < CFArrayGetCount(windows) && !visible; i++) {
        CFDictionaryRef window = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(windows, i));
        CFStringRef owner = static_cast<CFStringRef>(CFDictionaryGetValue(window, kCGWindowOwnerName));
        visible = owner != nullptr && CFStringCompare(owner, CFSTR("screencapture"), 0) == kCFCompareEqualTo;
    }
    CFRelease(windows);
    return visible;
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
    // Only a Cocoa window has an NSView behind winId(); the offscreen platform (screenshots) has none
    if (QGuiApplication::platformName() != QLatin1String("cocoa")) {
        return 0;
    }
    NSView* view = reinterpret_cast<NSView*>(window->winId());
    return view.window != nil ? view.window.windowNumber : 0;
}

bool MacIntegration::isRunningCopy(long pid)
{
    if (pid <= 0 || kill(static_cast<pid_t>(pid), 0) != 0) {
        return false;
    }
    char other[PROC_PIDPATHINFO_MAXSIZE];
    char self[PROC_PIDPATHINFO_MAXSIZE];
    return proc_pidpath(static_cast<int>(pid), other, sizeof(other)) > 0 &&
           proc_pidpath(getpid(), self, sizeof(self)) > 0 &&
           strcmp(other, self) == 0;
}
