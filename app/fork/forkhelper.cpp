#include "forkhelper.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibraryInfo>
#include <QRegularExpression>
#include <QSettings>

#include <csignal>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include <unistd.h>

#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "backend/nvhttp.h"
#include "forkmultidisplay.h"
#include "settings/streamingpreferences.h"
#include "streaming/session.h"
#include "streamprofiles.h"

#ifdef Q_OS_DARWIN
#include "mac/multidisplay_mac.h"
#endif

namespace ForkHelper
{

namespace
{
    // The same keys as ComputerManager's
    const char* const k_HostsKey = "hosts";
    const char* const k_HostsBackupKey = "hostsbackup";

    std::mutex s_ReportLock;

    struct Arguments {
        QString hostUuid, address, appName, groupId;
        uint16_t port = 0;
        int appId = 0, slot = 0;
        uint32_t displayId = 0;
        int width = 0, height = 0, fps = 0, bitrateKbps = 0, videoCodecConfig = 0;
        bool hdr = false;
    };

    void report(const QString& state, const QString& error = QString())
    {
        QJsonObject message { { "state", state } };
        if (!error.isEmpty()) {
            message.insert("error", error);
        }
        QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';

        std::lock_guard<std::mutex> lock(s_ReportLock);
        std::fwrite(line.constData(), 1, static_cast<size_t>(line.size()), stdout);
        std::fflush(stdout);
    }

    bool parse(const QStringList& arguments, Arguments& out)
    {
        bool sawHelper = false;
        for (int i = 1; i < arguments.size(); i++) {
            const QString& name = arguments[i];
            if (name == QLatin1String("--luz-helper")) {
                sawHelper = true;
                continue;
            }
            if (name == QLatin1String("--hdr")) {
                out.hdr = true;
                continue;
            }
            if (i + 1 >= arguments.size()) {
                return false;
            }
            const QString& value = arguments[++i];
            bool ok = true;
            if (name == QLatin1String("--host")) out.hostUuid = value;
            else if (name == QLatin1String("--address")) out.address = value;
            else if (name == QLatin1String("--port")) out.port = value.toUShort(&ok);
            else if (name == QLatin1String("--app-id")) out.appId = value.toInt(&ok);
            else if (name == QLatin1String("--app-name")) out.appName = value;
            else if (name == QLatin1String("--group")) out.groupId = value;
            else if (name == QLatin1String("--slot")) out.slot = value.toInt(&ok);
            else if (name == QLatin1String("--display")) out.displayId = value.toUInt(&ok);
            else if (name == QLatin1String("--fps")) out.fps = value.toInt(&ok);
            else if (name == QLatin1String("--bitrate")) out.bitrateKbps = value.toInt(&ok);
            else if (name == QLatin1String("--video-codec")) out.videoCodecConfig = value.toInt(&ok);
            else if (name == QLatin1String("--resolution")) {
                QStringList size = value.split('x');
                ok = size.size() == 2;
                if (ok) {
                    bool okHeight;
                    out.width = size[0].toInt(&ok);
                    out.height = size[1].toInt(&okHeight);
                    ok = ok && okHeight;
                }
            }
            else return false;
            if (!ok) {
                return false;
            }
        }

        // The group id goes into the launch request unencoded, so only hex digits
        static const QRegularExpression hex(QStringLiteral("^[0-9a-fA-F]{1,32}$"));
        bool hexGroup = hex.match(out.groupId).hasMatch();
        return sawHelper && hexGroup && NvComputer::isValidUuid(out.hostUuid) && !out.address.isEmpty() && out.appId != 0 &&
               out.slot >= 1 && out.displayId != 0 && out.width > 0 && out.height > 0 && out.fps > 0 && out.bitrateKbps > 0;
    }

    // The host as the computer manager saved it; read only, so a helper never rewrites the host list
    NvComputer* loadComputer(const QString& uuid)
    {
        QSettings settings;
        int hosts = settings.beginReadArray(k_HostsBackupKey);
        if (hosts == 0) {
            settings.endArray();
            hosts = settings.beginReadArray(k_HostsKey);
        }

        NvComputer* found = nullptr;
        for (int i = 0; i < hosts && found == nullptr; i++) {
            settings.setArrayIndex(i);
            auto computer = new NvComputer(settings);
            if (computer->uuid.compare(uuid, Qt::CaseInsensitive) == 0) {
                found = computer;
            }
            else {
                delete computer;
            }
        }
        settings.endArray();
        return found;
    }

    // The slot from the arguments, without Qt
    const char* argumentAfter(int argc, char* argv[], const char* name)
    {
        for (int i = 1; i + 1 < argc; i++) {
            if (std::strcmp(argv[i], name) == 0) {
                return argv[i + 1];
            }
        }
        return nullptr;
    }

