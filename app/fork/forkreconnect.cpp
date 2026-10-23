#include "forkreconnect.h"

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
}

void ForkReconnect::waitForHostToDrop(NvComputer* computer)
{
    bool apollo;
    {
        QReadLocker lock(&computer->lock);
        apollo = computer->isApolloServerSoftware;
    }
    if (!apollo) {
        // Only Apollo can say when it let a stream go
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: not Apollo; waiting %lld ms for the PC to let the old stream go",
                    static_cast<long long>(k_BlindWaitMs));
        QThread::msleep(static_cast<unsigned long>(k_BlindWaitMs));
        return;
    }

    ApolloClient client(ApolloClient::targetFor(computer));
    ApolloClient::RequestOptions options;
    options.timeoutMs = 1000;
    options.maxResponseBytes = 64 * 1024;

    QElapsedTimer waited;
    waited.start();
    for (;;) {
        ApolloClient::Response response = client.request(QStringLiteral("actions/bitrate"), QString(), nullptr, options);
        if (response.httpStatus == 403) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: the PC let the old stream go after %lld ms",
                        static_cast<long long>(waited.elapsed()));
            return;
        }
        if (response.httpStatus != 0 && response.httpStatus != 200 && response.httpStatus != 409) {
            // An older Apollo, or one with it off: it can't say, so a second
            qint64 left = k_BlindWaitMs - waited.elapsed();
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: the PC can't say when it let the old stream go (HTTP %d); waiting %lld ms",
                        response.httpStatus, static_cast<long long>(qMax<qint64>(left, 0)));
            if (left > 0) {
                QThread::msleep(static_cast<unsigned long>(left));
            }
            return;
        }
        if (waited.elapsed() >= k_MaxWaitMs) {
            // The launch goes anyway; Apollo keeps its virtual display's mode if it still streams
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Reconnect: the PC still has the old stream after %lld ms; launching anyway",
                        static_cast<long long>(waited.elapsed()));
            return;
        }
        QThread::msleep(k_PollMs);
    }
}
