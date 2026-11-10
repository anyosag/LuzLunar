#include "forkhostpower.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QElapsedTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QReadLocker>
#include <QThread>
#include <QThreadPool>

#include "apolloclient.h"
#include "forkpcprefs.h"
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
    // After Fix on PC or Undo Changes: the PC's network adapter restarts, so it's asked again
    const unsigned long k_WakePollMs = 3000;
    const int k_WakePollTimeoutMs = 3000;
    const qint64 k_WakeChangeBudgetMs = 60 * 1000;

    ApolloClient::RequestOptions requestOptions()
    {
        ApolloClient::RequestOptions options;
        options.contentType = "application/json";
        options.timeoutMs = k_RequestTimeoutMs;
        options.maxResponseBytes = 64 * 1024;
        return options;
    }

    std::string text(const QString& s)
    {
        return s.toStdString();
    }

    QString text(const std::string& s)
    {
        return QString::fromStdString(s);
    }

    QVariantMap jsonOf(const ApolloClient::Response& response)
    {
        return QJsonDocument::fromJson(response.body).object().toVariantMap();
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
    map.insert(QStringLiteral("canShutDown"), host.canShutDown);
    return map;
}

ForkHostPower::Names ForkHostPower::names(const QString& uuid) const
{
    Names out;
    if (m_Manager.isNull()) {
        return out;
    }
    for (NvComputer* computer : m_Manager->getComputers()) {
        QReadLocker lock(&computer->lock);
        if (computer->uuid == uuid) {
            out.name = computer->name;
            out.ip = computer->localAddress.isNull() ? QString() : computer->localAddress.address();
            out.mac = computer->macAddress.isEmpty() ? QString() : QString::fromLatin1(computer->macAddress.toHex(':'));
            break;
        }
    }
    return out;
}

QVariantMap ForkHostPower::wakeStatus(const QString& uuid) const
{
    QVariantMap map;
    auto it = m_Hosts.constFind(uuid);
    const Names pc = names(uuid);
    const std::string pcName = text(pc.name);
    map.insert(QStringLiteral("bios"), text(WakeSetupRules::biosText(pcName)));
    map.insert(QStringLiteral("away"), text(WakeSetupRules::awayText(pcName, text(pc.ip), text(pc.mac))));
    if (it == m_Hosts.constEnd()) {
        map.insert(QStringLiteral("known"), false);
        map.insert(QStringLiteral("busy"), false);
        map.insert(QStringLiteral("summary"), text(WakeSetupRules::summary({}, pcName)));
        return map;
    }
    const Host& host = *it;
    const WakeSetupRules::Status& wake = host.wake;
    map.insert(QStringLiteral("known"), host.wakeKnown);
    map.insert(QStringLiteral("supported"), host.wakeSupported);
    map.insert(QStringLiteral("permitted"), host.wakePermitted);
    map.insert(QStringLiteral("busy"), host.wakeInFlight > 0);
    map.insert(QStringLiteral("fromOff"), text(wake.fromOff));
    map.insert(QStringLiteral("summary"), text(WakeSetupRules::summary(wake, pcName)));
    map.insert(QStringLiteral("fixConfirmation"), text(WakeSetupRules::fixConfirmation(wake, pcName)));
    map.insert(QStringLiteral("shutDownWarning"), text(WakeSetupRules::shutDownWarning(wake, pcName)));
    map.insert(QStringLiteral("canFix"), wake.canFix);
    map.insert(QStringLiteral("canUndo"), wake.canUndo);
    map.insert(QStringLiteral("applying"), wake.applying);
    map.insert(QStringLiteral("reason"), text(wake.reason));

    QVariantList rows;
    for (const WakeSetupRules::Row& row : WakeSetupRules::rows(wake, pcName)) {
        QVariantMap r;
        r.insert(QStringLiteral("id"), text(row.id));
        r.insert(QStringLiteral("kind"), text(row.kind));
        r.insert(QStringLiteral("title"), text(row.title));
        r.insert(QStringLiteral("detail"), text(row.detail));
        rows.append(r);
    }
    map.insert(QStringLiteral("rows"), rows);
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
        answer.json = jsonOf(response);
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

    requestWake(uuid, false);
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
        // An Apollo from before Shut Down PC doesn't say it, and would sleep instead
        host.canShutDown = answer.json.value(QStringLiteral("canShutDown")).toBool();
    }
    else if (answer.httpStatus == 401) {
        // Apollo answers, but this Mac lacks the "Sleep and Shut Down PC" permission
        host.known = true;
        host.supported = true;
        host.permitted = false;
    }
    else if (answer.httpStatus == 404) {
        // An Apollo from before Sleep PC, with it turned off, or on a PC that can't sleep
        host.known = true;
        host.supported = false;
        host.canShutDown = false;
    }
}