    void silentCleanup()
    {
    }

    int silentInit(int, const POPUS_MULTISTREAM_CONFIGURATION, void*, int)
    {
        return 0;
    }

    void silentSample(char*, int)
    {
    }
}

bool requested(int argc, char* argv[])
{
    for (int i = 1; i < argc; i++) {
        if (std::strcmp(argv[i], "--luz-helper") == 0) {
            return true;
        }
    }
    return false;
}

int slotFromArguments(int argc, char* argv[])
{
    if (!requested(argc, argv)) {
        return -1;
    }
    const char* slot = argumentAfter(argc, argv, "--slot");
    return slot != nullptr ? std::atoi(slot) : 0;
}

void prepareProcess(int argc, char* argv[])
{
    // Only if this build has the plugin (scripts/fork/build-mac.sh bundles it); without it Qt
    // couldn't start at all, and the cocoa platform still works, just less quietly. The coordinator
    // starts helpers by their full path, so argv[0] is the executable.
    QString executableDir = argc > 0 ? QFileInfo(QString::fromLocal8Bit(argv[0])).absolutePath() : QString();
    QStringList candidates {
        executableDir + QStringLiteral("/../PlugIns/platforms/libqoffscreen.dylib"),
        QLibraryInfo::path(QLibraryInfo::PluginsPath) + QStringLiteral("/platforms/libqoffscreen.dylib"),
    };
    for (const QString& path : candidates) {
        if (QFile::exists(path)) {
            qputenv("QT_QPA_PLATFORM", "offscreen");
            return;
        }
    }

    // Qt leaves NSApplication alone, so it doesn't make this process a foreground app
    QCoreApplication::setAttribute(Qt::AA_PluginApplication);
}

int run(QGuiApplication& app)
{
    Arguments args;
    if (!parse(app.arguments(), args)) {
        report(QStringLiteral("failed"), QStringLiteral("bad helper arguments"));
        return 2;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Display group helper for slot %d of group %s: %dx%d at %d fps, %d kbps, on display %u",
                args.slot, qPrintable(args.groupId), args.width, args.height, args.fps, args.bitrateKbps, args.displayId);
    report(QStringLiteral("connecting"));

    // The coordinator may close this end of the pipe first; a write to it mustn't end the process
    signal(SIGPIPE, SIG_IGN);

    // Gamepads belong to the main stream; this one never opens them, so it can't drive their LEDs
    // or rumble against it
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "0");
    SDL_SetHint("SDL_JOYSTICK_MFI", "0");
    SDL_SetHint("SDL_JOYSTICK_IOKIT", "0");

    ForkMultiDisplay::setHelper(args.groupId, args.slot, args.displayId);
#ifdef Q_OS_DARWIN
    MultiDisplayMac::becomeBackgroundApp();
#endif

    NvComputer* computer = loadComputer(args.hostUuid);
    if (computer == nullptr) {
        report(QStringLiteral("failed"), QStringLiteral("the PC isn't in this Mac's settings"));
        return 1;
    }

    // Fresh serverinfo, as the computer manager's polling gets it, through the pinned certificate
    try {
        NvHTTP http(NvAddress(args.address, args.port), 0, computer->serverCert, !computer->isNvidiaServerSoftware);
        QString serverInfo = http.getServerInfo(NvHTTP::NVLL_ERROR, false);
        NvComputer polled(http, serverInfo);
        if (polled.uuid.compare(computer->uuid, Qt::CaseInsensitive) != 0) {
            report(QStringLiteral("failed"), QStringLiteral("another PC answered at %1").arg(args.address));
            return 1;
        }
        computer->update(polled);
    }
    catch (...) {
        report(QStringLiteral("failed"), QStringLiteral("can't reach the PC at %1").arg(args.address));
        return 1;
    }

    if (computer->pairState != NvComputer::PS_PAIRED) {
        report(QStringLiteral("failed"), QStringLiteral("this Mac isn't paired with the PC"));
        return 1;
    }
    if (computer->currentGameId != 0 && computer->currentGameId != args.appId) {
        report(QStringLiteral("failed"), QStringLiteral("another app runs on the PC"));
        return 1;
    }

    // A join is a resume of the running group app. Apollo reports no running app at all while its
    // input-only mode is on, which mustn't turn the join into a launch request.
    computer->currentGameId = args.appId;

    NvApp nvApp;
    nvApp.id = args.appId;
    nvApp.name = args.appName;
    for (const NvApp& known : computer->appList) {
        if (known.id == args.appId) {
            nvApp = known;
        }
    }

