#include "forkdisplaycoordinator.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include "forkdisplayextend.h"
#include "forkdisplayroute.h"
#include "forkevents.h"
#include "settings/streamingpreferences.h"

#ifdef Q_OS_DARWIN
#include "mac/multidisplay_mac.h"
#endif

extern char** environ;

namespace
{
    // How long a helper has to connect, and a direct stream from the PC to start on the iMac
    constexpr int k_ConnectTimeoutMs = 20000;
    constexpr int k_ShownTimeoutMs = 5000;
    constexpr int k_DirectTimeoutMs = 30000;

    // How long helpers get to end their streams before they're killed
    constexpr int k_StopGraceMs = 2000;

    // Moonlight's default HTTP port; any other goes with the address
    constexpr uint16_t k_DefaultHttpPort = 47989;

    // ForkDisplayRoute (Qt-free) mirrors these for the iMac's codec
    static_assert(ForkDisplayRoute::k_VccAutomatic == StreamingPreferences::VCC_AUTO
                  && ForkDisplayRoute::k_VccH264 == StreamingPreferences::VCC_FORCE_H264
                  && ForkDisplayRoute::k_VccHevc == StreamingPreferences::VCC_FORCE_HEVC
                  && ForkDisplayRoute::k_VccHevcHdr == StreamingPreferences::VCC_FORCE_HEVC_HDR_DEPRECATED
                  && ForkDisplayRoute::k_VccAv1 == StreamingPreferences::VCC_FORCE_AV1,
                  "ForkDisplayRoute's codec configs follow StreamingPreferences::VideoCodecConfig");

    enum Code {
        CodeRefocus = 1,
        CodeMessage = 2,
    };

    // Never SDL_USEREVENT, which Moonlight's session takes as its own (forkevents.h)
    Uint32 eventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }

    int64_t nowMs()
    {
        return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
    }

    void setCloseOnExec(int fd)
    {
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
}

struct ForkDisplayCoordinator::State
{
    struct Helper {
        ForkDisplayGroup::Slot slot;
        pid_t pid = -1;
        int stdinFd = -1, stdoutFd = -1;
        QByteArray buffer;
        QString lastError;
        // What it reported since it started; several lines can arrive in one read
        bool sawConnected = false, sawShown = false, sawEnd = false;
        bool connected = false;
        int restarts = 0;
    };

    std::shared_ptr<const ForkMultiDisplay::Group> group;
    QString executable;

    std::atomic<bool> stopping { false };
    std::mutex lock;
    std::condition_variable wake;

    // Guarded by lock, so the destructor can end them from the main thread
    std::vector<Helper*> helpers;
    ForkDisplayExtend* bridge = nullptr;

    ~State()
    {
        for (Helper* helper : helpers) {
            delete helper;
        }
    }