void ForkHostPower::sleep(const QString& uuid, const QString& appToQuit, bool afterStream)
{
    requestPower(uuid, appToQuit, afterStream, false);
}

void ForkHostPower::shutDown(const QString& uuid, const QString& appToQuit)
{
    requestPower(uuid, appToQuit, false, true);
}

void ForkHostPower::requestPower(const QString& uuid, const QString& appToQuit, bool afterStream, bool off)
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
    m_Hosts[uuid].lastOff = off; // [fork] for onSlept(): the card tells Asleep from Off
    m_Revision++;
    emit changed();

    QPointer<ForkHostPower> self(this);
    m_Pool->start([self, uuid, pcName, target, appToQuit, afterStream, off]() {
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
            status.json = jsonOf(response);
            status.networkError = response.networkError;

            QString reason = status.json.value(QStringLiteral("reason")).toString();
            QString app = status.json.value(QStringLiteral("app")).toString();
            if (status.httpStatus == 200 && !status.json.value(QStringLiteral("available")).toBool() &&
                    reason == QStringLiteral("streaming") && canRetry) {
                QThread::msleep(k_AfterStreamRetryMs);
                continue;
            }

            if (status.httpStatus == 401) {
                text = tr("This Mac doesn't have the Sleep and Shut Down PC permission on %1").arg(pcName);
            }
            else if (status.httpStatus == 404) {
                text = off ? tr("%1's Apollo can't shut down from LuzLunar").arg(pcName)
                           : tr("%1's Apollo can't sleep from LuzLunar").arg(pcName);
            }
            else if (status.httpStatus != 200) {
                text = tr("%1 didn't answer").arg(pcName);
            }
            else if (off && !status.json.value(QStringLiteral("canShutDown")).toBool()) {
                // An older Apollo ignores "state" and would sleep instead
                text = tr("%1's Apollo is too old to shut down from LuzLunar. Update Apollo first.").arg(pcName);
            }
            else if (!status.json.value(QStringLiteral("available")).toBool()) {
                if (reason == QStringLiteral("streaming")) {
                    text = off ? tr("%1 is streaming, so it stays on").arg(pcName)
                               : tr("%1 is streaming, so it stays awake").arg(pcName);
                }
                else if (reason == QStringLiteral("updating")) {
                    text = tr("%1 is installing an Apollo update").arg(pcName);
                }
                else if (reason == QStringLiteral("sleeping")) {
                    text = tr("%1 is already going to sleep or shutting down").arg(pcName);
                }
                else {
                    text = off ? tr("%1 can't shut down right now").arg(pcName)
                               : tr("%1 can't sleep right now").arg(pcName);
                }
            }
            else if (reason == QStringLiteral("app_running") && (appToQuit.isEmpty() || app != appToQuit)) {
                // It started after the dialog asked, or it isn't the one the warning named: ask again
                text = off ? tr("%1 is running on %2 now. Choose Shut Down PC again to quit it and shut down.").arg(app, pcName)
                           : tr("%1 is running on %2 now. Choose Sleep PC again to quit it and sleep.").arg(app, pcName);
            }
            else {
                QJsonObject request;
                request.insert(QStringLiteral("token"), status.json.value(QStringLiteral("token")).toString());
                // Only the app the user agreed to quit
                const bool quitApp = reason == QStringLiteral("app_running");
                request.insert(QStringLiteral("quitApp"), quitApp);
                if (off) {
                    request.insert(QStringLiteral("state"), QStringLiteral("off"));
                }
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
                    if (off) {
                        text = quitApp ? tr("Quitting %1 and shutting down %2").arg(app, pcName)
                                       : tr("Shutting down %1").arg(pcName);
                    }
                    else {
                        text = quitApp ? tr("Quitting %1 and putting %2 to sleep").arg(app, pcName)
                                       : tr("Putting %1 to sleep").arg(pcName);
                    }
                }
                else if (error == QStringLiteral("streaming")) {
                    if (canRetry) {
                        // A new token comes with the next answer
                        QThread::msleep(k_AfterStreamRetryMs);
                        continue;
                    }
                    text = off ? tr("%1 is streaming, so it stays on").arg(pcName)
                               : tr("%1 is streaming, so it stays awake").arg(pcName);
                }
                else if (error == QStringLiteral("app_running")) {
                    text = off ? tr("An app started on %1. Choose Shut Down PC again to quit it and shut down.").arg(pcName)
                               : tr("An app started on %1. Choose Sleep PC again to quit it and sleep.").arg(pcName);
                }
                else {
                    text = off ? tr("%1 didn't shut down. Try again.").arg(pcName)
                               : tr("%1 didn't go to sleep. Try again.").arg(pcName);
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
        // [fork] What this Mac asked, for the PC's card while it's away (Asleep, or Off)
        ForkPcPrefs::get()->notePowerAction(uuid, host.lastOff ? QStringLiteral("off") : QStringLiteral("sleep"));
    }
    m_Revision++;
    emit changed();
    emit finished(uuid, ok, text);
}

WakeSetupRules::Status ForkHostPower::parseWake(const QVariantMap& json)
{
    WakeSetupRules::Status status;
    status.known = true;
    status.fromOff = text(json.value(QStringLiteral("fromOff")).toString());
    const QVariantMap adapter = json.value(QStringLiteral("adapter")).toMap();
    status.adapterName = text(adapter.value(QStringLiteral("name")).toString());
    status.adapterDescription = text(adapter.value(QStringLiteral("description")).toString());
    status.link = text(adapter.value(QStringLiteral("link")).toString());
    for (const QVariant& item : json.value(QStringLiteral("checks")).toList()) {
        const QVariantMap c = item.toMap();
        WakeSetupRules::Check check;
        check.id = text(c.value(QStringLiteral("id")).toString());
        check.state = text(c.value(QStringLiteral("state")).toString());
        check.reason = text(c.value(QStringLiteral("reason")).toString());
        check.keyword = text(c.value(QStringLiteral("keyword")).toString());
        check.setting = text(c.value(QStringLiteral("setting")).toString());
        check.current = text(c.value(QStringLiteral("current")).toString());
        check.target = text(c.value(QStringLiteral("target")).toString());
        status.checks.push_back(check);
    }
    status.lastPowerOn = text(json.value(QStringLiteral("lastPowerOn")).toString());
    bool uptimeOk = false;
    qlonglong uptime = json.value(QStringLiteral("uptimeSeconds")).toLongLong(&uptimeOk);
    status.uptimeSeconds = uptimeOk ? uptime : -1;
    status.undoable = json.value(QStringLiteral("undoable")).toBool();
    status.applying = json.value(QStringLiteral("applying")).toBool();
    status.canFix = json.value(QStringLiteral("canFix")).toBool();
    status.canUndo = json.value(QStringLiteral("canUndo")).toBool();
    status.reason = text(json.value(QStringLiteral("reason")).toString());
    if (json.contains(QStringLiteral("lastResult"))) {
        const QVariantMap r = json.value(QStringLiteral("lastResult")).toMap();
        status.lastResult.present = true;
        status.lastResult.action = text(r.value(QStringLiteral("action")).toString());
        status.lastResult.ok = r.value(QStringLiteral("ok")).toBool();
        status.lastResult.restartNeeded = r.value(QStringLiteral("restartNeeded")).toBool();
        status.lastResult.changed = r.value(QStringLiteral("changed")).toInt();
        for (const QVariant& keyword : r.value(QStringLiteral("failed")).toList()) {
            status.lastResult.failed.push_back(text(keyword.toString()));
        }
        status.lastResult.error = text(r.value(QStringLiteral("error")).toString());
    }
    return status;
}

void ForkHostPower::onWakeStatus(const QString& uuid, const Answer& answer)
{
    Host& host = m_Hosts[uuid];
    if (answer.httpStatus == 200) {
        host.wakeKnown = true;
        host.wakeSupported = true;
        host.wakePermitted = true;
        host.wake = parseWake(answer.json);
    }
    else if (answer.httpStatus == 401) {
        host.wakeKnown = true;
        host.wakeSupported = true;
        host.wakePermitted = false;
    }
    else if (answer.httpStatus == 404) {
        // An Apollo from before Set Up Wake from Off, or with it turned off
        host.wakeKnown = true;
        host.wakeSupported = false;
        host.wake = WakeSetupRules::Status {};
    }
}

void ForkHostPower::refreshWake(const QString& uuid)
{
    requestWake(uuid, false);
}

void ForkHostPower::requestWake(const QString& uuid, bool afterWake)
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
        if (afterWake) {
            // Not an Apollo this Mac is paired with: nothing to ask
            m_Hosts[uuid].wakeSentAtMs = 0;
            emit poweredOn(uuid, text(WakeSetupRules::poweredOnText({}, -1, text(names(uuid).name))));
        }
        return;
    }

    ApolloClient::Target target = ApolloClient::targetFor(computer);
    m_Hosts[uuid].wakeInFlight++;
    m_Revision++;
    emit changed();

    QPointer<ForkHostPower> self(this);
    m_Pool->start([self, uuid, target, afterWake]() {
        ApolloClient client(target);
        ApolloClient::Response response = client.request(QStringLiteral("actions/wake"), QString(), nullptr, requestOptions());
        Answer answer;
        answer.httpStatus = response.httpStatus;
        answer.json = jsonOf(response);
        answer.networkError = response.networkError;

        if (self.isNull()) {
            return;
        }
        QMetaObject::invokeMethod(self.data(), [self, uuid, answer, afterWake]() {
            if (self.isNull()) {
                return;
            }
            Host& host = self->m_Hosts[uuid];
            host.wakeInFlight = qMax(0, host.wakeInFlight - 1);
            self->onWakeStatus(uuid, answer);
            if (afterWake) {
                const qint64 sent = host.wakeSentAtMs;
                host.wakeSentAtMs = 0;
                const long long since = sent > 0 ? (QDateTime::currentMSecsSinceEpoch() - sent) / 1000 : -1;
                WakeSetupRules::Status status = answer.httpStatus == 200 ? host.wake : WakeSetupRules::Status {};
                emit self->poweredOn(uuid, text(WakeSetupRules::poweredOnText(status, since, text(self->names(uuid).name))));
            }
            self->m_Revision++;
            emit self->changed();
        }, Qt::QueuedConnection);
    });
}

