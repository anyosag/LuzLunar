#include "forksystemshortcuts.h"

#include <memory>

#include <QCoreApplication>
#include <QSettings>
#include <QStringList>

#include "forkmacshortcuts.h"
#include "forkpreferences.h"
#include "mac/macintegration.h"
#include "settings/streamingpreferences.h"

#ifdef Q_OS_DARWIN
#include <libproc.h>
#include <signal.h>
#include <unistd.h>
#endif

// The crash record of global hot keys a running LuzLunar holds off: "pid:1,2"
#define SER_HELDMACSHORTCUTS "fork/heldMacShortcuts"

// Set once the capture default below has been applied
#define SER_CAPTUREDEFAULTED "fork/captureSysKeysDefaulted"

// Upstream's StreamingPreferences key for captureSysKeysMode
#define SER_CAPTURESYSKEYS "capturesyskeys"

namespace
{
    enum Mode {
        // Upstream's behavior: SDL's grab, every shortcut to the host
        ModePassThrough,
        // Only the chosen groups, through the per-app hot key calls
        ModeSelective,
        // The calls are missing on this macOS: nothing is taken, so the Mac keeps its shortcuts
        ModeNone,
    };

    // How often to look for macOS's screenshot tools, and for how long after ⌘⇧ are let go
    const Uint32 k_ScreenshotWatchIntervalMs = 100;
    const Uint32 k_ScreenshotWatchAfterMs = 1000;

    struct State {
        SDL_Window* window = nullptr;
        Mode mode = ModePassThrough;
        bool wantGrab = false;
        std::unique_ptr<ForkMacShortcuts::Controller> controller;

        // Watching for macOS's screenshot tools, which can't be used while relative mouse mode
        // holds the cursor still
        SDL_TimerID watchTimer = 0;
        bool commandShiftHeld = false;
        Uint32 watchUntil = 0;
        bool mouseFreed = false;
    };

    std::unique_ptr<State> s_State;

    bool hasFocus(SDL_Window* window)
    {
        return (SDL_GetWindowFlags(window) & SDL_WINDOW_INPUT_FOCUS) != 0;
    }

    Uint32 screenshotWatchEventType()
    {
        static Uint32 type = SDL_RegisterEvents(1);
        return type;
    }

    // On SDL's timer thread: wake the stream's event loop for a look
    Uint32 screenshotWatchTick(Uint32 interval, void*)
    {
        SDL_Event event = {};
        event.type = screenshotWatchEventType();
        SDL_PushEvent(&event);
        return interval;
    }

    void stopScreenshotWatch()
    {
        if (s_State->watchTimer != 0) {
            SDL_RemoveTimer(s_State->watchTimer);
            s_State->watchTimer = 0;
        }
    }

    // ⇧⌘4's crosshair and ⇧⌘5's toolbar go to the Mac, but a fullscreen stream holds the cursor
    // still for the host (relative mouse mode), so they couldn't be used. While they're on screen
    // the cursor is let go, and held again when they close.
    void checkScreenshotTools()
    {
        bool visible = MacIntegration::screenshotOverlayVisible();

        if (visible && !s_State->mouseFreed && SDL_GetRelativeMouseMode()) {
            SDL_SetRelativeMouseMode(SDL_FALSE);
            s_State->mouseFreed = true;
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Freed the mouse for macOS's screenshot tools");
        }
        else if (!visible && s_State->mouseFreed) {
            s_State->mouseFreed = false;
            // Unless the user went to another app meanwhile; then a click in the stream captures it as usual
            if (hasFocus(s_State->window)) {
                SDL_SetRelativeMouseMode(SDL_TRUE);
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The screenshot tools closed; the stream has the mouse again");
        }

        if (!s_State->mouseFreed && !s_State->commandShiftHeld && SDL_TICKS_PASSED(SDL_GetTicks(), s_State->watchUntil)) {
            stopScreenshotWatch();
        }
    }

    void updateScreenshotWatch()
    {
        SDL_Keymod mod = SDL_GetModState();
        bool held = (mod & KMOD_GUI) && (mod & KMOD_SHIFT);
        if (held == s_State->commandShiftHeld) {
            return;
        }

        s_State->commandShiftHeld = held;
        if (held) {
            if (s_State->watchTimer == 0) {
                s_State->watchTimer = SDL_AddTimer(k_ScreenshotWatchIntervalMs, screenshotWatchTick, nullptr);
            }
        }
        else {
            s_State->watchUntil = SDL_GetTicks() + k_ScreenshotWatchAfterMs;
        }
    }

    void persistRecord(const std::vector<int>& globalIds)
    {
        QSettings settings;
        if (globalIds.empty()) {
            settings.remove(SER_HELDMACSHORTCUTS);
        }
        else {
            settings.setValue(SER_HELDMACSHORTCUTS,
                              QString::fromStdString(ForkMacShortcuts::formatRecord(getpid(), globalIds)));
        }
        settings.sync();
    }

    void apply()
    {
        if (s_State->mode != ModeSelective) {
            return;
        }

        ForkMacShortcuts::Controller& controller = *s_State->controller;
        bool wasTaken = controller.taken();
        controller.update(s_State->wantGrab && hasFocus(s_State->window));

        if (controller.taken() && !wasTaken) {
            QStringList ids;
            for (const ForkMacShortcuts::Wanted& hotKey : controller.held()) {
                ids.append(QString::number(hotKey.id));
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Taking %d Mac shortcuts for the host: %s",
                        (int)ids.size(), qPrintable(ids.join(',')));
        }
        else if (!controller.taken() && wasTaken) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Gave the Mac its shortcuts back");
        }
    }

#ifdef Q_OS_DARWIN
    // True if pid is a running copy of this program
    bool isRunningCopy(long pid)
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

