#include "forkhostupdates.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QReadLocker>
#include <QThreadPool>

#include "apolloclient.h"
#include "backend/computermanager.h"
#include "backend/nvcomputer.h"
#include "hostupdaterules.h"

namespace
{
    const int k_RefreshIntervalMs = 30 * 60 * 1000;
    const int k_UpdatingPollMs = 5 * 1000;
    // Apollo's install takes a minute or two; give up waiting for it after this
    const qint64 k_UpdatingTimeoutSecs = 8 * 60;
}

ForkHostUpdates* ForkHostUpdates::get()
{
    static ForkHostUpdates* s_Instance = new ForkHostUpdates(QCoreApplication::instance());
    return s_Instance;
}

ForkHostUpdates::ForkHostUpdates(QObject* parent)
    : QObject(parent),
      m_Pool(new QThreadPool(this))
{
    m_Pool->setMaxThreadCount(2);

    m_RefreshTimer.setInterval(k_RefreshIntervalMs);
    connect(&m_RefreshTimer, &QTimer::timeout, this, &ForkHostUpdates::refreshAll);
    m_UpdatingTimer.setInterval(k_UpdatingPollMs);
    connect(&m_UpdatingTimer, &QTimer::timeout, this, &ForkHostUpdates::pollUpdating);
}

void ForkHostUpdates::setComputerManager(QObject* manager)
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
    QTimer::singleShot(10 * 1000, this, &ForkHostUpdates::refreshAll);
    m_RefreshTimer.start();
}

QVariantMap ForkHostUpdates::status(const QString& uuid) const
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
    map.insert(QStringLiteral("busy"), host.inFlight > 0);
    map.insert(QStringLiteral("updating"), host.updating);
    map.insert(QStringLiteral("error"), host.error);

    const QJsonObject& s = host.status;
    QJsonObject latest = s.value(QStringLiteral("latest")).toObject();
    map.insert(QStringLiteral("version"), s.value(QStringLiteral("version")).toString());
    map.insert(QStringLiteral("masterBuild"), s.value(QStringLiteral("channel")).toString() == QStringLiteral("master"));
    map.insert(QStringLiteral("state"), s.value(QStringLiteral("state")).toString());
    map.insert(QStringLiteral("message"), s.value(QStringLiteral("message")).toString());
    map.insert(QStringLiteral("automatic"), s.value(QStringLiteral("automatic")).toBool());
    map.insert(QStringLiteral("update"), s.value(QStringLiteral("update")).toBool());
    map.insert(QStringLiteral("latestVersion"), latest.value(QStringLiteral("version")).toString());
    map.insert(QStringLiteral("latestNotes"), latest.value(QStringLiteral("notes")).toString());
    map.insert(QStringLiteral("lastResult"), s.value(QStringLiteral("last_result")).toObject().value(QStringLiteral("text")).toString());
    return map;
}

void ForkHostUpdates::refresh(const QString& uuid)
{
    send(uuid, QByteArray());
}

void ForkHostUpdates::refreshAll()
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

void ForkHostUpdates::check(const QString& uuid)
{
    send(uuid, QByteArrayLiteral(R"({"action":"check"})"));
}

void ForkHostUpdates::install(const QString& uuid)
{
    Host& host = m_Hosts[uuid];
    host.updating = true;
    host.updateStarted = QDateTime::currentDateTimeUtc();
    host.versionBefore = host.status.value(QStringLiteral("version")).toString();
    host.error.clear();
    m_Revision++;
    emit changed();
    m_UpdatingTimer.start();

    send(uuid, QByteArrayLiteral(R"({"action":"install"})"));
}

void ForkHostUpdates::setAutomatic(const QString& uuid, bool automatic)
{
    send(uuid, automatic ? QByteArrayLiteral(R"({"automatic":true})") : QByteArrayLiteral(R"({"automatic":false})"));
}