    void log(const char* format, const QString& text)
    {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, format, qPrintable(text));
    }

    // To the main thread's SDL loop, unless the stream already ended
    void post(int code, const QString& text = QString(), pid_t pid = 0)
    {
        if (stopping) {
            return;
        }
        SDL_Event event = {};
        event.type = eventType();
        event.user.code = code;
        event.user.windowID = static_cast<Uint32>(pid);
        event.user.data1 = this;
        event.user.data2 = text.isEmpty() ? nullptr : new QString(text);
        if (SDL_PushEvent(&event) <= 0 && event.user.data2 != nullptr) {
            delete static_cast<QString*>(event.user.data2);
        }
    }

    // Waits ms unless the stream ends first; false if it ended
    bool pause(int ms)
    {
        std::unique_lock<std::mutex> guard(lock);
        wake.wait_for(guard, std::chrono::milliseconds(ms), [this]() { return stopping.load(); });
        return !stopping;
    }

    bool spawn(Helper& helper)
    {
        const ForkDisplayGroup::Slot& slot = helper.slot;
        int toChild[2], fromChild[2];
        if (pipe(toChild) != 0) {
            return false;
        }
        if (pipe(fromChild) != 0) {
            close(toChild[0]);
            close(toChild[1]);
            return false;
        }

        // At once, so nothing else this process starts meanwhile inherits them (a helper whose stdin
        // another process also holds never sees it close); the helper's own copies are dup2'd
        for (int fd : { toChild[0], toChild[1], fromChild[0], fromChild[1] }) {
            setCloseOnExec(fd);
        }

        // The iMac's display through this Mac takes the iMac codec and bitrate settings
        int bitrateKbps = slot.bitrateKbps;
        int videoCodecConfig = group->videoCodecConfig;
        if (slot.external) {
            ForkDisplayRoute::ImacStream stream = ForkDisplayRoute::imacStream(ForkDisplayRoute::Route::ViaMac, group->imacCodec,
                                                                              group->imacBitrateKbps, slot.bitrateKbps,
                                                                              group->videoCodecConfig, ForkDisplayRoute::ImacCodecs());
            bitrateKbps = stream.kbps;
            if (!stream.sameAsMain) {
                videoCodecConfig = ForkDisplayRoute::codecConfig(stream.codec);
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Display group slot %d, the iMac's, through this Mac: %s",
                        slot.slot, ForkDisplayRoute::describe(stream).c_str());
        }

        QList<QByteArray> arguments {
            QFile::encodeName(executable),
            "--luz-helper",
            "--host", group->hostUuid.toUtf8(),
            "--address", group->address.toUtf8(),
            "--port", QByteArray::number(group->httpPort),
            "--app-id", QByteArray::number(group->appId),
            "--app-name", group->appName.toUtf8(),
            "--group", QByteArray::fromStdString(group->plan.id),
            "--slot", QByteArray::number(slot.slot),
            "--display", QByteArray::number(slot.displayId),
            "--resolution", QByteArray::number(slot.width) + "x" + QByteArray::number(slot.height),
            "--fps", QByteArray::number(slot.fps),
            "--bitrate", QByteArray::number(bitrateKbps),
            "--video-codec", QByteArray::number(videoCodecConfig),
        };
        if (slot.hdr) {
            arguments.append("--hdr");
        }
        std::vector<char*> argv;
        for (QByteArray& argument : arguments) {
            argv.push_back(argument.data());
        }
        argv.push_back(nullptr);

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_adddup2(&actions, toChild[0], STDIN_FILENO);
        posix_spawn_file_actions_adddup2(&actions, fromChild[1], STDOUT_FILENO);
        posix_spawn_file_actions_adddup2(&actions, STDERR_FILENO, STDERR_FILENO);

        // Nothing else of this process's (sockets, other helpers' pipes) goes to the helper, and it
        // starts with no signals blocked and the default handlers
        posix_spawnattr_t attributes;
        posix_spawnattr_init(&attributes);
        sigset_t none, defaults;
        sigemptyset(&none);
        sigemptyset(&defaults);
        sigaddset(&defaults, SIGTERM);
        sigaddset(&defaults, SIGINT);
        sigaddset(&defaults, SIGPIPE);
        posix_spawnattr_setsigmask(&attributes, &none);
        posix_spawnattr_setsigdefault(&attributes, &defaults);
        posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);

        pid_t pid = -1;
        int error = posix_spawn(&pid, argv[0], &actions, &attributes, argv.data(), environ);
        posix_spawn_file_actions_destroy(&actions);
        posix_spawnattr_destroy(&attributes);
        close(toChild[0]);
        close(fromChild[1]);

        if (error != 0) {
            close(toChild[1]);
            close(fromChild[0]);
            log("[fork] Couldn't start a display group helper: %s", QString::fromLocal8Bit(strerror(error)));
            return false;
        }

        fcntl(fromChild[0], F_SETFL, fcntl(fromChild[0], F_GETFL, 0) | O_NONBLOCK);

        std::lock_guard<std::mutex> guard(lock);
        helper.pid = pid;
        helper.stdinFd = toChild[1];
        helper.stdoutFd = fromChild[0];
        helper.buffer.clear();
        helper.sawConnected = helper.sawShown = helper.sawEnd = false;
        helper.connected = false;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Started the helper for display group slot %d (pid %d)", slot.slot, pid);
        return true;
    }

    // Reads what a helper wrote, waiting up to timeoutMs, into its saw* flags. Sets gone when its
    // stdout closed.
    void read(Helper& helper, int timeoutMs, bool& gone)
    {
        gone = false;
        if (helper.stdoutFd < 0) {
            gone = true;
            return;
        }

        pollfd waiting = { helper.stdoutFd, POLLIN, 0 };
        if (poll(&waiting, 1, timeoutMs) <= 0) {
            return;
        }

        char chunk[1024];
        for (;;) {
            ssize_t n = ::read(helper.stdoutFd, chunk, sizeof(chunk));
            if (n > 0) {
                helper.buffer.append(chunk, n);
                continue;
            }
            if (n == 0) {
                gone = true;
            }
            break;
        }

        qsizetype end;
        while ((end = helper.buffer.indexOf('\n')) >= 0) {
            QJsonObject message = QJsonDocument::fromJson(helper.buffer.left(end)).object();
            helper.buffer.remove(0, end + 1);
            QString reported = message.value("state").toString();
            QString error = message.value("error").toString();
            if (!error.isEmpty()) {
                helper.lastError = error;
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Display group slot %d: %s: %s",
                            helper.slot.slot, qPrintable(reported), qPrintable(error));
            }
            if (reported == QLatin1String("connected")) {
                helper.sawConnected = true;
            }
            else if (reported == QLatin1String("shown")) {
                helper.sawShown = true;
            }
            else if (reported == QLatin1String("failed") || reported == QLatin1String("ended")) {
                helper.sawEnd = true;
            }
        }
    }

    // Ends a helper: its stdin closes, which ends its stream; killed if it lingers
    void end(Helper& helper, int graceMs)
    {
        int stdinFd, stdoutFd;
        pid_t pid;
        {
            std::lock_guard<std::mutex> guard(lock);
            stdinFd = helper.stdinFd;
            stdoutFd = helper.stdoutFd;
            pid = helper.pid;
            helper.stdinFd = helper.stdoutFd = -1;
            helper.pid = -1;
        }
        if (stdinFd >= 0) {
            close(stdinFd);
        }
        if (stdoutFd >= 0) {
            close(stdoutFd);
        }
        if (pid <= 0) {
            return;
        }

        int64_t deadline = nowMs() + graceMs;
        while (waitpid(pid, nullptr, WNOHANG) == 0) {
            if (nowMs() >= deadline) {
                kill(pid, SIGTERM);
                std::this_thread::sleep_for(std::chrono::milliseconds(500));
                if (waitpid(pid, nullptr, WNOHANG) == 0) {
                    kill(pid, SIGKILL);
                    waitpid(pid, nullptr, 0);
                }
                return;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
    }

    // Starts a helper for the slot and waits until it streams; tries twice
    bool bringUp(Helper& helper)
    {
        for (int attempt = 0; attempt < 2 && !stopping; attempt++) {
            if (attempt > 0) {
                // Apollo takes one launch at a time; another may still be pending
                if (!pause(1500)) {
                    return false;
                }
            }
            if (!spawn(helper)) {
                continue;
            }

            int64_t deadline = nowMs() + k_ConnectTimeoutMs;
            bool gone = false, extended = false;
            while (!stopping && !gone && !helper.sawEnd && !helper.sawShown && nowMs() < deadline) {
                read(helper, 200, gone);
                if (helper.sawConnected && !extended) {
                    // Connected: its window comes next
                    extended = true;
                    deadline = nowMs() + k_ShownTimeoutMs;
                }
            }

            if (helper.sawConnected && !gone && !helper.sawEnd) {
                helper.connected = true;
                // In case showing its window took the keyboard from slot 0 after all
                post(CodeRefocus, QString(), helper.pid);
                return true;
            }

            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Display group slot %d didn't connect%s%s",
                        helper.slot.slot, helper.lastError.isEmpty() ? "" : ": ", qPrintable(helper.lastError));
            end(helper, 0);
        }
        return false;
    }

    // The iMac streams the slot straight from the PC, if the route says so and it starts
    bool bringUpDirect(const ForkDisplayGroup::Slot& slot)
    {
        if (group->route == ForkDisplayRoute::Setting::ViaMac) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] iMac route: through this Mac (set to go through this Mac)");
            return false;
        }

        // The launch screen checked the route before the stream connected (ForkGroupLaunch); a stream
        // started without it checks now
        ForkDisplayRoute::Facts facts;
        ForkDisplayRoute::Decision decision;
        if (!ForkMultiDisplay::routeDecision(&decision, &facts)) {
            facts = ForkMultiDisplay::checkRoute(*group, nullptr, [](const ForkDisplayRoute::Facts&, double) {}).facts;
            decision = ForkDisplayRoute::decide(group->route, facts);
            ForkMultiDisplay::setRouteDecision(decision, facts);
        }
        if (stopping) {
            return false;
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] iMac route: %s",
                    ForkDisplayRoute::describe(decision, facts).c_str());
        if (decision.route != ForkDisplayRoute::Route::Direct) {
            if (group->route == ForkDisplayRoute::Setting::Direct) {
                post(CodeMessage, QStringLiteral("The iMac's picture goes through this Mac: %1")
                                      .arg(QString::fromStdString(decision.reason)));
            }
            return false;
        }

        auto bridge = std::make_unique<ForkDisplayExtend>();
        if (!bridge->open(1000)) {
            post(CodeMessage, QStringLiteral("The iMac's picture goes through this Mac: DisplayExtend's Host stopped answering"));
            return false;
        }
        {
            std::lock_guard<std::mutex> guard(lock);
            if (stopping) {
                return false;
            }
            this->bridge = bridge.get();
        }

        ForkDisplayExtend::Direct direct;
        direct.address = QString::fromStdString(decision.address);
        if (group->httpPort != 0 && group->httpPort != k_DefaultHttpPort) {
            direct.address += QStringLiteral(":%1").arg(group->httpPort);
        }
        direct.app = group->appName;
        direct.hostUniqueId = group->hostUuid;
        direct.width = slot.width;
        direct.height = slot.height;
        direct.fps = slot.fps;
        ForkDisplayRoute::ImacStream stream = ForkDisplayRoute::imacStream(ForkDisplayRoute::Route::Direct, group->imacCodec,
                                                                          group->imacBitrateKbps, slot.bitrateKbps,
                                                                          group->videoCodecConfig, facts.imacCodecs);
        direct.codec = stream.codec;
        direct.bitrateKbps = stream.kbps;

        QString error;
        bool started = bridge->startDirect(direct, k_DirectTimeoutMs, &error);
        if (started && !stopping) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] The iMac streams display group slot %d straight from the PC (%s), %s",
                        slot.slot, qPrintable(direct.address), ForkDisplayRoute::describe(stream).c_str());
            bridge.release();
            return true;
        }

        {
            std::lock_guard<std::mutex> guard(lock);
            this->bridge = nullptr;
        }
        if (!stopping) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] The iMac couldn't stream straight from the PC: %s", qPrintable(error));
            post(CodeMessage, QStringLiteral("The iMac's picture goes through this Mac: %1").arg(error));
        }
        return false;
    }

    Helper* addHelper(const ForkDisplayGroup::Slot& slot)
    {
        auto helper = new Helper;
        helper->slot = slot;
        std::lock_guard<std::mutex> guard(lock);
        helpers.push_back(helper);
        return helper;
    }

    void run()
    {
        // The Mac's own displays first, DisplayExtend's last: the iMac may take a while to decide
        std::vector<ForkDisplayGroup::Slot> order;
        for (const ForkDisplayGroup::Slot& slot : group->plan.slotList) {
            if (slot.slot != 0 && !slot.external) {
                order.push_back(slot);
            }
        }
        for (const ForkDisplayGroup::Slot& slot : group->plan.slotList) {
            if (slot.slot != 0 && slot.external) {
                order.push_back(slot);
            }
        }

        bool directSlotFellBack = false;
        ForkDisplayGroup::Slot directSlot;
        for (const ForkDisplayGroup::Slot& slot : order) {
            if (stopping) {
                break;
            }
            if (slot.external && bringUpDirect(slot)) {
                directSlot = slot;
                continue;
            }
            Helper* helper = addHelper(slot);
            if (!bringUp(*helper)) {
                post(CodeMessage, QStringLiteral("Display %1 (%2) couldn't start its stream")
                                      .arg(slot.slot + 1).arg(QString::fromStdString(slot.name)));
            }
        }

        // A helper's window, or DisplayExtend parking its display, can still take the keyboard from
        // the main stream a moment after its display came up: look again 1 s and 3 s on
        for (int wait : { 1000, 2000 }) {
            if (!pause(wait)) {
                break;
            }
            for (Helper* helper : helpers) {
                if (helper->connected) {
                    post(CodeRefocus, QString(), helper->pid);
                }
            }
            post(CodeRefocus);
        }

        // Watch: a helper that stops is started again once; an iMac stream from the PC that stops
        // falls back to a helper
        while (!stopping) {
            for (Helper* helper : helpers) {
                if (stopping || !helper->connected) {
                    continue;
                }
                bool gone = false;
                read(*helper, 0, gone);
                if (!gone && !helper->sawEnd) {
                    continue;
                }

                end(*helper, 0);
                helper->connected = false;

                // The host ending the whole group stops every helper just before slot 0 ends:
                // give that a moment before starting one again
                if (!pause(1000)) {
                    break;
                }
                if (helper->restarts++ < 1) {
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Display group slot %d stopped; starting it again", helper->slot.slot);
                    if (!bringUp(*helper)) {
                        post(CodeMessage, QStringLiteral("Display %1's stream stopped").arg(helper->slot.slot + 1));
                    }
                }
                else {
                    post(CodeMessage, QStringLiteral("Display %1's stream stopped").arg(helper->slot.slot + 1));
                }
            }

            ForkDisplayExtend* bridgeNow;
            {
                std::lock_guard<std::mutex> guard(lock);
                bridgeNow = bridge;
            }
            if (bridgeNow != nullptr && !stopping) {
                // Every event waiting, so none pile up
                QJsonObject event;
                bool ended = false;
                for (QJsonObject next = bridgeNow->nextEvent(0); !next.isEmpty() && !ended; next = bridgeNow->nextEvent(0)) {
                    QString state = next.value("state").toString();
                    if (next.value("event").toString() == QLatin1String("direct") &&
                            (state == QLatin1String("ended") || state == QLatin1String("failed"))) {
                        event = next;
                        ended = true;
                    }
                }
                ended = ended || !bridgeNow->isOpen();
                if (ended && !stopping) {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] The iMac's stream from the PC stopped%s%s",
                                event.contains("error") ? ": " : "", qPrintable(event.value("error").toString()));
                    {
                        std::lock_guard<std::mutex> guard(lock);
                        bridge = nullptr;
                    }
                    delete bridgeNow;
                    if (!directSlotFellBack) {
                        directSlotFellBack = true;
                        post(CodeMessage, QStringLiteral("The iMac's stream from the PC stopped; its picture now goes through this Mac"));
                        Helper* helper = addHelper(directSlot);
                        bringUp(*helper);
                    }
                }
            }

            pause(500);
        }

        // The stream ended: end the helpers together, then hand the iMac back to DisplayExtend
        {
            std::lock_guard<std::mutex> guard(lock);
            for (Helper* helper : helpers) {
                if (helper->stdinFd >= 0) {
                    close(helper->stdinFd);
                    helper->stdinFd = -1;
                }
            }
        }
        for (Helper* helper : helpers) {
            end(*helper, k_StopGraceMs);
        }

        ForkDisplayExtend* bridgeNow;
        {
            std::lock_guard<std::mutex> guard(lock);
            bridgeNow = bridge;
            bridge = nullptr;
        }
        if (bridgeNow != nullptr) {
            bridgeNow->stopDirect(1000);
            delete bridgeNow;
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Display group %s ended", group->plan.id.c_str());
    }
};

