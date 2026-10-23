#include "bitrateclient.h"

#include <mutex>

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QReadLocker>
#include <QThread>
#include <QThreadPool>

#include "apolloclient.h"
#include "backend/nvcomputer.h"
#include "forkevents.h"
#include "streamstats.h"

struct BitrateClient::Shared
{
    ApolloClient::Target target;
    QString hostName;
    int ownKbps = 0;

    mutable std::mutex mutex;
    bool alive = true;
    bool queued = false;    // a worker job will send wantKbps
    int wantKbps = 0;       // the newest bitrate to ask for; 0 for none
    BitrateState::State state;
};

namespace
{
    // How often a request is tried when the PC doesn't answer, and how long each try waits
    const int k_Tries = 3;
    const int k_TimeoutMs = 3000;
    const int k_RetryDelayMs = 500;
    // How often a change the PC took is asked about again, until it's applied
    const int k_ConfirmTries = 3;
    const int k_ConfirmDelayMs = 500;
    // How long an Apollo that says when its encoder exists is waited for
    const int k_KnownWaitMs = 10000;
    const int k_KnownPollMs = 1000;

    Uint32 eventType()
    {
        static Uint32 type = ForkEvents::registerType();
        return type;
    }

    QThreadPool* workerPool()
    {
        // The pool belongs to the app, so a stream can end without waiting for a request in flight
        static QThreadPool* pool = [] {
            QThreadPool* newPool = new QThreadPool(QCoreApplication::instance());
            newPool->setMaxThreadCount(1);
            return newPool;
        }();
        return pool;
    }

    bool alive(const std::shared_ptr<BitrateClient::Shared>& shared)
    {
        std::lock_guard<std::mutex> lock(shared->mutex);
        return shared->alive;
    }

    const char* whyText(BitrateState::Why why)
    {
        switch (why) {
        case BitrateState::Why::NotApollo:
            return "not LuzLunar's Apollo";
        case BitrateState::Why::OlderApollo:
            return "an older Apollo";
        case BitrateState::Why::OffInApollo:
            return "off in Apollo";
        case BitrateState::Why::Encoder:
            return "its encoder can't";
        case BitrateState::Why::NoPermission:
            return "no permission";
        case BitrateState::Why::NotStreaming:
            return "it doesn't see this stream";
        case BitrateState::Why::None:
            break;
        }
        return "";
    }

    BitrateState::Reply parse(const ApolloClient::Response& response)
    {
        BitrateState::Reply reply;
        reply.httpStatus = response.httpStatus;
        QJsonObject json = QJsonDocument::fromJson(response.body).object();
        reply.hasStatus = json.contains(QStringLiteral("target")) && json.contains(QStringLiteral("live"));
        reply.target = json.value(QStringLiteral("target")).toInt();
        reply.min = json.value(QStringLiteral("min")).toInt();
        reply.max = json.value(QStringLiteral("max")).toInt();
        reply.live = json.value(QStringLiteral("live")).toBool(true);
        reply.hasKnown = json.contains(QStringLiteral("known"));
        reply.known = json.value(QStringLiteral("known")).toBool();
        reply.pending = json.value(QStringLiteral("pending")).toBool();
        return reply;
    }