    void startup()
    {
        QSettings settings;

        // A LuzLunar that died while holding global hot keys (Cmd+Tab) off: turn them back on,
        // unless that copy is still running (a stream from the command line, say)
        QString record = settings.value(SER_HELDMACSHORTCUTS).toString();
        if (!record.isEmpty()) {
            long pid = 0;
            std::vector<int> ids;
            if (!ForkMacShortcuts::parseRecord(record.toStdString(), &pid, &ids)) {
                settings.remove(SER_HELDMACSHORTCUTS);
            }
            else if (!isRunningCopy(pid)) {
                for (int id : ids) {
                    MacIntegration::setSymbolicHotKeyEnabled(id, true, false);
                }
                settings.remove(SER_HELDMACSHORTCUTS);
                qInfo("[fork] Gave the Mac back %d shortcuts left off by an earlier LuzLunar", (int)ids.size());
            }
        }

        // LuzLunar captures system shortcuts in fullscreen by default, where upstream doesn't.
        // Applied once, so it also changes existing settings, and later choices stick.
        if (!settings.contains(SER_CAPTUREDEFAULTED)) {
            settings.setValue(SER_CAPTURESYSKEYS, static_cast<int>(StreamingPreferences::CSK_FULLSCREEN));
            settings.setValue(SER_CAPTUREDEFAULTED, true);
        }
    }
#endif
}

#ifdef Q_OS_DARWIN
// Runs while the QGuiApplication is constructed, before anything reads StreamingPreferences
Q_COREAPP_STARTUP_FUNCTION(startup)
#endif

void ForkSystemShortcuts::activate(SDL_Window* window)
{
    s_State = std::make_unique<State>();
    s_State->window = window;

#ifdef Q_OS_DARWIN
    ForkPreferences* prefs = ForkPreferences::get();
    if (prefs->macShortcutsAll()) {
        s_State->mode = ModePassThrough;
        return;
    }

    if (!MacIntegration::symbolicHotKeysAvailable()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] This macOS doesn't let LuzLunar choose shortcuts; the Mac keeps them all");
        s_State->mode = ModeNone;
        return;
    }

    std::vector<ForkMacShortcuts::Wanted> wanted;
    for (const ForkMacShortcuts::Wanted& hotKey : ForkMacShortcuts::wantedHotKeys([prefs](const ForkMacShortcuts::Group& group) {
             return prefs->macShortcutToHost(QString::fromUtf8(group.key));
         })) {
        // Skip ids macOS has given to something else
        std::string name = MacIntegration::symbolicHotKeyName(hotKey.id);
        if (name != hotKey.name) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Mac shortcut %d is \"%s\" here, not \"%s\"; leaving it alone",
                        hotKey.id, name.c_str(), hotKey.name);
            continue;
        }
        wanted.push_back(hotKey);
    }

    ForkMacShortcuts::Backend backend {
        [](int id) { return MacIntegration::isSymbolicHotKeyEnabled(id); },
        [](int id, ForkMacShortcuts::Scope scope, bool enabled) {
            return MacIntegration::setSymbolicHotKeyEnabled(id, enabled, scope == ForkMacShortcuts::ScopeApp);
        },
        persistRecord,
    };
    s_State->controller = std::make_unique<ForkMacShortcuts::Controller>(backend, wanted);
    s_State->mode = ModeSelective;
#endif
}

void ForkSystemShortcuts::deactivate()
{
    if (s_State) {
        stopScreenshotWatch();
        if (s_State->controller) {
            s_State->wantGrab = false;
            apply();
        }
    }
    s_State.reset();
}

void ForkSystemShortcuts::handleEvent(const SDL_Event& event)
{
    if (!s_State) {
        return;
    }

#ifdef Q_OS_DARWIN
    if (event.type == SDL_KEYDOWN || event.type == SDL_KEYUP) {
        updateScreenshotWatch();
        return;
    }
    if (event.type == screenshotWatchEventType()) {
        checkScreenshotTools();
        return;
    }
#endif

    // Upstream keeps capture on in fullscreen when the window loses focus; the shortcuts go back to
    // the Mac anyway (Cmd+Tab is taken for every app) and are taken again with the focus
    if (event.type == SDL_WINDOWEVENT &&
            (event.window.event == SDL_WINDOWEVENT_FOCUS_LOST || event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED)) {
        apply();
    }
}

bool ForkSystemShortcuts::keyboardGrab(bool shouldGrab)
{
    if (!s_State) {
        return shouldGrab;
    }

    s_State->wantGrab = shouldGrab;

    switch (s_State->mode) {
    case ModeSelective:
        apply();
        return false;
    case ModeNone:
        return false;
    case ModePassThrough:
    default:
        return shouldGrab;
    }
}
