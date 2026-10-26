#include "forkdebugchannel.h"

#include "forkdebugrules.h"
#include "streaming/session.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtDebug>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <climits>
#include <cstring>
#include <mutex>
#include <thread>

#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include "SDL_compat.h"

namespace ForkDebugChannel
{
namespace
{
    using Clock = std::chrono::steady_clock;
    using ForkDebugRules::Level;

    // A request, at most; anything longer is refused
    constexpr size_t k_MaxRequest = 64 * 1024;

    // SDL2's categories, SDL_LOG_CATEGORY_APPLICATION up to SDL_LOG_CATEGORY_CUSTOM
    constexpr int k_Categories = SDL_LOG_CATEGORY_CUSTOM;
    int s_NormalPriority[k_Categories];
    bool s_Pinned = false;

    // The level, its deadline and what status reports
    std::mutex s_Mutex;
    Level s_Level = Level::Info;
    Clock::time_point s_LevelUntil;
    QString s_LogFile;
    QString s_Version;
    std::function<uint64_t()> s_LogBytes;
    uint64_t s_LogLimit = 0;

    std::thread s_Thread;
    int s_Listener = -1;
    int s_Wake[2] = {-1, -1}; // a pipe whose write ends the thread's poll
    QByteArray s_SocketPath;

    QString socketPath()
    {
        return QDir::homePath() + QStringLiteral("/Library/Application Support/LuzLunar/debug.sock");
    }

    void closeOnExec(int fd)
    {
        fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
    }

    // With s_Mutex held
    void applyLevel(Level level, const QString& why)
    {
        s_Level = level;
        if (s_Pinned) {
            for (int category = 0; category < k_Categories; category++) {
                SDL_LogSetPriority(category, static_cast<SDL_LogPriority>(ForkDebugRules::sdlPriority(level, s_NormalPriority[category])));
            }
        }
        qInfo().noquote() << "[fork] Debug channel: log level" << ForkDebugRules::levelName(level) << why;
    }

    // With s_Mutex held
    QJsonObject state()
    {
        QJsonObject out;
        out["app"] = QStringLiteral("LuzLunar");
        out["version"] = s_Version;
        out["pid"] = static_cast<qint64>(getpid());
        out["logFile"] = s_LogFile;
        out["logBytes"] = static_cast<qint64>(s_LogBytes ? s_LogBytes() : 0);
        out["logLimit"] = static_cast<qint64>(s_LogLimit);
        out["level"] = ForkDebugRules::levelName(s_Level);
        qint64 left = 0;
        if (s_Level != Level::Info) {
            left = std::max<qint64>(0, std::chrono::duration_cast<std::chrono::seconds>(s_LevelUntil - Clock::now()).count());
        }
        out["secondsLeft"] = left;
        out["streaming"] = Session::get() != nullptr;
        return out;
    }

    QByteArray answer(const QByteArray& request)
    {
        QJsonDocument document = QJsonDocument::fromJson(request.trimmed());
        QJsonObject body = document.object();
        QString op = body.value("op").toString();
        QString error;

        std::lock_guard<std::mutex> lock(s_Mutex);
        if (!document.isObject()) {
            error = QStringLiteral("the request must be a JSON object");
        }
        else if (op == "status") {
        }
        else if (op == "level") {
            QJsonValue minutesValue = body.value("minutes");
            auto level = ForkDebugRules::parseLevel(body.value("level").toString().toStdString());
            auto minutes = ForkDebugRules::minutes(!minutesValue.isUndefined(), minutesValue.toDouble(-1));
            if (!level) {
                error = QStringLiteral("level must be info, debug or verbose");
            }
            else if (!minutes) {
                error = QStringLiteral("minutes must be 1 to %1").arg(ForkDebugRules::k_MaxMinutes);
            }
            else if (*level == Level::Info) {
                applyLevel(Level::Info, QStringLiteral("(asked for)"));
            }
            else {
                s_LevelUntil = Clock::now() + std::chrono::minutes(*minutes);
                applyLevel(*level, QStringLiteral("for %1 minutes").arg(*minutes));
            }
        }
        else if (op == "mark") {
            if (!body.value("text").isString()) {
                error = QStringLiteral("a mark needs text");
            }
            else {
                qInfo().noquote() << "[fork] Debug channel: mark:"
                                  << QString::fromStdString(ForkDebugRules::cleanMark(body.value("text").toString().toStdString()));
            }
        }
        else {
            error = QStringLiteral("op must be status, level or mark");
        }

        QJsonObject reply = state();
        reply["ok"] = error.isEmpty();
        if (!error.isEmpty()) {
            reply["error"] = error;
        }
        return QJsonDocument(reply).toJson(QJsonDocument::Compact) + '\n';
    }