void ForkHostPower::noteWakeSent(const QString& uuid)
{
    m_Hosts[uuid].wakeSentAtMs = QDateTime::currentMSecsSinceEpoch();
}

void ForkHostPower::noteOnline(const QString& uuid)
{
    auto it = m_Hosts.find(uuid);
    if (it == m_Hosts.end() || it->wakeSentAtMs == 0) {
        emit poweredOn(uuid, text(WakeSetupRules::poweredOnText({}, -1, text(names(uuid).name))));
        return;
    }
    requestWake(uuid, true);
}

void ForkHostPower::fixWake(const QString& uuid)
{
    changeWake(uuid, false);
}

void ForkHostPower::undoWake(const QString& uuid)
{
    changeWake(uuid, true);
}

void ForkHostPower::changeWake(const QString& uuid, bool undo)
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
    m_Hosts[uuid].wakeInFlight++;
    m_Revision++;
    emit changed();

    QPointer<ForkHostPower> self(this);
    m_Pool->start([self, uuid, pcName, target, undo]() {
        ApolloClient client(target);
        const std::string name = text(pcName);
        Answer last;
        bool ok = false;
        QString message;

        // A fresh token, then the request
        ApolloClient::Response response = client.request(QStringLiteral("actions/wake"), QString(), nullptr, requestOptions());
        last.httpStatus = response.httpStatus;
        last.json = jsonOf(response);
        last.networkError = response.networkError;
        const QString token = last.json.value(QStringLiteral("token")).toString();
        const bool can = last.json.value(undo ? QStringLiteral("canUndo") : QStringLiteral("canFix")).toBool();
        const QString reason = last.json.value(QStringLiteral("reason")).toString();

        if (last.httpStatus != 200) {
            message = text(WakeSetupRules::refusalText(last.httpStatus, std::string(), name));
        }
        else if (!can || token.isEmpty()) {
            const QString why = reason.isEmpty() || reason == QStringLiteral("none") ? QStringLiteral("nothing") : reason;
            message = text(WakeSetupRules::refusalText(409, text(why), name));
        }
        else {
            QJsonObject request;
            request.insert(QStringLiteral("token"), token);
            request.insert(QStringLiteral("action"), undo ? QStringLiteral("undo") : QStringLiteral("fix"));
            QByteArray body = QJsonDocument(request).toJson(QJsonDocument::Compact);
            ApolloClient::Response posted = client.request(QStringLiteral("actions/wake"), QString(), &body, requestOptions());
            const QString error = jsonOf(posted).value(QStringLiteral("error")).toString();
            if (posted.httpStatus != 202) {
                message = text(WakeSetupRules::refusalText(posted.httpStatus, text(error), name));
            }
            else {
                // The PC changes its settings a moment later and restarts its network adapter: ask
                // again until it says it's done, or a minute passes
                QElapsedTimer elapsed;
                elapsed.start();
                bool done = false;
                ApolloClient::RequestOptions poll = requestOptions();
                poll.timeoutMs = k_WakePollTimeoutMs;
                while (!done && elapsed.elapsed() < k_WakeChangeBudgetMs) {
                    QThread::msleep(k_WakePollMs);
                    ApolloClient::Response answer = client.request(QStringLiteral("actions/wake"), QString(), nullptr, poll);
                    if (answer.httpStatus == 200) {
                        QVariantMap json = jsonOf(answer);
                        if (!json.value(QStringLiteral("applying")).toBool()) {
                            last.httpStatus = 200;
                            last.json = json;
                            last.networkError.clear();
                            done = true;
                        }
                    }
                }
                if (!done) {
                    message = text(WakeSetupRules::noAnswerAfterChange(name));
                }
                else {
                    WakeSetupRules::Status status = parseWake(last.json);
                    ok = status.lastResult.present && status.lastResult.ok;
                    message = text(WakeSetupRules::resultText(status.lastResult, name));
                }
            }
        }

        if (self.isNull()) {
            return;
        }
        QMetaObject::invokeMethod(self.data(), [self, uuid, ok, message, last]() {
            if (self.isNull()) {
                return;
            }
            Host& host = self->m_Hosts[uuid];
            host.wakeInFlight = qMax(0, host.wakeInFlight - 1);
            if (last.httpStatus == 200 || last.httpStatus == 401 || last.httpStatus == 404) {
                self->onWakeStatus(uuid, last);
            }
            self->m_Revision++;
            emit self->changed();
            emit self->wakeFinished(uuid, ok, message);
        }, Qt::QueuedConnection);
    });
}