void ForkHostUpdates::send(const QString& uuid, const QByteArray& body)
{
    if (m_Manager.isNull()) {
        return;
    }
    NvComputer* computer = nullptr;
    for (NvComputer* candidate : m_Manager->getComputers()) {
        QReadLocker lock(&candidate->lock);
        if (candidate->uuid == uuid) {
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

    QPointer<ForkHostUpdates> self(this);
    m_Pool->start([self, uuid, target, body]() {
        ApolloClient client(target);
        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = 10 * 1000;
        options.maxResponseBytes = 64 * 1024;
        ApolloClient::Response response = client.request(QStringLiteral("actions/update"), QString(), body.isNull() ? nullptr : &body, options);

        if (self.isNull()) {
            return;
        }
        QMetaObject::invokeMethod(self.data(), [self, uuid, response]() {
            if (!self.isNull()) {
                self->onResponse(uuid, response.httpStatus, response.body, response.networkError);
            }
        }, Qt::QueuedConnection);
    });
}

void ForkHostUpdates::onResponse(const QString& uuid, int httpStatus, const QByteArray& body, const QString& networkError)
{
    Host& host = m_Hosts[uuid];
    host.inFlight = qMax(0, host.inFlight - 1);

    if (httpStatus == 200) {
        QJsonDocument document = QJsonDocument::fromJson(body);
        if (document.isObject()) {
            host.known = true;
            host.permitted = true;
            host.status = document.object();
            host.supported = host.status.value(QStringLiteral("supported")).toBool();
            host.error.clear();
        }
    }
    else if (httpStatus == 401) {
        // Apollo answers, but this Mac lacks the "Update Apollo" permission
        host.known = true;
        host.supported = true;
        host.permitted = false;
    }
    else if (httpStatus == 404) {
        // An Apollo from before over-the-air updates
        host.known = true;
        host.supported = false;
    }
    else if (httpStatus == 400) {
        QJsonDocument document = QJsonDocument::fromJson(body);
        host.error = document.object().value(QStringLiteral("error")).toString();
        if (host.updating) {
            host.updating = false;
            emit finished(uuid, tr("Apollo didn't update: %1").arg(host.error));
        }
    }
    else if (!host.updating) {
        // While it updates, Apollo is expected to stop answering for a while
        host.error = networkError.isEmpty() ? tr("The PC answered %1").arg(httpStatus) : networkError;
    }

    if (host.updating && httpStatus == 200) {
        QString version = host.status.value(QStringLiteral("version")).toString();
        QString message = host.status.value(QStringLiteral("message")).toString();
        QJsonObject lastResult = host.status.value(QStringLiteral("last_result")).toObject();

        HostUpdateRules::Answer answer;
        answer.versionBefore = host.versionBefore.toStdString();
        answer.version = version.toStdString();
        answer.state = host.status.value(QStringLiteral("state")).toString().toStdString();
        answer.hasLastResult = !lastResult.isEmpty();
        answer.lastResultTime = static_cast<qint64>(lastResult.value(QStringLiteral("time")).toDouble());
        answer.startedSecs = host.updateStarted.toSecsSinceEpoch();
        answer.nowSecs = QDateTime::currentDateTimeUtc().toSecsSinceEpoch();

        // Every way it ends gets a toast, so a click on Update Apollo never just comes back
        switch (HostUpdateRules::outcome(answer)) {
        case HostUpdateRules::Outcome::Updated:
            emit finished(uuid, tr("Apollo updated to %1").arg(version));
            break;
        case HostUpdateRules::Outcome::WentBack:
            // Back on the same version: the helper put the previous build back, or gave up
            emit finished(uuid, lastResult.value(QStringLiteral("text")).toString());
            break;
        case HostUpdateRules::Outcome::Failed:
            host.error = message;
            emit finished(uuid, tr("Apollo didn't update: %1").arg(message));
            break;
        case HostUpdateRules::Outcome::UpToDate:
            host.error = message;
            emit finished(uuid, tr("Apollo is up to date"));
            break;
        case HostUpdateRules::Outcome::StuckChecking:
            // An Apollo from before the updater put its state back after a check ignores Install
            host.error = tr("Apollo is stuck checking for updates. Restart Apollo on the PC (or the PC), then choose Update Apollo again within 30 minutes.");
            emit finished(uuid, host.error);
            break;
        case HostUpdateRules::Outcome::Waiting:
            // It installs once nobody streams, however long that takes
            host.updateStarted = QDateTime::currentDateTimeUtc();
            break;
        case HostUpdateRules::Outcome::Continue:
            break;
        }
        if (HostUpdateRules::ends(HostUpdateRules::outcome(answer))) {
            host.updating = false;
        }
    }

    m_Revision++;
    emit changed();
}

void ForkHostUpdates::pollUpdating()
{
    bool any = false;
    QDateTime now = QDateTime::currentDateTimeUtc();
    for (auto it = m_Hosts.begin(); it != m_Hosts.end(); ++it) {
        Host& host = it.value();
        if (!host.updating) {
            continue;
        }
        if (host.updateStarted.secsTo(now) > k_UpdatingTimeoutSecs) {
            host.updating = false;
            host.error = tr("Apollo didn't come back after updating. Check the PC.");
            m_Revision++;
            emit changed();
            emit finished(it.key(), host.error);
            continue;
        }
        any = true;
        if (host.inFlight == 0) {
            refresh(it.key());
        }
    }
    if (!any) {
        m_UpdatingTimer.stop();
    }
}