    // Hands the state to the stats and, when it changed, to the main thread
    void publish(const std::shared_ptr<BitrateClient::Shared>& shared, const BitrateState::State& before)
    {
        BitrateState::State now;
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return;
            }
            now = shared->state;
            int target = now.targetKbps > 0 ? now.targetKbps : shared->ownKbps;
            ForkStreamStats::setBitrate(target / 1000.0, shared->ownKbps / 1000.0);
        }
        if (now.known != before.known || now.live != before.live || now.why != before.why || now.targetKbps != before.targetKbps ||
                now.pending != before.pending || now.minKbps != before.minKbps || now.maxKbps != before.maxKbps) {
            SDL_Event event = {};
            event.type = eventType();
            SDL_PushEvent(&event);
        }
    }

    BitrateState::Next update(const std::shared_ptr<BitrateClient::Shared>& shared, const BitrateState::Reply& reply)
    {
        BitrateState::State before;
        BitrateState::Next next;
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            before = shared->state;
            next = BitrateState::apply(shared->state, reply);
            if (before.live && !shared->state.live) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Bitrate: %s can't change the bitrate during the stream (%s, HTTP %d)",
                            qPrintable(shared->hostName), whyText(shared->state.why), reply.httpStatus);
                shared->wantKbps = 0;
            }
        }
        publish(shared, before);
        return next;
    }

    // GET /actions/bitrate, or POST body to it; tried again while the PC doesn't answer
    ApolloClient::Response ask(ApolloClient& client, const std::shared_ptr<BitrateClient::Shared>& shared, const QByteArray* body)
    {
        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = k_TimeoutMs;
        options.maxResponseBytes = 64 * 1024;
        options.cancelled = [shared] { return !alive(shared); };

        ApolloClient::Response response;
        for (int attempt = 0; attempt < k_Tries; attempt++) {
            response = client.request(QStringLiteral("actions/bitrate"), QString(), body, options);
            if (response.httpStatus != 0) {
                break;
            }
            {
                // A newer request replaces this one; the stream ending ends it
                std::lock_guard<std::mutex> lock(shared->mutex);
                if (!shared->alive || (body != nullptr && shared->wantKbps != 0)) {
                    break;
                }
            }
            QThread::msleep(k_RetryDelayMs);
        }
        return response;
    }

    // On the worker, first: whether the PC changes bitrates live, and what it can do now
    void startUp(const std::shared_ptr<BitrateClient::Shared>& shared)
    {
        ApolloClient client(shared->target);
        ApolloClient::HostInfo info = client.hostInfo();
        BitrateState::State before;
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            before = shared->state;
            BitrateState::serverInfo(shared->state, info.answered, info.permissions, info.bitrate.toStdString());
            if (!shared->state.live) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Bitrate: %s doesn't change a stream's bitrate (%s), so it stays at %d kbps",
                            qPrintable(shared->hostName), whyText(shared->state.why), shared->ownKbps);
            }
        }
        publish(shared, before);
        if (info.answered && info.bitrate != QLatin1String("1")) {
            return;
        }

        QElapsedTimer waited;
        waited.start();
        for (;;) {
            ApolloClient::Response response = ask(client, shared, nullptr);
            if (response.httpStatus == 0) {
                // The first change finds out
                return;
            }
            BitrateState::Next next = update(shared, parse(response));
            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                if (next != BitrateState::Next::AskAgain || !shared->alive || shared->wantKbps != 0 || waited.elapsed() >= k_KnownWaitMs) {
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Bitrate: %s runs the stream at %d kbps, between %d and %d kbps; %s",
                                qPrintable(shared->hostName), shared->state.targetKbps, shared->state.minKbps, shared->state.maxKbps,
                                !shared->state.live ? "its encoder can't change it" :
                                shared->state.known ? "its encoder can change it" : "not known yet whether its encoder can change it");
                    return;
                }
            }
            QThread::msleep(k_KnownPollMs);
        }
    }

    // On the worker: sends the newest bitrate asked for until none waits, confirming each
    void send(std::shared_ptr<BitrateClient::Shared> shared)
    {
        ApolloClient client(shared->target);
        for (;;) {
            int kbps;
            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                if (!shared->alive || !shared->state.live || shared->wantKbps == 0) {
                    shared->queued = false;
                    shared->wantKbps = 0;
                    return;
                }
                kbps = shared->wantKbps;
                shared->wantKbps = 0;
            }

            QJsonObject request;
            request.insert(QStringLiteral("kbps"), kbps);
            QByteArray body = QJsonDocument(request).toJson(QJsonDocument::Compact);
            ApolloClient::Response response = ask(client, shared, &body);
            if (response.httpStatus == 0) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Bitrate: %s didn't answer the request for %d kbps: %s",
                            qPrintable(shared->hostName), kbps, qPrintable(response.networkError));
                continue;
            }
            BitrateState::Reply reply = parse(response);
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Bitrate: asked %s for %d kbps: HTTP %d, %d kbps%s",
                        qPrintable(shared->hostName), kbps, reply.httpStatus, reply.target, reply.pending ? ", pending" : "");
            BitrateState::Next next = update(shared, reply);

            // Until the PC has applied it, unless a newer request takes over
            for (int i = 0; next == BitrateState::Next::AskAgain && i < k_ConfirmTries; i++) {
                {
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    if (!shared->alive || shared->wantKbps != 0) {
                        break;
                    }
                }
                QThread::msleep(k_ConfirmDelayMs);
                ApolloClient::Response status = ask(client, shared, nullptr);
                if (status.httpStatus == 0) {
                    break;
                }
                next = update(shared, parse(status));
            }
        }
    }
}

BitrateClient::BitrateClient(NvComputer* computer, int ownKbps)
    : m_Shared(std::make_shared<Shared>())
{
    // Both on this thread before a worker uses them
    eventType();
    workerPool();

    m_Shared->target = ApolloClient::targetFor(computer);
    m_Shared->ownKbps = ownKbps;
    {
        QReadLocker lock(&computer->lock);
        m_Shared->hostName = computer->name;
    }
    ForkStreamStats::setBitrate(ownKbps / 1000.0, ownKbps / 1000.0);

    std::shared_ptr<Shared> shared = m_Shared;
    workerPool()->start([shared] { startUp(shared); });
}

BitrateClient::~BitrateClient()
{
    // A request in flight gives up, and what it gets back is dropped
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    m_Shared->alive = false;
    ForkStreamStats::setBitrate(0, 0);
}

void BitrateClient::request(int kbps)
{
    if (kbps <= 0) {
        return;
    }
    bool startWorker = false;
    {
        std::lock_guard<std::mutex> lock(m_Shared->mutex);
        if (!m_Shared->alive || !m_Shared->state.live) {
            return;
        }
        m_Shared->wantKbps = kbps;
        if (!m_Shared->queued) {
            m_Shared->queued = true;
            startWorker = true;
        }
    }
    if (startWorker) {
        std::shared_ptr<Shared> shared = m_Shared;
        workerPool()->start([shared] { send(shared); });
    }
}

BitrateState::State BitrateClient::state() const
{
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    return m_Shared->state;
}

int BitrateClient::ownKbps() const
{
    return m_Shared->ownKbps;
}

int BitrateClient::targetKbps() const
{
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    return m_Shared->state.targetKbps > 0 ? m_Shared->state.targetKbps : m_Shared->ownKbps;
}

bool BitrateClient::isStateEvent(const SDL_Event& event)
{
    return event.type == eventType();
}
