#include "forkpcprobe.h"
#include "forkpcprefs.h"
#include "forkhostpower.h"
#include "forkhostupdates.h"
#include "pccardrules.h"
#include "backend/computermanager.h"
#include "streaming/session.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QElapsedTimer>
#include <QGuiApplication>
#include <QReadLocker>
#include <QTcpSocket>
#include <QThreadPool>

ForkPcProbe::ForkPcProbe()
{
    m_Timer.setInterval(10 * 1000);
    connect(&m_Timer, &QTimer::timeout, this, &ForkPcProbe::probe);
}

ForkPcProbe* ForkPcProbe::get()
{
    static ForkPcProbe* s_Instance = new ForkPcProbe();
    return s_Instance;
}

void ForkPcProbe::attach(ComputerManager* manager)
{
    if (!m_Manager.isNull() || manager == nullptr) {
        return;
    }
    m_Manager = manager;
    connect(manager, &ComputerManager::computerStateChanged, this, &ForkPcProbe::handleComputerStateChanged);
    connect(qApp, &QGuiApplication::applicationStateChanged, this, &ForkPcProbe::handleApplicationState);
    connect(qApp, &QCoreApplication::aboutToQuit, this, &ForkPcProbe::writeLastSeen);

    for (NvComputer* computer : manager->getComputers()) {
        note(computer);
    }

    // A screenshot run has no real PCs and measures nothing
    if (!qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS")) {
        updateTimer();
        QTimer::singleShot(2000, this, &ForkPcProbe::probe);
    }
}

int ForkPcProbe::latencyMs(const QString& uuid) const
{
    const QVector<int> samples = m_Latency.value(uuid);
    return PcCardRules::median(std::vector<int>(samples.begin(), samples.end()));
}

void ForkPcProbe::handleComputerStateChanged(NvComputer* computer)
{
    note(computer);
}

// What a card remembers about a PC that is away, from each poll change
void ForkPcProbe::note(NvComputer* computer)
{
    QString uuid;
    bool online, knownPaired, activeIsLocal, activeIsRemote;
    {
        QReadLocker lock(&computer->lock);
        uuid = computer->uuid;
        online = computer->state == NvComputer::CS_ONLINE;
        knownPaired = computer->pairState == NvComputer::PS_PAIRED ||
                      (computer->pairState == NvComputer::PS_UNKNOWN && !computer->serverCert.isNull());
        activeIsLocal = !computer->activeAddress.isNull() && computer->activeAddress == computer->localAddress;
        activeIsRemote = !computer->activeAddress.isNull() && computer->activeAddress == computer->remoteAddress;
    }

    ForkPcPrefs* prefs = ForkPcPrefs::get();
    const bool known = m_WasOnline.contains(uuid);
    const bool was = m_WasOnline.value(uuid, false);
    const qint64 now = QDateTime::currentSecsSinceEpoch();

    if (online) {
        prefs->adopt(uuid);
        if (activeIsLocal) {
            m_Via.insert(uuid, QStringLiteral("home"));
        } else if (activeIsRemote) {
            m_Via.insert(uuid, QStringLiteral("internet"));
            // The only proof that its outside address works: it answered there
            if (now - prefs->remoteWorkedSecs(uuid) > 3600) {
                prefs->noteRemoteWorked(uuid, now);
            }
        }

        if (!was) {
            // Back: the wake worked, a request to go down is over (unless this very run saw it
            // just now), and Apollo is asked once for its version and wake setup
            prefs->clearWakeSent(uuid);
            m_Probing.remove(uuid);
            if (knownPaired) {
                ForkHostUpdates::get()->refresh(uuid);
                ForkHostPower::get()->refresh(uuid);
            }
        }

        // A request to go down is history once the PC is up again, was never seen going down (a
        // leftover from an earlier run), or still answers a minute after the request
        const qint64 powerAt = prefs->powerActionSecs(uuid);
        if (!prefs->powerAction(uuid).isEmpty() &&
                (!known || !was || now - powerAt >= PcCardRules::k_GoingDownSecs)) {
            prefs->clearPowerAction(uuid);
        }
    } else if (known && was) {
        // Online until now: it went away
        prefs->noteLastSeen(uuid, now, m_Via.value(uuid));
        m_Latency.remove(uuid);
    }

    m_WasOnline.insert(uuid, online);
}

void ForkPcProbe::writeLastSeen()
{
    if (m_Manager.isNull()) {
        return;
    }
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    for (NvComputer* computer : m_Manager->getComputers()) {
        QString uuid;
        bool online;
        {
            QReadLocker lock(&computer->lock);
            uuid = computer->uuid;
            online = computer->state == NvComputer::CS_ONLINE;
        }
        if (online) {
            ForkPcPrefs::get()->noteLastSeen(uuid, now, m_Via.value(uuid));
        }
    }
}

// Measuring only runs while LuzLunar is the active app
void ForkPcProbe::handleApplicationState()
{
    updateTimer();
}

void ForkPcProbe::updateTimer()
{
    if (qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS")) {
        return;
    }
    if (QGuiApplication::applicationState() == Qt::ApplicationActive) {
        if (!m_Timer.isActive()) {
            m_Timer.start();
        }
    } else {
        m_Timer.stop();
    }
}

void ForkPcProbe::addSample(const QString& uuid, int ms)
{
    QVector<int>& samples = m_Latency[uuid];
    samples.append(qMax(1, ms));
    while (samples.size() > 5) {
        samples.removeFirst();
    }
    emit latencyChanged(uuid);
}

// Times a TCP connect to each online PC's HTTP port (about one round trip), on a pool thread, so the
// UI thread being busy doesn't count. Not while a stream runs.
void ForkPcProbe::probe()
{
    if (m_Manager.isNull() || Session::get() != nullptr ||
            QGuiApplication::applicationState() != Qt::ApplicationActive) {
        return;
    }
    for (NvComputer* computer : m_Manager->getComputers()) {
        QString uuid, host;
        quint16 port = 0;
        {
            QReadLocker lock(&computer->lock);
            if (computer->state != NvComputer::CS_ONLINE || computer->activeAddress.isNull()) {
                continue;
            }
            uuid = computer->uuid;
            host = computer->activeAddress.address();
            port = computer->activeAddress.port();
        }
        if (m_Probing.contains(uuid)) {
            continue;
        }
        m_Probing.insert(uuid);

        QPointer<ForkPcProbe> self(this);
        QThreadPool::globalInstance()->start([self, uuid, host, port]() {
            int ms = -1;
            {
                QTcpSocket socket;
                QElapsedTimer timer;
                timer.start();
                socket.connectToHost(host, port);
                if (socket.waitForConnected(2000)) {
                    ms = int((timer.nsecsElapsed() + 500000) / 1000000);
                }
                socket.abort();
            }
            QMetaObject::invokeMethod(qApp, [self, uuid, ms]() {
                if (self.isNull()) {
                    return;
                }
                self->m_Probing.remove(uuid);
                if (ms >= 0) {
                    self->addSample(uuid, ms);
                }
            }, Qt::QueuedConnection);
        });
    }
}
