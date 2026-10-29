#include "forkdisplayextend.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>

#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include "SDL_compat.h"

namespace
{
    // A reply line can't be longer than this (the Host's are a few hundred bytes)
    constexpr int k_MaxLineBytes = 64 * 1024;

    int remaining(const QElapsedTimer& timer, int timeoutMs)
    {
        return std::max(0, timeoutMs - static_cast<int>(timer.elapsed()));
    }

    bool setNonBlocking(int fd)
    {
        int flags = fcntl(fd, F_GETFL, 0);
        return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
    }
}

QString ForkDisplayExtend::socketPath()
{
    return QDir::homePath() + QStringLiteral("/Library/Application Support/DisplayExtend/luzlunar.sock");
}

bool ForkDisplayExtend::available()
{
    return QFile::exists(socketPath());
}

ForkDisplayExtend::ForkDisplayExtend() = default;

ForkDisplayExtend::~ForkDisplayExtend()
{
    close();
}

bool ForkDisplayExtend::open(int timeoutMs)
{
    close();

    QByteArray path = QFile::encodeName(socketPath());
    sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    if (path.size() >= static_cast<int>(sizeof(address.sun_path))) {
        return false;
    }
    std::memcpy(address.sun_path, path.constData(), static_cast<size_t>(path.size()));

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return false;
    }
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    setNonBlocking(fd);

    if (::connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        if (errno != EINPROGRESS && errno != EAGAIN) {
            ::close(fd);
            return false;
        }
        pollfd waiting = { fd, POLLOUT, 0 };
        int error = 0;
        socklen_t length = sizeof(error);
        if (poll(&waiting, 1, timeoutMs) != 1 || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) != 0 || error != 0) {
            ::close(fd);
            return false;
        }
    }

    m_Fd = fd;
    m_Buffer.clear();
    m_Events.clear();
    return true;
}

void ForkDisplayExtend::close()
{
    int fd = m_Fd.exchange(-1);
    if (fd >= 0) {
        ::close(fd);
    }
}

void ForkDisplayExtend::interrupt()
{
    int fd = m_Fd;
    if (fd >= 0) {
        ::shutdown(fd, SHUT_RDWR);
    }
}

bool ForkDisplayExtend::writeLine(const QByteArray& line)
{
    QByteArray data = line + '\n';
    qsizetype sent = 0;
    while (sent < data.size()) {
        ssize_t n = ::send(m_Fd, data.constData() + sent, static_cast<size_t>(data.size() - sent), 0);
        if (n > 0) {
            sent += n;
            continue;
        }
        if (n < 0 && (errno == EAGAIN || errno == EINTR)) {
            pollfd waiting = { m_Fd, POLLOUT, 0 };
            if (poll(&waiting, 1, 1000) == 1) {
                continue;
            }
        }
        close();
        return false;
    }
    return true;
}

bool ForkDisplayExtend::readLine(QByteArray& line, int timeoutMs)
{
    QElapsedTimer timer;
    timer.start();

    for (;;) {
        qsizetype end = m_Buffer.indexOf('\n');
        if (end >= 0) {
            line = m_Buffer.left(end);
            m_Buffer.remove(0, end + 1);
            return true;
        }
        if (m_Fd < 0 || m_Buffer.size() > k_MaxLineBytes) {
            close();
            return false;
        }

        pollfd waiting = { m_Fd, POLLIN, 0 };
        int ready = poll(&waiting, 1, remaining(timer, timeoutMs));
        if (ready == 0) {
            return false;
        }
        if (ready < 0) {
            if (errno == EINTR) {
                continue;
            }
            close();
            return false;
        }

        char chunk[4096];
        ssize_t n = ::recv(m_Fd, chunk, sizeof(chunk), 0);
        if (n > 0) {
            m_Buffer.append(chunk, n);
        }
        else if (n == 0 || (errno != EAGAIN && errno != EINTR)) {
            // The Host closed the connection
            close();
            return false;
        }
    }
}

