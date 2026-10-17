// LuzLunar: probe for the private symbolic hot key calls that stream capture uses.
// Re-run it after a macOS update to check they still work.
//
// Build: clang++ -std=c++17 -fobjc-arc -framework AppKit scripts/fork/hotkey-probe.mm -o /tmp/hotkey-probe
//
//   hotkey-probe list                 every id 0-264 with its name, keys and on/off state
//   hotkey-probe get ID...            on/off state of some ids
//   hotkey-probe set ID 0|1           turn one id off or on for everyone (CGSSetSymbolicHotKeyEnabled)
//   hotkey-probe conn ID 0|1 SECONDS  turn one id off or on for this process's connection only,
//                                     then wait without putting it back (to test kill -9)
//   hotkey-probe window [--conn] ID...
//                                     a window that logs its key-downs and turns the ids off while
//                                     it's in front; plain Q closes it and puts them back

#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <vector>

typedef int CGError_;
typedef CGError_ (*SetEnabledFn)(uint32_t, bool);
typedef bool (*IsEnabledFn)(uint32_t);
typedef CGError_ (*GetValueFn)(uint32_t, unichar*, unichar*, uint32_t*);
typedef const char* (*NameFn)(uint32_t);
typedef CGError_ (*SetEnabledConnFn)(int, uint32_t, bool);
typedef int (*MainConnFn)(void);

static SetEnabledFn s_SetEnabled;
static IsEnabledFn s_IsEnabled;
static GetValueFn s_GetValue;
static NameFn s_Name;
static SetEnabledConnFn s_SetEnabledConn;
static MainConnFn s_MainConn;

static void* sym(const char* a, const char* b = nullptr)
{
    void* p = dlsym(RTLD_DEFAULT, a);
    if (!p && b) {
        p = dlsym(RTLD_DEFAULT, b);
    }
    return p;
}

static void load()
{
    // Make sure SkyLight is loaded before looking anything up
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    s_SetEnabled = (SetEnabledFn)sym("CGSSetSymbolicHotKeyEnabled", "SLSSetSymbolicHotKeyEnabled");
    s_IsEnabled = (IsEnabledFn)sym("CGSIsSymbolicHotKeyEnabled", "SLSIsSymbolicHotKeyEnabled");
    s_GetValue = (GetValueFn)sym("CGSGetSymbolicHotKeyValue", "SLSGetSymbolicHotKeyValue");
    s_Name = (NameFn)sym("SLSSymbolicHotKeyName", "CGSSymbolicHotKeyName");
    s_SetEnabledConn = (SetEnabledConnFn)sym("CGSSetSymbolicHotKeyEnabledForConnection",
                                             "SLSSetSymbolicHotKeyEnabledForConnection");
    s_MainConn = (MainConnFn)sym("CGSMainConnectionID", "SLSMainConnectionID");
    fprintf(stderr, "set=%d is=%d value=%d name=%d setForConnection=%d mainConnection=%d\n",
            s_SetEnabled != nullptr, s_IsEnabled != nullptr, s_GetValue != nullptr, s_Name != nullptr,
            s_SetEnabledConn != nullptr, s_MainConn != nullptr);
}

static void printId(uint32_t id)
{
    unichar ch = 0, vk = 0;
    uint32_t mods = 0;
    CGError_ err = s_GetValue ? s_GetValue(id, &ch, &vk, &mods) : -1;
    const char* name = s_Name ? s_Name(id) : nullptr;
    printf("%u\t%s\t%s\tchar=%u vk=%u mods=0x%x err=%d\n", id,
           s_IsEnabled ? (s_IsEnabled(id) ? "on" : "off") : "?",
           name ? name : "-", ch, vk, mods, err);
}

@interface ProbeWindow : NSWindow
@end

@implementation ProbeWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)keyDown:(NSEvent*)event
{
    printf("%.3f keyDown keyCode=%u mods=0x%lx chars=\"%s\"\n", [NSDate timeIntervalSinceReferenceDate],
           event.keyCode, (unsigned long)(event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask),
           event.charactersIgnoringModifiers.UTF8String ?: "");
    fflush(stdout);
    // Plain Q quits, so Escape and Cmd+Esc can be tested
    if (event.keyCode == 12 && !(event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask)) {
        [NSApp terminate:nil];
    }
}
@end

static std::vector<uint32_t> s_Ids;
static bool s_UseConn;

static void setAll(bool enabled)
{
    for (uint32_t id : s_Ids) {
        CGError_ err = s_UseConn ? s_SetEnabledConn(s_MainConn(), id, enabled) : s_SetEnabled(id, enabled);
        printf("%.3f %s %u -> %s (err=%d, now %s)\n", [NSDate timeIntervalSinceReferenceDate],
               s_UseConn ? "connection" : "global", id, enabled ? "on" : "off", err,
               s_IsEnabled(id) ? "on" : "off");
    }
    fflush(stdout);
}

@interface ProbeDelegate : NSObject <NSApplicationDelegate>
@end

@implementation ProbeDelegate
- (void)applicationDidBecomeActive:(NSNotification*)n { setAll(false); }
- (void)applicationDidResignActive:(NSNotification*)n { setAll(true); }
- (void)applicationWillTerminate:(NSNotification*)n { setAll(true); }
@end

int main(int argc, char** argv)
{
    @autoreleasepool {
        load();
        if (argc < 2) {
            fprintf(stderr, "usage: see the comment at the top of hotkey-probe.mm\n");
            return 2;
        }
        NSString* cmd = @(argv[1]);
        if ([cmd isEqualToString:@"list"]) {
            for (uint32_t id = 0; id <= 264; id++) {
                printId(id);
            }
            return 0;
        }
        if ([cmd isEqualToString:@"get"]) {
            for (int i = 2; i < argc; i++) {
                printId((uint32_t)atoi(argv[i]));
            }
            return 0;
        }
        if ([cmd isEqualToString:@"set"] && argc == 4) {
            CGError_ err = s_SetEnabled((uint32_t)atoi(argv[2]), atoi(argv[3]) != 0);
            printf("err=%d\n", err);
            printId((uint32_t)atoi(argv[2]));
            return 0;
        }
        if ([cmd isEqualToString:@"conn"] && argc == 5) {
            int cid = s_MainConn();
            CGError_ err = s_SetEnabledConn(cid, (uint32_t)atoi(argv[2]), atoi(argv[3]) != 0);
            printf("connection %d err=%d\n", cid, err);
            printId((uint32_t)atoi(argv[2]));
            fflush(stdout);
            sleep((unsigned)atoi(argv[4]));
            printId((uint32_t)atoi(argv[2]));
            return 0;
        }
        if ([cmd isEqualToString:@"window"]) {
            for (int i = 2; i < argc; i++) {
                if (strcmp(argv[i], "--conn") == 0) {
                    s_UseConn = true;
                }
                else {
                    s_Ids.push_back((uint32_t)atoi(argv[i]));
                }
            }
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            ProbeDelegate* delegate = [ProbeDelegate new];
            NSApp.delegate = delegate;
            ProbeWindow* w = [[ProbeWindow alloc] initWithContentRect:NSMakeRect(200, 200, 520, 160)
                                                            styleMask:NSWindowStyleMaskTitled
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO];
            w.title = @"hotkey-probe: press keys here, Q to quit";
            [w makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
            [NSApp run];
            return 0;
        }
        fprintf(stderr, "unknown command\n");
        return 2;
    }
}
