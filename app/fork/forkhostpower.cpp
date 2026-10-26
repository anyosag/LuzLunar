#include "forkhostpower.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QReadLocker>
#include <QThread>
#include <QThreadPool>

#include "apolloclient.h"
#include "backend/computermanager.h"
#include "backend/nvcomputer.h"

namespace
{
    const int k_RefreshIntervalMs = 30 * 60 * 1000;
    const int k_RequestTimeoutMs = 10 * 1000;
    const int k_QuitAppTimeoutMs = 60 * 1000;
    // Right after a stream: Apollo drops the stream's session a moment after it ends
    const int k_AfterStreamTries = 4;
    const unsigned long k_AfterStreamRetryMs = 750;

    ApolloClient::RequestOptions requestOptions()
    {
        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = k_RequestTimeoutMs;
        options.maxResponseBytes = 64 * 1024;
        return options;
    }
}

ForkHostPower* ForkHostPower::get()
{
    static ForkHostPower* s_Instance = new ForkHostPower(QCoreApplication::instance());
    return s_Instance;
}

ForkHostPower::ForkHostPower(QObject* parent)
    : QObject(parent),
      m_Pool(new QThreadPool(this))
{
    // One request at a time, in order: each GET hands out a new single-use token, so a refresh
    // running alongside Sleep could replace the token Sleep is about to post
    m_Pool->setMaxThreadCount(1);

    m_RefreshTimer.setInterval(k_RefreshIntervalMs);
    connect(&m_RefreshTimer, &QTimer::timeout, this, &ForkHostPower::refreshAll);
}

void ForkHostPower::setComputerManager(QObject* manager)
{
    auto* computerManager = qobject_cast<ComputerManager*>(manager);
    if (computerManager == nullptr || computerManager == m_Manager) {
        return;
    }
    m_Manager = computerManager;
    if (qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS")) {
        return;
    }
    // PCs come online a few seconds after launch
    QTimer::singleShot(10 * 1000, this, &ForkHostPower::refreshAll);
    m_RefreshTimer.start();
}

QVariantMap ForkHostPower::status(const QString& uuid) const
{
    QVariantMap map;
    auto it = m_Hosts.constFind(uuid);
    if (it == m_Hosts.constEnd()) {
        map.insert(QStringLiteral("known"), false);
        return map;
    }
    const Host& host = *it;
    map.insert(QStringLiteral("known"), host.known);
    map.insert(QStringLiteral("supported"), host.supported);
    map.insert(QStringLiteral("permitted"), host.permitted);
    map.insert(QStringLiteral("available"), host.available);
    map.insert(QStringLiteral("reason"), host.reason);
    map.insert(QStringLiteral("app"), host.app);
    map.insert(QStringLiteral("busy"), host.inFlight > 0);
    return map;
}

void ForkHostPower::refreshAll()
{
    if (m_Manager.isNull()) {
        return;
    }
    for (NvComputer* computer : m_Manager->getComputers()) {
        QString uuid;
        {
            QReadLocker lock(&computer->lock);
            if (!computer->isApolloServerSoftware || computer->pairState != NvComputer::PS_PAIRED ||
                computer->state != NvComputer::CS_ONLINE) {
                continue;
            }
            uuid = computer->uuid;
        }
        refresh(uuid);
    }
}

void ForkHostPower::refresh(const QString& uuid)
{
    if (m_Manager.isNull()) {
        return;
    }
    NvComputer* computer = nullptr;
    for (NvComputer* candidate : m_Manager->getComputers()) {
        QReadLocker lock(&candidate->lock);
        if (candidate->uuid == uuid && candidate->isApolloServerSoftware && candidate->pairState == NvComputer::PS_PAIRED &&
            candidate->state == NvComputer::CS_ONLINE) {
            computer = candidate;
            break;
        }
    }
    if (computer == nullptr) {
        return;
    }

    ApolloClient::Target target = ApolloClient::targetFor(computer);
    m_Hosts[uuid].inFlight++;
    m_Revision++;
    emit changed();

    QPointer<ForkHostPower> self(this);
    m_Pool->start([self, uuid, target]() {
        ApolloClient client(target);
        ApolloClient::Response response = client.request(QStringLiteral("actions/sleep"), QString(), nullptr, requestOptions());
        Answer answer;
        answer.httpStatus = response.httpStatus;
        answer.json = QJsonDocument::fromJson(response.body).object().toVariantMap();
        answer.networkError = response.networkError;

        if (self.isNull()) {
            return;
        }
        QMetaObject::invokeMethod(self.data(), [self, uuid, answer]() {
            if (!self.isNull()) {
                Host& host = self->m_Hosts[uuid];
                host.inFlight = qMax(0, host.inFlight - 1);
                self->onStatus(uuid, answer);
                self->m_Revision++;
                emit self->changed();
            }
        }, Qt::QueuedConnection);
    });
}

void ForkHostPower::onStatus(const QString& uuid, const Answer& answer)
{
    Host& host = m_Hosts[uuid];
    if (answer.httpStatus == 200) {
        host.known = true;
        host.supported = true;
        host.permitted = true;
        host.available = answer.json.value(QStringLiteral("available")).toBool();
        host.reason = answer.json.value(QStringLiteral("reason")).toString();
        host.app = answer.json.value(QStringLiteral("app")).toString();
    }
    else if (answer.httpStatus == 401) {
        // Apollo answers, but this Mac lacks the "Sleep PC" permission
        host.known = true;
        host.supported = true;
        host.permitted = false;
    }
    else if (answer.httpStatus == 404) {
        // An Apollo from before Sleep PC, with it turned off, or on a PC that can't sleep
        host.known = true;
        host.supported = false;
    }
}