QJsonObject ForkDisplayExtend::request(const QString& op, const QJsonObject& arguments, int timeoutMs, QString* error)
{
    auto fail = [error](const QString& text) {
        if (error != nullptr) {
            *error = text;
        }
        return QJsonObject();
    };

    if (m_Fd < 0) {
        return fail(QStringLiteral("DisplayExtend's Host isn't connected"));
    }

    int id = m_NextId++;
    QJsonObject message = arguments;
    message.insert("id", id);
    message.insert("op", op);
    if (!writeLine(QJsonDocument(message).toJson(QJsonDocument::Compact))) {
        return fail(QStringLiteral("DisplayExtend's Host closed the connection"));
    }

    QElapsedTimer timer;
    timer.start();
    for (;;) {
        QByteArray line;
        if (!readLine(line, remaining(timer, timeoutMs))) {
            return fail(m_Fd < 0 ? QStringLiteral("DisplayExtend's Host closed the connection")
                                 : QStringLiteral("DisplayExtend's Host didn't answer in time"));
        }

        QJsonObject reply = QJsonDocument::fromJson(line).object();
        if (reply.contains("event")) {
            m_Events.append(reply);
            continue;
        }
        if (reply.value("id").toInt() != id) {
            // A late reply to an earlier request that timed out
            continue;
        }
        if (!reply.value("ok").toBool()) {
            return fail(reply.value("error").toString(QStringLiteral("DisplayExtend's Host refused")));
        }
        return reply;
    }
}

QJsonObject ForkDisplayExtend::nextEvent(int timeoutMs)
{
    if (!m_Events.isEmpty()) {
        return m_Events.takeFirst();
    }

    QElapsedTimer timer;
    timer.start();
    for (;;) {
        QByteArray line;
        if (!readLine(line, remaining(timer, timeoutMs))) {
            return QJsonObject();
        }
        QJsonObject message = QJsonDocument::fromJson(line).object();
        if (message.contains("event")) {
            return message;
        }
    }
}

ForkDisplayExtend::Status ForkDisplayExtend::status(int timeoutMs)
{
    Status status;
    QJsonObject reply = request(QStringLiteral("status"), QJsonObject(), timeoutMs, &status.error);
    if (reply.isEmpty()) {
        return status;
    }
    status.ok = true;

    QJsonObject imac = reply.value("imac").toObject();
    status.imacConnected = imac.value("connected").toBool();
    status.imacAddress = imac.value("address").toString();
    status.displayId = static_cast<uint32_t>(imac.value("displayId").toDouble());
    status.width = imac.value("width").toInt();
    status.height = imac.value("height").toInt();
    status.hz = imac.value("hz").toInt();

    QJsonObject latency = reply.value("latency").toObject();
    status.p50Ms = latency.value("p50Ms").toDouble();
    status.p95Ms = latency.value("p95Ms").toDouble();
    status.frames = latency.value("frames").toInt();

    QJsonObject moonlight = reply.value("moonlight").toObject();
    status.moonlightVerified = moonlight.value("verified").toBool();
    status.moonlightVersion = moonlight.value("version").toString();
    for (const QJsonValue& id : moonlight.value("pairedHostIds").toArray()) {
        status.pairedHostIds.append(id.toString());
    }

    QJsonObject direct = reply.value("direct").toObject();
    status.directSupported = direct.value("supported").toBool();

    // Codecs the bridge names; a Host before 1.6.5 names none, and its iMac streams H.264
    auto codecs = [](const QJsonValue& list, std::vector<ForkDisplayRoute::Codec>* out) {
        if (!list.isArray()) {
            return;
        }
        std::vector<ForkDisplayRoute::Codec> parsed;
        for (const QJsonValue& name : list.toArray()) {
            ForkDisplayRoute::Codec codec;
            if (ForkDisplayRoute::parseCodec(name.toString().toStdString(), &codec)) {
                parsed.push_back(codec);
            }
        }
        if (!parsed.empty()) {
            *out = parsed;
        }
    };
    codecs(direct.value("codecs"), &status.codecs.direct);
    codecs(imac.value("hardwareDecoders"), &status.codecs.hardware);
    return status;
}

std::vector<ForkDisplayRoute::Probe> ForkDisplayExtend::probe(const QStringList& addresses, int port, int count, int timeoutMs)
{
    std::vector<ForkDisplayRoute::Probe> results;

    QJsonObject arguments {
        { "addresses", QJsonArray::fromStringList(addresses) },
        { "port", port },
        { "count", count },
    };
    QJsonObject reply = request(QStringLiteral("probe"), arguments, timeoutMs);
    for (const QJsonValue& value : reply.value("results").toArray()) {
        QJsonObject result = value.toObject();
        ForkDisplayRoute::Probe probe;
        probe.address = result.value("address").toString().toStdString();
        probe.count = count;
        probe.failures = result.value("failures").toInt();
        probe.medianMs = result.value("medianMs").toDouble(-1);
        probe.maxMs = result.value("maxMs").toDouble(-1);
        results.push_back(probe);
    }
    return results;
}

