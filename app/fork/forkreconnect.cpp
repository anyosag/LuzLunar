#include "forkreconnect.h"

#include <algorithm>

#include <QElapsedTimer>
#include <QReadLocker>
#include <QThread>

#include "SDL_compat.h"
#include "apolloclient.h"
#include "backend/nvcomputer.h"

namespace
{
    const qint64 k_MaxWaitMs = 3000;
    const qint64 k_BlindWaitMs = 1000;  // for a PC that can't say
    const int k_PollMs = 200;

    bool isApollo(NvComputer* computer)
    {
        QReadLocker lock(&computer->lock);
        return computer->isApolloServerSoftware;
    }

    void blindWait(qint64 waitedMs, const char* why)
    {
        qint64 left = qMax<qint64>(k_BlindWaitMs - waitedMs, 0);
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: the PC can't say when it let the old stream go (%s); waiting %lld ms",
                    why, static_cast<long long>(left));
        if (left > 0) {
            QThread::msleep(static_cast<unsigned long>(left));
        }
    }
}

void ForkReconnect::waitForHostToDrop(NvComputer* computer)
{
    if (!isApollo(computer)) {
        // Only Apollo can say when it let a stream go
        blindWait(0, "not Apollo");
        return;
    }

    ApolloClient client(ApolloClient::targetFor(computer));
    ApolloClient::RequestOptions options;
    options.maxResponseBytes = 64 * 1024;

    QElapsedTimer waited;
    waited.start();
    int unanswered = 0;
    for (;;) {
        // Within what's left of the wait, so it holds the launch back 3 s at most
        options.timeoutMs = static_cast<int>(std::clamp<qint64>(k_MaxWaitMs - waited.elapsed(), 100, 1000));
        ApolloClient::Response response = client.request(QStringLiteral("actions/bitrate"), QString(), nullptr, options);
        if (response.httpStatus == 403) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: the PC let the old stream go after %lld ms",
                        static_cast<long long>(waited.elapsed()));
            return;
        }
        if (response.httpStatus == 0) {
            // No answer twice running: not a moment's hiccup while the stream goes (an address or
            // certificate missing, a PC asleep), so this can't say either
            if (++unanswered >= 2) {
                blindWait(waited.elapsed(), qPrintable(response.networkError));
                return;
            }
        }
        else if (response.httpStatus != 200 && response.httpStatus != 409) {
            // An older Apollo, or one with it off
            blindWait(waited.elapsed(), qPrintable(QStringLiteral("HTTP %1").arg(response.httpStatus)));
            return;
        }
        else {
            unanswered = 0;
        }
        if (waited.elapsed() + k_PollMs >= k_MaxWaitMs) {
            // The launch goes anyway; Apollo keeps its virtual display's mode if it still streams
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: the PC still has the old stream after %lld ms; launching anyway",
                        static_cast<long long>(waited.elapsed()));
            return;
        }
        QThread::msleep(k_PollMs);
    }
}

const char* ForkReconnect::startVerb(NvComputer* computer)
{
    return isApollo(computer) ? "launch" : "resume";
}