    // The app's profile like slot 0's stream, then this slot's own size and rate, and nothing that
    // needs the keyboard, a fullscreen Space or a sound device
    Session* session = StreamProfiles::createSession(computer, nvApp, nullptr, [&args](StreamingPreferences* prefs) {
        prefs->width = args.width;
        prefs->height = args.height;
        prefs->fps = args.fps;
        prefs->bitrateKbps = args.bitrateKbps;
        prefs->videoCodecConfig = static_cast<StreamingPreferences::VideoCodecConfig>(args.videoCodecConfig);
        prefs->enableHdr = args.hdr;
        prefs->windowMode = StreamingPreferences::WM_WINDOWED;
        prefs->absoluteMouseMode = false;
        prefs->trackpadMode = StreamingPreferences::TM_MAC_MOUSE;
        prefs->captureSysKeysMode = StreamingPreferences::CSK_OFF;
        prefs->quitAppAfter = false;
        prefs->playAudioOnHost = false;
        prefs->gameOptimizations = false;
        prefs->showPerformanceOverlay = false;
        prefs->muteOnFocusLoss = false;
        prefs->backgroundGamepad = false;
        prefs->richPresence = false;
    });

    QObject::connect(session, &Session::connectionStarted, session, []() {
        report(QStringLiteral("connected"));
    }, Qt::DirectConnection);
    QObject::connect(session, &Session::stageFailed, session, [](QString stage, int errorCode, QString) {
        report(QStringLiteral("failed"), QStringLiteral("%1 failed (error %2)").arg(stage).arg(errorCode));
    }, Qt::DirectConnection);
    QObject::connect(session, &Session::displayLaunchError, session, [](QString text) {
        report(QStringLiteral("error"), text.simplified());
    }, Qt::DirectConnection);
    QObject::connect(session, &Session::sessionFinished, session, [](int) {
        report(QStringLiteral("ended"));
    }, Qt::DirectConnection);
    QObject::connect(session, &Session::readyForDeletion, &app, &QCoreApplication::quit, Qt::QueuedConnection);

    // stdin closes when the main stream ends (or crashes): end this stream too. Its event loop runs
    // on the main thread, so stop it the thread-safe way the signal handler in main.cpp does.
    std::thread([]() {
        QByteArray pending;
        char chunk[256];
        for (;;) {
            ssize_t n = read(STDIN_FILENO, chunk, sizeof(chunk));
            if (n <= 0) {
                break;
            }
            pending.append(chunk, n);
            if (pending.contains("\"quit\"")) {
                break;
            }
        }

        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Display group helper told to stop");
        Session* active = Session::get();
        if (active != nullptr) {
            active->setShouldExit();
            active->interrupt();
        }
        else {
            QMetaObject::invokeMethod(QCoreApplication::instance(), &QCoreApplication::quit, Qt::QueuedConnection);
        }
    }).detach();

    if (!session->initialize(nullptr)) {
        report(QStringLiteral("failed"), QStringLiteral("the stream couldn't start on this Mac"));
        return 1;
    }
    session->start();

    return app.exec();
}

void streamWindowCreated(SDL_Window* window)
{
    if (!ForkMultiDisplay::isHelper()) {
        return;
    }

#ifdef Q_OS_DARWIN
    if (!MultiDisplayMac::placeHelperWindow(window, ForkMultiDisplay::targetDisplay())) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Couldn't place the helper's window over display %u",
                    ForkMultiDisplay::targetDisplay());
    }
#else
    (void)window;
#endif
    report(QStringLiteral("shown"));
}

bool dropsEvent(const SDL_Event& event)
{
    if (!ForkMultiDisplay::isHelper()) {
        return false;
    }

    // Keyboard, text, mouse, joysticks, controllers, touch and gestures, and drops
    return (event.type >= SDL_KEYDOWN && event.type < SDL_CLIPBOARDUPDATE) ||
           (event.type >= SDL_DROPFILE && event.type <= SDL_DROPCOMPLETE);
}

void silenceAudio(AUDIO_RENDERER_CALLBACKS& callbacks)
{
    if (!ForkMultiDisplay::isHelper()) {
        return;
    }

    callbacks.init = silentInit;
    callbacks.cleanup = silentCleanup;
    callbacks.decodeAndPlaySample = silentSample;
}

bool windowFrame(int& x, int& y, int& width, int& height)
{
    if (!ForkMultiDisplay::isHelper()) {
        return false;
    }
#ifdef Q_OS_DARWIN
    return MultiDisplayMac::helperFrame(ForkMultiDisplay::targetDisplay(), x, y, width, height);
#else
    (void)x;
    (void)y;
    (void)width;
    (void)height;
    return false;
#endif
}

}