void ForkHostPower::sleep(const QString& uuid, const QString& appToQuit, bool afterStream)
{
    if (m_Manager.isNull()) {
        return;
    }
    NvComputer* computer = nullptr;
    QString pcName;
    for (NvComputer* candidate : m_Manager->getComputers()) {
        QReadLocker lock(&candidate->lock);
        if (candidate->uuid == uuid) {
            computer = candidate;
            pcName = candidate->name;
            break;
        }
    }
    if (computer == nullptr) {
        return;
    }

    ApolloClient::Target target = ApolloClient::targetFor(computer);
    m_Hosts[uuid].inFlight++;
    m_Revision++;
    emit changed();

    QPointer<ForkHostPower> self(this);
    m_Pool->start([self, uuid, pcName, target, appToQuit, afterStream]() {
        ApolloClient client(target);

        // A fresh token, and what the PC is doing now, then the request. Right after a stream the PC
        // may still count it for a moment, in the answer or in the request's: ask again then.
        Answer status;
        bool ok = false;
        QString text;
        for (int attempt = 1; ; attempt++) {
            const bool canRetry = afterStream && attempt < k_AfterStreamTries;
            ApolloClient::Response response = client.request(QStringLiteral("actions/sleep"), QString(), nullptr, requestOptions());
            status.httpStatus = response.httpStatus;
            status.json = QJsonDocument::fromJson(response.body).object().toVariantMap();
            status.networkError = response.networkError;

            QString reason = status.json.value(QStringLiteral("reason")).toString();
            QString app = status.json.value(QStringLiteral("app")).toString();
            if (status.httpStatus == 200 && !status.json.value(QStringLiteral("available")).toBool() &&
                    reason == QStringLiteral("streaming") && canRetry) {
                QThread::msleep(k_AfterStreamRetryMs);
                continue;
            }

            if (status.httpStatus == 401) {
                text = tr("This Mac doesn't have the Sleep PC permission on %1").arg(pcName);
            }
            else if (status.httpStatus == 404) {
                text = tr("%1's Apollo can't sleep from LuzLunar").arg(pcName);
            }
            else if (status.httpStatus != 200) {
                text = tr("%1 didn't answer").arg(pcName);
            }
            else if (!status.json.value(QStringLiteral("available")).toBool()) {
                if (reason == QStringLiteral("streaming")) {
                    text = tr("%1 is streaming, so it stays awake").arg(pcName);
                }
                else if (reason == QStringLiteral("updating")) {
                    text = tr("%1 is installing an Apollo update").arg(pcName);
                }
                else if (reason == QStringLiteral("sleeping")) {
                    text = tr("%1 is already going to sleep").arg(pcName);
                }
                else {
                    text = tr("%1 can't sleep right now").arg(pcName);
                }
            }
            else if (reason == QStringLiteral("app_running") && (appToQuit.isEmpty() || app != appToQuit)) {
                // It started after the dialog asked, or it isn't the one the warning named: ask again
                text = tr("%1 is running on %2 now. Choose Sleep PC again to quit it and sleep.").arg(app, pcName);
            }
            else {
                QJsonObject request;
                request.insert(QStringLiteral("token"), status.json.value(QStringLiteral("token")).toString());
                // Only the app the user agreed to quit
                const bool quitApp = reason == QStringLiteral("app_running");
                request.insert(QStringLiteral("quitApp"), quitApp);
                QByteArray body = QJsonDocument(request).toJson(QJsonDocument::Compact);
                // Apollo quits the app before it answers, which takes up to the app's exit timeout
                ApolloClient::RequestOptions options = requestOptions();
                if (quitApp) {
                    options.timeoutMs = k_QuitAppTimeoutMs;
                }
                ApolloClient::Response slept = client.request(QStringLiteral("actions/sleep"), QString(), &body, options);
                QString error = QJsonDocument::fromJson(slept.body).object().value(QStringLiteral("error")).toString();
                if (slept.httpStatus == 202) {
                    ok = true;
                    text = quitApp ? tr("Quitting %1 and putting %2 to sleep").arg(app, pcName)
                                   : tr("Putting %1 to sleep").arg(pcName);
                }
                else if (error == QStringLiteral("streaming")) {
                    if (canRetry) {
                        // A new token comes with the next answer
                        QThread::msleep(k_AfterStreamRetryMs);
                        continue;
                    }
                    text = tr("%1 is streaming, so it stays awake").arg(pcName);
                }
                else if (error == QStringLiteral("app_running")) {
                    text = tr("An app started on %1. Choose Sleep PC again to quit it and sleep.").arg(pcName);
                }
                else {
                    text = tr("%1 didn't go to sleep. Try again.").arg(pcName);
                }
            }
            break;
        }

        if (self.isNull()) {
            return;
        }
        QMetaObject::invokeMethod(self.data(), [self, uuid, ok, text, status]() {
            if (!self.isNull()) {
                self->onSlept(uuid, ok, text, status);
            }
        }, Qt::QueuedConnection);
    });
}

void ForkHostPower::onSlept(const QString& uuid, bool ok, const QString& text, const Answer& status)
{
    Host& host = m_Hosts[uuid];
    host.inFlight = qMax(0, host.inFlight - 1);
    onStatus(uuid, status);
    if (ok) {
        host.available = false;
        host.reason = QStringLiteral("sleeping");
    }
    m_Revision++;
    emit changed();
    emit finished(uuid, ok, text);
}
