#include "camera.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QList>
#include <QReadLocker>
#include <QSslConfiguration>
#include <QSslError>
#include <QSslSocket>
#include <QThread>
#include <QTimer>

#include "apolloclient.h"
#include "backend/identitymanager.h"
#include "backend/nvcomputer.h"
#include "camerarules.h"
#include "forkevents.h"
#include "forkpreferences.h"
#include "luzcamera.h"
#include "mac/camera_mac.h"
#include "mac/macdrivesetup.h"

#define CAM_TR(text) QCoreApplication::translate("ForkCamera", text)

struct ForkCamera::Shared
{
    std::mutex mutex;
    bool alive = true;
    bool ready = false;     // news for the main thread
    bool live = false;
    QString message;
    QThread* thread = nullptr;
    QObject* context = nullptr;     // lives on the thread; the link's events run there
};

namespace
{
    Uint32 eventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }

    qint64 nowMs()
    {
        static QElapsedTimer clock = [] {
            QElapsedTimer timer;
            timer.start();
            return timer;
        }();
        return clock.elapsed();
    }

    // To the main thread: whether the camera is on for the PC, and a message for beside the notch
    void tell(const std::shared_ptr<ForkCamera::Shared>& shared, bool live, const QString& message)
    {
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
            shared->live = live;
            if (!message.isEmpty()) {
                shared->message = message;
            }
            shared->ready = true;
        }
        SDL_Event event = {};
        event.type = eventType();
        SDL_PushEvent(&event);
    }

    const char* stateName(luzcamera::status_e state)
    {
        switch (state) {
        case luzcamera::status_e::live: return "live";
        case luzcamera::status_e::stopped: return "stopped";
        case luzcamera::status_e::denied: return "not allowed by macOS";
        case luzcamera::status_e::unavailable: return "unavailable";
        case luzcamera::status_e::off: return "off";
        }
        return "unknown";
    }

    class Link;

    // The link for the camera's thread, held there
    thread_local std::shared_ptr<Link> t_Link;

    // The connection and the camera, on the link's thread: everything here runs there
    class Link : public std::enable_shared_from_this<Link>
    {
    public:
        Link(const ApolloClient::Target& target, const QString& hostName, const QString& deviceId, std::shared_ptr<ForkCamera::Shared> shared)
            : m_Target(target), m_HostName(hostName), m_DeviceId(deviceId.toStdString()), m_Shared(std::move(shared))
        {
        }

        ~Link()
        {
            // The camera first, so no frame arrives for a link that's gone
            m_Capture.reset();
            delete m_Socket;
            delete m_Tick;
            delete m_Retry;
        }

        void begin()
        {
            QObject* context = m_Shared->context;
            m_Tick = new QTimer(context);
            m_Tick->setInterval(luzcamera::k_ping_interval_ms);
            std::weak_ptr<Link> weak = shared_from_this();
            QObject::connect(m_Tick, &QTimer::timeout, context, [weak] {
                if (std::shared_ptr<Link> link = weak.lock()) {
                    link->tick();
                }
            });
            m_Retry = new QTimer(context);
            m_Retry->setSingleShot(true);
            QObject::connect(m_Retry, &QTimer::timeout, context, [weak] {
                if (std::shared_ptr<Link> link = weak.lock()) {
                    link->connectNow();
                }
            });
            m_MacName = MacDriveSetup::computerName();

            // What serverinfo says first: Apollo's camera on, and the Camera permission for this Mac.
            // The request's event loop also runs the end of the stream, which drops the link: it stays
            // until this returns, and then goes.
            std::shared_ptr<Link> self = shared_from_this();
            ApolloClient::HostInfo info = ApolloClient(m_Target).hostInfo();
            if (t_Link.get() != this) {
                return;
            }
            switch (CameraRules::offer(info.answered, info.camera, info.permissions)) {
            case CameraRules::Offer::NoCamera:
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s's Apollo has Mac Camera off", qPrintable(m_HostName));
                m_GaveUp = true;
                return;
            case CameraRules::Offer::NoPermission:
                tell(m_Shared, false, CAM_TR("%1's Apollo doesn't give this Mac the Camera permission").arg(m_HostName));
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s's Apollo doesn't give this Mac the Camera permission", qPrintable(m_HostName));
                m_GaveUp = true;
                return;
            case CameraRules::Offer::Connect:
                break;
            }
            connectNow();
        }

    private:
        void connectNow()
        {
            closeSocket();
            m_Upgraded = false;
            m_Answer.clear();
            m_Reader = luzcamera::reader_t();
            m_PinMismatch = false;

            QObject* context = m_Shared->context;
            std::weak_ptr<Link> weak = shared_from_this();
            m_Socket = new QSslSocket(context);
            m_Socket->setSslConfiguration(IdentityManager::get()->getSslConfig());
            // The PC's certificate is the one pinned at pairing, as for every request to it
            QSslCertificate serverCert = m_Target.serverCert;
            QSslSocket* socket = m_Socket;
            QObject::connect(socket, QOverload<const QList<QSslError>&>::of(&QSslSocket::sslErrors), context, [socket, serverCert](const QList<QSslError>& errors) {
                for (const QSslError& error : errors) {
                    if (error.certificate() != serverCert) {
                        return;
                    }
                }
                socket->ignoreSslErrors(errors);
            });
            QObject::connect(socket, &QSslSocket::encrypted, context, [weak, socket] {
                std::shared_ptr<Link> link = weak.lock();
                if (link && link->m_Socket == socket) {
                    link->encrypted();
                }
            });
            QObject::connect(socket, &QIODevice::readyRead, context, [weak, socket] {
                std::shared_ptr<Link> link = weak.lock();
                if (link && link->m_Socket == socket) {
                    link->readable();
                }
            });
            QObject::connect(socket, &QAbstractSocket::disconnected, context, [weak, socket] {
                std::shared_ptr<Link> link = weak.lock();
                if (link && link->m_Socket == socket) {
                    link->lost("the connection closed");
                }
            });
            QObject::connect(socket, &QAbstractSocket::errorOccurred, context, [weak, socket](QAbstractSocket::SocketError) {
                std::shared_ptr<Link> link = weak.lock();
                if (link && link->m_Socket == socket) {
                    link->lost(socket->errorString().toStdString());
                }
            });
            m_ConnectStartedMs = nowMs();
            m_LastHeardMs = nowMs();
            m_Tick->start();
            m_Socket->connectToHostEncrypted(m_Target.address.address(), m_Target.httpsPort);
        }

        void closeSocket()
        {
            if (m_Socket != nullptr) {
                QSslSocket* old = m_Socket;
                m_Socket = nullptr;
                old->disconnect();
                old->abort();
                old->deleteLater();
            }
        }

        void encrypted()
        {
            // A certificate the system trusts raises no SSL errors, so compare it with the pinned one too
            if (m_Socket->peerCertificate() != m_Target.serverCert) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s's certificate isn't the one it was paired with", qPrintable(m_HostName));
                m_PinMismatch = true;
                giveUp();
                return;
            }
            QString hostPort = QString("%1:%2").arg(m_Target.address.address()).arg(m_Target.httpsPort);
            QByteArray request = QByteArray("GET ") + luzcamera::k_path + " HTTP/1.1\r\nHost: " + hostPort.toUtf8() +
                                 "\r\nUpgrade: " + luzcamera::k_upgrade + "\r\nConnection: Upgrade\r\n\r\n";
            m_Socket->write(request);
        }

        void readable()
        {
            QByteArray bytes = m_Socket->readAll();
            m_LastHeardMs = nowMs();
            if (!m_Upgraded) {
                m_Answer += bytes;
                int end = m_Answer.indexOf("\r\n\r\n");
                if (end < 0) {
                    if (m_Answer.size() > 16 * 1024) {
                        lost("a garbled answer");
                    }
                    return;
                }
                QByteArray head = m_Answer.left(end);
                QByteArray rest = m_Answer.mid(end + 4);
                m_Answer.clear();
                int lineEnd = head.indexOf("\r\n");
                std::string statusLine = (lineEnd < 0 ? head : head.left(lineEnd)).toStdString();
                CameraRules::Answer answer = CameraRules::answer(statusLine, rest.trimmed().toStdString());
                if (answer != CameraRules::Answer::Upgraded) {
                    refused(answer, statusLine + (rest.isEmpty() ? std::string() : ", " + rest.trimmed().toStdString()));
                    return;
                }
                m_Upgraded = true;
                m_Failures = 0;
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: connected to %s; it starts the camera when an app there opens Mac Camera",
                            qPrintable(m_HostName));
                send(luzcamera::make_hello(m_MacName));
                bytes = rest;
            }
            m_Reader.feed(reinterpret_cast<const std::uint8_t*>(bytes.constData()), static_cast<std::size_t>(bytes.size()));
            luzcamera::message_t message;
            for (;;) {
                luzcamera::reader_t::result_e result = m_Reader.next(message);
                if (result == luzcamera::reader_t::result_e::need_more) {
                    break;
                }
                if (result == luzcamera::reader_t::result_e::error) {
                    lost("a message too large");
                    return;
                }
                handle(message);
                if (m_Socket == nullptr) {
                    return;
                }
            }
        }

        void handle(const luzcamera::message_t& message)
        {
            switch (message.type()) {
            case luzcamera::type_e::start: {
                luzcamera::start_t start;
                if (luzcamera::parse_start(message, start)) {
                    startCamera(start);
                }
                break;
            }
            case luzcamera::type_e::stop:
                stopCamera("the last app on the PC closed it");
                break;
            case luzcamera::type_e::keyframe:
                if (m_Capture) {
                    m_Capture->requestKeyframe();
                }
                break;
            case luzcamera::type_e::bitrate: {
                std::uint32_t kbps = 0;
                if (luzcamera::parse_bitrate(message, kbps)) {
                    m_Bitrate.limit(kbps);
                    if (m_Capture) {
                        m_Capture->setBitrate(static_cast<int>(m_Bitrate.current()));
                    }
                }
                break;
            }
            default:
                // PING, and anything newer: hearing it is enough
                break;
            }
        }

        void startCamera(const luzcamera::start_t& start)
        {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s asks for this Mac's camera at %ux%u, %u fps, %u kbps",
                        qPrintable(m_HostName), start.width, start.height, start.fps, start.kbps);
            m_Bitrate.start(start.kbps > 0 ? start.kbps : luzcamera::default_kbps(start.width, start.height), nowMs());
            m_Queue.reset();
            if (!m_Capture) {
                std::weak_ptr<Link> weak = shared_from_this();
                QObject* context = m_Shared->context;
                auto number = std::make_shared<std::atomic<std::uint32_t>>(0);
                m_Capture = std::make_unique<MacCamera::Capture>(
                    [weak, context, number](const MacCamera::Frame& frame) {
                        // On a VideoToolbox thread: the message is made here, and sent from the link's thread
                        luzcamera::video_t video;
                        video.keyframe = frame.keyframe;
                        video.time_us = frame.timeUs;
                        video.number = ++*number;
                        video.width = static_cast<std::uint16_t>(frame.width);
                        video.height = static_cast<std::uint16_t>(frame.height);
                        auto bytes = std::make_shared<std::vector<std::uint8_t>>(luzcamera::make_video(video, frame.data, frame.size));
                        if (bytes->empty()) {
                            return;
                        }
                        bool keyframe = frame.keyframe;
                        QMetaObject::invokeMethod(context, [weak, bytes, keyframe] {
                            if (std::shared_ptr<Link> link = weak.lock()) {
                                link->sendVideo(*bytes, keyframe);
                            }
                        }, Qt::QueuedConnection);
                    },
                    [weak, context](MacCamera::State state, const std::string& detail) {
                        QMetaObject::invokeMethod(context, [weak, state, detail] {
                            if (std::shared_ptr<Link> link = weak.lock()) {
                                link->cameraState(state, detail);
                            }
                        }, Qt::QueuedConnection);
                    });
            }
            m_Capture->start(start.width, start.height, start.fps, static_cast<int>(m_Bitrate.current()), m_DeviceId);
        }

        void stopCamera(const char* why)
        {
            if (m_Capture) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: this Mac's camera goes off: %s", why);
                m_Capture->stop();
            }
        }

        void cameraState(MacCamera::State state, const std::string& detail)
        {
            luzcamera::status_e status = luzcamera::status_e::unavailable;
            QString message;
            bool live = false;
            switch (state) {
            case MacCamera::State::Live:
                status = luzcamera::status_e::live;
                live = true;
                message = CAM_TR("%1 is using this Mac's camera").arg(m_HostName);
                break;
            case MacCamera::State::Stopped:
                status = luzcamera::status_e::stopped;
                break;
            case MacCamera::State::Denied:
                status = luzcamera::status_e::denied;
                if (!m_ToldDenied) {
                    m_ToldDenied = true;
                    message = CAM_TR("%1 wants this Mac's camera: allow LuzLunar in System Settings › Privacy & Security › Camera").arg(m_HostName);
                }
                break;
            case MacCamera::State::Unavailable:
                status = luzcamera::status_e::unavailable;
                message = CAM_TR("This Mac's camera isn't available for %1: %2").arg(m_HostName, QString::fromStdString(detail));
                break;
            }
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: this Mac's camera is %s%s%s", stateName(status), detail.empty() ? "" : ": ", detail.c_str());
            if (m_Upgraded) {
                send(luzcamera::make_status(status, detail));
            }
            tell(m_Shared, live, message);
        }

        void sendVideo(const std::vector<std::uint8_t>& bytes, bool keyframe)
        {
            if (!m_Upgraded || m_Socket == nullptr) {
                return;
            }
            std::size_t queued = static_cast<std::size_t>(m_Socket->bytesToWrite() + m_Socket->encryptedBytesToWrite());
            switch (m_Queue.frame(keyframe, queued, m_Bitrate.current())) {
            case CameraRules::Queue::Verdict::Send:
                send(bytes);
                break;
            case CameraRules::Queue::Verdict::DropAndAskKeyframe:
                if (m_Capture) {
                    m_Capture->requestKeyframe();
                }
                break;
            case CameraRules::Queue::Verdict::Drop:
                break;
            }
        }

        void send(const std::vector<std::uint8_t>& bytes)
        {
            if (m_Socket != nullptr && !bytes.empty()) {
                m_Socket->write(reinterpret_cast<const char*>(bytes.data()), static_cast<qint64>(bytes.size()));
            }
        }

        void tick()
        {
            if (m_Socket == nullptr) {
                return;
            }
            qint64 now = nowMs();
            if (!m_Upgraded) {
                if (now - m_ConnectStartedMs > 15000) {
                    lost("no answer");
                }
                return;
            }
            if (now - m_LastHeardMs > luzcamera::k_silence_timeout_ms) {
                lost("nothing heard for 5 s");
                return;
            }
            send(luzcamera::make_ping(static_cast<std::uint64_t>(now)));
            // The bitrate follows what waits to be sent
            std::size_t queued = static_cast<std::size_t>(m_Socket->bytesToWrite() + m_Socket->encryptedBytesToWrite());
            if (m_Bitrate.update(queued, now) && m_Capture) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %u kbps with %lld ms waiting to be sent", m_Bitrate.current(),
                            static_cast<long long>(CameraRules::queuedMs(queued, m_Bitrate.current())));
                m_Capture->setBitrate(static_cast<int>(m_Bitrate.current()));
            }
        }

        void refused(CameraRules::Answer answer, const std::string& what)
        {
            closeSocket();
            m_Tick->stop();
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s answered %s", qPrintable(m_HostName), what.c_str());
            switch (answer) {
            case CameraRules::Answer::NoPermission:
                tell(m_Shared, false, CAM_TR("%1's Apollo doesn't give this Mac the Camera permission").arg(m_HostName));
                giveUp();
                return;
            case CameraRules::Answer::Unsupported:
                giveUp();
                return;
            case CameraRules::Answer::RetrySoon:
            case CameraRules::Answer::RetryLater:
            case CameraRules::Answer::Upgraded:
                break;
            }
            retry(answer);
        }

        void lost(const std::string& why)
        {
            if (m_Socket == nullptr || m_GaveUp) {
                return;
            }
            bool wasUpgraded = m_Upgraded;
            closeSocket();
            m_Tick->stop();
            m_Upgraded = false;
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: the connection to %s ended: %s", qPrintable(m_HostName), why.c_str());
            // The camera doesn't stay on for a PC that can't see it
            stopCamera("the connection to the PC ended");
            if (wasUpgraded) {
                m_Failures = 0;
            }
            retry(CameraRules::Answer::RetryLater);
        }

        void retry(CameraRules::Answer answer)
        {
            m_Failures++;
            int delay = CameraRules::retryDelayMs(answer, m_Failures);
            if (delay < 0 || m_GaveUp) {
                return;
            }
            m_Retry->start(delay);
        }

        void giveUp()
        {
            m_GaveUp = true;
            closeSocket();
            m_Tick->stop();
            m_Retry->stop();
            stopCamera("the PC can't take it");
        }

        ApolloClient::Target m_Target;
        QString m_HostName;
        std::string m_DeviceId;
        std::string m_MacName;
        std::shared_ptr<ForkCamera::Shared> m_Shared;
        QSslSocket* m_Socket = nullptr;
        QTimer* m_Tick = nullptr;
        QTimer* m_Retry = nullptr;
        QByteArray m_Answer;
        bool m_Upgraded = false;
        bool m_GaveUp = false;
        bool m_PinMismatch = false;
        bool m_ToldDenied = false;
        int m_Failures = 0;
        qint64 m_ConnectStartedMs = 0;
        qint64 m_LastHeardMs = 0;
        luzcamera::reader_t m_Reader;
        CameraRules::Bitrate m_Bitrate;
        CameraRules::Queue m_Queue;
        std::unique_ptr<MacCamera::Capture> m_Capture;
    };

}

