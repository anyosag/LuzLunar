#include "adaptivebitrate.h"

#include <chrono>
#include <mutex>

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QReadLocker>
#include <QThread>
#include <QThreadPool>

#include "SDL_compat.h"
#include "apolloclient.h"
#include "backend/nvcomputer.h"
#include "bitraterules.h"
#include "streamstats.h"

struct AdaptiveBitrate::Shared
{
    Shared(int chosenKbps, bool hdr)
        : controller(chosenKbps, hdr)
    {
    }

    ApolloClient::Target target;
    QString hostName;
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();

    // The decode thread's alone
    BitrateRules::Controller controller;

    std::mutex mutex;
    bool alive = true;
    bool stopped = false;   // the host can't change the bitrate: no more requests this stream
    bool checked = false;   // serverinfo answered whether it can
    bool queued = false;    // a worker job will send wantKbps
    int wantKbps = 0;       // the newest bitrate to ask for; 0 for none
};

namespace
{
    // How often a request is tried when the PC doesn't answer, and how long each try waits
    const int k_Tries = 3;
    const int k_TimeoutMs = 3000;
    const int k_RetryDelayMs = 500;

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

    bool alive(const std::shared_ptr<AdaptiveBitrate::Shared>& shared)
    {
        std::lock_guard<std::mutex> lock(shared->mutex);
        return shared->alive;
    }

    void stop(const std::shared_ptr<AdaptiveBitrate::Shared>& shared)
    {
        std::lock_guard<std::mutex> lock(shared->mutex);
        shared->stopped = true;
        shared->queued = false;
        shared->wantKbps = 0;
    }

    // On the worker: whether the host changes bitrates while streaming, from serverinfo. Asked when
    // the stream starts, while the network is still fine, and again before a request if the host
    // didn't answer then. Without an answer the request goes anyway: a host that can't change
    // bitrates refuses it, which ends adaptive bitrate for the stream just the same.
    bool hostTakesChanges(const std::shared_ptr<AdaptiveBitrate::Shared>& shared)
    {
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive) {
                return false;
            }
            if (shared->checked) {
                return !shared->stopped;
            }
        }
        ApolloClient client(shared->target);
        ApolloClient::HostInfo info = client.hostInfo();
        if (!info.answered) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Adaptive bitrate: %s didn't answer serverinfo; asked again before the next change, which is sent either way",
                        qPrintable(shared->hostName));
            return true;
        }

        bool takes = info.bitrate == QLatin1String("1");
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            shared->checked = true;
        }
        if (!takes) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Adaptive bitrate: %s doesn't change a stream's bitrate (%s), so it stays at %d kbps",
                        qPrintable(shared->hostName),
                        info.permissions < 0 ? "not LuzLunar's Apollo" : (info.bitrate.isEmpty() ? "an older Apollo" : "off in Apollo"),
                        shared->controller.chosenKbps());
            stop(shared);
        }
        return takes;
    }

    // On the worker: sends the newest bitrate the controller wants until none waits
    void send(std::shared_ptr<AdaptiveBitrate::Shared> shared)
    {
        if (!hostTakesChanges(shared)) {
            std::lock_guard<std::mutex> lock(shared->mutex);
            shared->queued = false;
            return;
        }

        ApolloClient client(shared->target);

        for (;;) {
            int kbps;
            {
                std::lock_guard<std::mutex> lock(shared->mutex);
                if (!shared->alive || shared->stopped || shared->wantKbps == 0) {
                    shared->queued = false;
                    return;
                }
                kbps = shared->wantKbps;
                shared->wantKbps = 0;
            }

            QJsonObject request;
            request.insert(QStringLiteral("kbps"), kbps);
            QByteArray body = QJsonDocument(request).toJson(QJsonDocument::Compact);

            ApolloClient::RequestOptions options;
            options.contentType = "application/json";
            options.timeoutMs = k_TimeoutMs;
            options.maxResponseBytes = 64 * 1024;
            options.cancelled = [shared] { return !alive(shared); };

            ApolloClient::Response response;
            for (int attempt = 0; attempt < k_Tries; attempt++) {
                response = client.request(QStringLiteral("actions/bitrate"), QString(), &body, options);
                if (response.httpStatus != 0) {
                    break;
                }
                {
                    // A newer bitrate replaces this one; the stream ending ends it
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    if (!shared->alive || shared->wantKbps != 0) {
                        break;
                    }
                }
                QThread::msleep(k_RetryDelayMs);
            }

            QJsonObject reply = QJsonDocument::fromJson(response.body).object();
            switch (response.httpStatus) {
            case 200:
            case 202:
                {
                    int target = reply.value(QStringLiteral("target")).toInt(kbps);
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                                "[fork] Adaptive bitrate: %s streams at %d kbps (%d kbps for its encoder)",
                                qPrintable(shared->hostName), target, reply.value(QStringLiteral("encoder")).toInt());
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    if (shared->alive) {
                        ForkStreamStats::setBitrateCap(target < shared->controller.chosenKbps() ? target / 1000.0 : 0);
                    }
                    break;
                }
            case 0:
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "[fork] Adaptive bitrate: %s didn't answer the request for %d kbps: %s",
                            qPrintable(shared->hostName), kbps, qPrintable(response.networkError));
                break;
            default:
                // Not this stream's: no permission, not streaming, off, or an encoder that can't
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                            "[fork] Adaptive bitrate: %s refused %d kbps (HTTP %d, %s); the stream keeps its bitrate",
                            qPrintable(shared->hostName), kbps, response.httpStatus,
                            qPrintable(reply.value(QStringLiteral("error")).toString(reply.value(QStringLiteral("live")).toBool(true) ? QStringLiteral("refused") : QStringLiteral("not live"))));
                stop(shared);
                {
                    std::lock_guard<std::mutex> lock(shared->mutex);
                    if (shared->alive) {
                        ForkStreamStats::setBitrateCap(0);
                    }
                }
                return;
            }
        }
    }
}