bool ForkDisplayExtend::pairMoonlight(const QString& address, const QString& pin, int timeoutMs, QString* error)
{
    QJsonObject arguments { { "address", address }, { "pin", pin } };
    return !request(QStringLiteral("pairMoonlight"), arguments, timeoutMs, error).isEmpty();
}

bool ForkDisplayExtend::startDirect(const Direct& direct, int timeoutMs, QString* error)
{
    QElapsedTimer timer;
    timer.start();

    QJsonObject arguments {
        { "address", direct.address },
        { "app", direct.app },
        { "hostUniqueId", direct.hostUniqueId },
        { "width", direct.width },
        { "height", direct.height },
        { "fps", direct.fps },
        { "bitrateKbps", direct.bitrateKbps },
    };
    // A Host before 1.6.5 takes no codec and streams H.264
    if (direct.codec != ForkDisplayRoute::Codec::H264) {
        arguments.insert("videoCodec", QString::fromLatin1(ForkDisplayRoute::codecName(direct.codec)));
    }
    if (request(QStringLiteral("startDirect"), arguments, remaining(timer, timeoutMs), error).isEmpty()) {
        return false;
    }

    // "switching", then "streaming" once the iMac's Moonlight shows the stream
    for (;;) {
        QJsonObject event = nextEvent(remaining(timer, timeoutMs));
        if (event.isEmpty()) {
            if (error != nullptr) {
                *error = m_Fd < 0 ? QStringLiteral("DisplayExtend's Host closed the connection")
                                  : QStringLiteral("the iMac's Moonlight didn't start streaming in time");
            }
            return false;
        }
        if (event.value("event").toString() != QLatin1String("direct")) {
            continue;
        }

        QString state = event.value("state").toString();
        if (state == QLatin1String("streaming")) {
            return true;
        }
        if (state == QLatin1String("failed") || state == QLatin1String("ended")) {
            if (error != nullptr) {
                *error = event.value("error").toString(QStringLiteral("the iMac's Moonlight stopped"));
            }
            return false;
        }
    }
}

void ForkDisplayExtend::stopDirect(int timeoutMs)
{
    if (m_Fd >= 0) {
        request(QStringLiteral("stopDirect"), QJsonObject(), timeoutMs);
    }
}

namespace ForkRouteProbe
{

namespace
{
    // One connect, in milliseconds; -1 if it failed or timed out
    double connectOnce(const addrinfo* target, int timeoutMs)
    {
        int fd = socket(target->ai_family, SOCK_STREAM, IPPROTO_TCP);
        if (fd < 0) {
            return -1;
        }
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        fcntl(fd, F_SETFD, FD_CLOEXEC);
        setNonBlocking(fd);

        auto start = std::chrono::steady_clock::now();
        double elapsed = -1;
        if (::connect(fd, target->ai_addr, target->ai_addrlen) == 0) {
            elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
        }
        else if (errno == EINPROGRESS) {
            pollfd waiting = { fd, POLLOUT, 0 };
            int error = 0;
            socklen_t length = sizeof(error);
            if (poll(&waiting, 1, timeoutMs) == 1 && getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0) {
                elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
            }
        }
        ::close(fd);
        return elapsed;
    }
}

ForkDisplayRoute::Probe tcpConnects(const QString& address, uint16_t port, int count, int timeoutMs)
{
    ForkDisplayRoute::Probe probe;
    probe.address = address.toStdString();
    probe.count = count;

    addrinfo hints = {};
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_NUMERICSERV;
    addrinfo* targets = nullptr;
    QByteArray host = address.toUtf8();
    QByteArray service = QByteArray::number(port);
    if (getaddrinfo(host.constData(), service.constData(), &hints, &targets) != 0 || targets == nullptr) {
        probe.failures = count;
        return probe;
    }

    connectOnce(targets, timeoutMs);

    std::vector<double> times;
    for (int i = 0; i < count; i++) {
        double ms = connectOnce(targets, timeoutMs);
        if (ms >= 0) {
            times.push_back(ms);
        }
        else {
            probe.failures++;
        }
    }
    freeaddrinfo(targets);

    if (!times.empty()) {
        probe.medianMs = ForkDisplayRoute::median(times);
        probe.maxMs = *std::max_element(times.begin(), times.end());
    }
    return probe;
}

}