ForkCamera::ForkCamera(NvComputer* computer)
    : m_Shared(std::make_shared<Shared>())
{
    eventType();
    ApolloClient::Target target = ApolloClient::targetFor(computer);
    QString hostName;
    {
        QReadLocker lock(&computer->lock);
        hostName = computer->name;
    }
    QString deviceId = ForkPreferences::get()->cameraDevice();

    m_Shared->thread = new QThread();
    m_Shared->thread->setObjectName(QStringLiteral("LuzLunar camera"));
    m_Shared->context = new QObject();
    m_Shared->context->moveToThread(m_Shared->thread);
    m_Shared->thread->start();

    std::shared_ptr<Shared> shared = m_Shared;
    QMetaObject::invokeMethod(m_Shared->context, [target, hostName, deviceId, shared] {
        t_Link = std::make_shared<Link>(target, hostName, deviceId, shared);
        t_Link->begin();
    }, Qt::QueuedConnection);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s offers Mac Camera; connecting", qPrintable(hostName));
}

ForkCamera::~ForkCamera()
{
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        m_Shared->alive = false;
    }
    // The camera goes off and the connection closes on the link's thread, before it ends
    QMetaObject::invokeMethod(m_Shared->context, [] {
        t_Link.reset();
    }, Qt::BlockingQueuedConnection);
    m_Shared->thread->quit();
    m_Shared->thread->wait();
    delete m_Shared->context;
    delete m_Shared->thread;
    m_Shared->context = nullptr;
    m_Shared->thread = nullptr;
}

bool ForkCamera::handleEvent(const SDL_Event& event)
{
    if (event.type != eventType()) {
        return false;
    }
    QString message;
    bool live;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        if (!m_Shared->ready) {
            return false;
        }
        m_Shared->ready = false;
        message = m_Shared->message;
        m_Shared->message.clear();
        live = m_Shared->live;
    }
    bool changed = live != m_Live;
    m_Live = live;
    if (!message.isEmpty()) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Camera: %s", qPrintable(message));
        if (m_MessageSink) {
            m_MessageSink(message);
        }
    }
    return changed || !message.isEmpty();
}

void ForkCamera::setMessageSink(std::function<bool(const QString&)> sink)
{
    m_MessageSink = std::move(sink);
}