AdaptiveBitrate::AdaptiveBitrate(NvComputer* computer, int chosenKbps, bool hdr)
    : m_Shared(std::make_shared<Shared>(chosenKbps, hdr))
{
    // Before a worker uses it
    workerPool();

    m_Shared->target = ApolloClient::targetFor(computer);
    {
        QReadLocker lock(&computer->lock);
        m_Shared->hostName = computer->name;
    }
    ForkStreamStats::setBitrateCap(0);

    // The last stream may have ended on a poor connection, which moonlight-common-c doesn't take back
    ForkStreamStats::resetConnectionStatus();

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[fork] Adaptive bitrate: between %d and %d kbps",
                m_Shared->controller.floorKbps(), chosenKbps);

    std::shared_ptr<Shared> shared = m_Shared;

    // Whether the host takes changes, asked now while the network is fine; requests queue behind it
    workerPool()->start([shared] { hostTakesChanges(shared); });

    ForkStreamStats::setBitrateListener([shared](const ForkStreamStats::Snapshot& stats) {
        // The decode thread, about once a second
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            if (!shared->alive || shared->stopped) {
                return;
            }
        }

        BitrateRules::Sample sample;
        sample.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - shared->start).count();
        sample.dropPercent = stats.dropPercent;
        sample.lostFrames = stats.droppedFrames;
        sample.rttMs = stats.rttMs;
        bool suggestLowerBitrate;
        sample.poor = ForkStreamStats::connectionPoor(&suggestLowerBitrate);

        int previous = shared->controller.currentKbps();
        uint32_t previousBase = shared->controller.baseRttMs();
        int kbps = shared->controller.tick(sample);
        if (previousBase > 0 && shared->controller.baseRttMs() > previousBase) {
            // Only a route that got slower raises it
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "[fork] Adaptive bitrate: the route got slower, base %u ms (was %u ms)",
                        shared->controller.baseRttMs(), previousBase);
        }
        if (kbps == 0) {
            return;
        }
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Adaptive bitrate: %d -> %d kbps (%.1f%% of frames lost, %u ms, base %u ms%s)",
                    previous, kbps, sample.dropPercent, sample.rttMs, shared->controller.baseRttMs(),
                    sample.poor ? ", poor connection" : "");

        bool startWorker = false;
        {
            std::lock_guard<std::mutex> lock(shared->mutex);
            shared->wantKbps = kbps;
            if (!shared->queued) {
                shared->queued = true;
                startWorker = true;
            }
        }
        if (startWorker) {
            workerPool()->start([shared] { send(shared); });
        }
    });
}

AdaptiveBitrate::~AdaptiveBitrate()
{
    // No listener runs after this returns
    ForkStreamStats::setBitrateListener(nullptr);

    // A request in flight gives up, and what it gets back is dropped
    std::lock_guard<std::mutex> lock(m_Shared->mutex);
    m_Shared->alive = false;
    ForkStreamStats::setBitrateCap(0);
}