    void serveClient(int client)
    {
        uid_t uid;
        gid_t gid;
        if (getpeereid(client, &uid, &gid) != 0 || uid != getuid()) {
            return;
        }
        int one = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        timeval timeout = {2, 0}; // a client that stalls doesn't hold the channel
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        QByteArray request;
        char buffer[4096];
        while (!request.contains('\n') && request.size() <= static_cast<qsizetype>(k_MaxRequest)) {
            ssize_t got = recv(client, buffer, sizeof(buffer), 0);
            if (got < 0 && errno == EINTR) {
                continue;
            }
            if (got <= 0) {
                break;
            }
            request.append(buffer, static_cast<qsizetype>(got));
        }
        if (request.size() > static_cast<qsizetype>(k_MaxRequest)) {
            request.clear();
        }

        QByteArray reply = answer(request);
        for (qsizetype sent = 0; sent < reply.size();) {
            ssize_t wrote = send(client, reply.constData() + sent, static_cast<size_t>(reply.size() - sent), 0);
            if (wrote < 0 && errno == EINTR) {
                continue;
            }
            if (wrote <= 0) {
                break;
            }
            sent += wrote;
        }
    }

    void serve()
    {
        for (;;) {
            int timeout = -1;
            {
                std::lock_guard<std::mutex> lock(s_Mutex);
                if (s_Level != Level::Info) {
                    auto left = std::chrono::duration_cast<std::chrono::milliseconds>(s_LevelUntil - Clock::now()).count();
                    if (left <= 0) {
                        applyLevel(Level::Info, QStringLiteral("(the time asked for is up)"));
                    }
                    else {
                        timeout = static_cast<int>(std::min<long long>(left, INT_MAX));
                    }
                }
            }

            pollfd fds[2] = {{s_Listener, POLLIN, 0}, {s_Wake[0], POLLIN, 0}};
            if (poll(fds, 2, timeout) < 0) {
                if (errno == EINTR) {
                    continue;
                }
                qWarning() << "[fork] Debug channel: poll failed:" << strerror(errno);
                return;
            }
            if (fds[1].revents != 0) {
                return;
            }
            if (fds[0].revents & POLLIN) {
                int client = accept(s_Listener, nullptr, nullptr);
                if (client >= 0) {
                    closeOnExec(client);
                    serveClient(client);
                    close(client);
                }
            }
        }
    }
}

void pinLogPriorities()
{
    std::lock_guard<std::mutex> lock(s_Mutex);
    for (int category = 0; category < k_Categories; category++) {
        s_NormalPriority[category] = SDL_LogGetPriority(category);
        SDL_LogSetPriority(category, static_cast<SDL_LogPriority>(s_NormalPriority[category]));
    }
    s_Pinned = true;
}

void start(const QString& logFile, std::function<uint64_t()> logBytes, uint64_t logLimit)
{
    if (s_Thread.joinable()) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(s_Mutex);
        s_LogFile = logFile;
        s_LogBytes = std::move(logBytes);
        s_LogLimit = logLimit;
        s_Version = QCoreApplication::applicationVersion();
    }

    QString path = socketPath();
    QByteArray native = QFile::encodeName(path);
    sockaddr_un address = {};
    if (static_cast<size_t>(native.size()) >= sizeof(address.sun_path)) {
        qWarning() << "[fork] Debug channel: the socket's path is too long:" << path;
        return;
    }
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, native.constData(), static_cast<size_t>(native.size()));

    QString folder = QFileInfo(path).path();
    QDir().mkpath(folder);
    chmod(QFile::encodeName(folder).constData(), 0700);

    // Another LuzLunar answering there keeps its socket
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        bool answered = ::connect(probe, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0;
        close(probe);
        if (answered) {
            qInfo() << "[fork] Debug channel: another LuzLunar serves" << path;
            return;
        }
    }
    unlink(native.constData());

    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0) {
        qWarning() << "[fork] Debug channel: no socket:" << strerror(errno);
        return;
    }
    closeOnExec(listener);
    if (bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
        chmod(native.constData(), 0600) != 0 || listen(listener, 4) != 0 || pipe(s_Wake) != 0) {
        qWarning() << "[fork] Debug channel: can't serve" << path << ':' << strerror(errno);
        close(listener);
        unlink(native.constData());
        return;
    }
    closeOnExec(s_Wake[0]);
    closeOnExec(s_Wake[1]);
    s_Listener = listener;
    s_SocketPath = native;
    s_Thread = std::thread(serve);
    qInfo() << "[fork] Debug channel: serving" << path;
}

void stop()
{
    if (!s_Thread.joinable()) {
        return;
    }
    char byte = 0;
    while (write(s_Wake[1], &byte, 1) < 0 && errno == EINTR) {
    }
    s_Thread.join();
    close(s_Listener);
    close(s_Wake[0]);
    close(s_Wake[1]);
    s_Listener = s_Wake[0] = s_Wake[1] = -1;
    unlink(s_SocketPath.constData());

    std::lock_guard<std::mutex> lock(s_Mutex);
    if (s_Level != Level::Info) {
        applyLevel(Level::Info, QStringLiteral("(quitting)"));
    }
}
}