ForkDisplayCoordinator::ForkDisplayCoordinator(std::shared_ptr<const ForkMultiDisplay::Group> group, SDL_Window* window)
    : m_State(std::make_shared<State>()),
      m_Window(window)
{
    // Registered here, on the main thread, before the thread can post one
    eventType();

    m_State->group = std::move(group);
    m_State->executable = QCoreApplication::applicationFilePath();

    std::shared_ptr<State> state = m_State;
    std::thread([state]() { state->run(); }).detach();
}

ForkDisplayCoordinator::~ForkDisplayCoordinator()
{
    {
        std::lock_guard<std::mutex> guard(m_State->lock);
        m_State->stopping = true;

        // A request to DisplayExtend's Host in progress gives up now
        if (m_State->bridge != nullptr) {
            m_State->bridge->interrupt();
        }
    }
    m_State->wake.notify_all();
}

void ForkDisplayCoordinator::setMessageSink(std::function<bool(const QString&)> sink)
{
    m_MessageSink = std::move(sink);
}

void ForkDisplayCoordinator::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType()) {
        return;
    }

    QString* text = static_cast<QString*>(event.user.data2);

    // Only this stream's: a coordinator from an earlier stream may have posted before it stopped
    if (event.user.data1 == m_State.get()) {
        switch (event.user.code) {
        case CodeRefocus:
#ifdef Q_OS_DARWIN
            // Only while that helper or this app is the active one: the user may have switched to
            // another app on purpose while the displays came up. This app in front without its
            // stream window holding the keyboard happens too, after a helper handed activation back.
            if (SDL_GetKeyboardFocus() != m_Window) {
                pid_t active = MultiDisplayMac::activePid();
                bool helper = event.user.windowID != 0 && active == static_cast<pid_t>(event.user.windowID);
                if (helper || active == getpid()) {
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, helper ? "[fork] A display group helper took the keyboard; giving it back to the main stream"
                                                                     : "[fork] The main stream's window lost the keyboard while the displays came up; taking it back");
                    SDL_RaiseWindow(m_Window);
                }
            }
#endif
            break;
        case CodeMessage:
            if (text != nullptr) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] %s", qPrintable(*text));
                if (m_MessageSink) {
                    m_MessageSink(*text);
                }
            }
            break;
        }
    }

    delete text;
}
