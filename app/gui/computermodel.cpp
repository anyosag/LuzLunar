#include "computermodel.h"
#include "fork/forkhostpower.h" // [fork]
#include "fork/forkhostupdates.h" // [fork]
#include "fork/forkmultidisplay.h" // [fork]
#include "fork/forkpcprefs.h" // [fork]
#include "fork/pccardrules.h" // [fork]
#include "fork/streamprofiles.h" // [fork]

#include <QCoreApplication> // [fork]
#include <QDateTime> // [fork]
#include <QElapsedTimer> // [fork]
#include <QGuiApplication> // [fork]
#include <QReadLocker> // [fork]
#include <QTcpSocket> // [fork]
#include <QThreadPool>
#include <QTimer> // [fork]

ComputerModel::ComputerModel(QObject* object)
    : QAbstractListModel(object) {}

void ComputerModel::initialize(ComputerManager* computerManager)
{
    m_ComputerManager = computerManager;
    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &ComputerModel::handleComputerStateChanged);
    connect(m_ComputerManager, &ComputerManager::pairingCompleted,
            this, &ComputerModel::handlePairingCompleted);

    m_Computers = m_ComputerManager->getComputers();

    // [fork] The card's roles also depend on what this Mac remembers about each PC and on what
    // Apollo told ForkHostPower and ForkHostUpdates, so those changes refresh the rows
    connect(ForkPcPrefs::get(), &ForkPcPrefs::changed, this, &ComputerModel::forkHandlePrefsChanged);
    connect(ForkHostPower::get(), &ForkHostPower::changed, this, &ComputerModel::forkHandleHostInfoChanged);
    connect(ForkHostUpdates::get(), &ForkHostUpdates::changed, this, &ComputerModel::forkHandleHostInfoChanged);
    connect(&m_ForkBoxArt, &BoxArtManager::boxArtLoadComplete, this, &ComputerModel::forkHandleBoxArtLoaded);
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, &ComputerModel::forkWriteLastSeen);

    for (NvComputer* computer : m_Computers) {
        forkNoteTransitions(computer);
    }

    // The latency chip: how fast each online PC answers, measured every 10 s while the app is in front.
    // A screenshot run has no real PCs and measures nothing.
    if (!qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS")) {
        QTimer* probe = new QTimer(this);
        probe->setInterval(10 * 1000);
        connect(probe, &QTimer::timeout, this, &ComputerModel::forkProbeLatency);
        probe->start();
        QTimer::singleShot(2000, this, &ComputerModel::forkProbeLatency);
    }
}

QVariant ComputerModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid()) {
        return QVariant();
    }

    Q_ASSERT(index.row() < m_Computers.count());

    NvComputer* computer = m_Computers[index.row()];

    // [fork] The card's roles take their own snapshot of the PC
    if (role >= StateRole) {
        return forkData(computer, role);
    }

    QReadLocker lock(&computer->lock);

    switch (role) {
    case NameRole:
        return computer->name;
    case OnlineRole:
        return computer->state == NvComputer::CS_ONLINE;
    case PairedRole:
        return computer->pairState == NvComputer::PS_PAIRED;
    case BusyRole:
        return computer->currentGameId != 0;
    case WakeableRole:
        return !computer->macAddress.isEmpty();
    case StatusUnknownRole:
        return computer->state == NvComputer::CS_UNKNOWN;
    case ServerSupportedRole:
        return computer->isSupportedServerVersion;
    case HostSoftwareRole:
        // [fork] The host software's name for the redesign's cards ("Apollo · paired"). Only a
        // paired host's verified serverinfo tells Apollo and Sunshine apart, so it's empty otherwise.
        // (a PC that was paired from this Mac counts while it's away: its certificate is pinned)
        if (computer->pairState != NvComputer::PS_PAIRED &&
                !(computer->pairState == NvComputer::PS_UNKNOWN && !computer->serverCert.isNull())) {
            return QString();
        }
        return computer->isApolloServerSoftware ? QStringLiteral("Apollo")
             : computer->isNvidiaServerSoftware ? QStringLiteral("GeForce Experience")
             : QStringLiteral("Sunshine");
    case UuidRole: // [fork]
        return computer->uuid;
    case DetailsRole: {
        QString state, pairState;

        switch (computer->state) {
        case NvComputer::CS_ONLINE:
            state = tr("Online");
            break;
        case NvComputer::CS_OFFLINE:
            state = tr("Offline");
            break;
        default:
            state = tr("Unknown");
            break;
        }

        switch (computer->pairState) {
        case NvComputer::PS_PAIRED:
            pairState = tr("Paired");
            break;
        case NvComputer::PS_NOT_PAIRED:
            pairState = tr("Unpaired");
            break;
        default:
            pairState = tr("Unknown");
            break;
        }

        return tr("Name: %1").arg(computer->name) + '\n' +
               tr("Status: %1").arg(state) + '\n' +
               tr("Active Address: %1").arg(computer->activeAddress.toString()) + '\n' +
               tr("UUID: %1").arg(computer->uuid) + '\n' +
               tr("Local Address: %1").arg(computer->localAddress.toString()) + '\n' +
               tr("Remote Address: %1").arg(computer->remoteAddress.toString()) + '\n' +
               tr("IPv6 Address: %1").arg(computer->ipv6Address.toString()) + '\n' +
               tr("Manual Address: %1").arg(computer->manualAddress.toString()) + '\n' +
               tr("MAC Address: %1").arg(computer->macAddress.isEmpty() ? tr("Unknown") : QString(computer->macAddress.toHex(':'))) + '\n' +
               tr("Pair State: %1").arg(pairState) + '\n' +
               tr("Running Game ID: %1").arg(computer->state == NvComputer::CS_ONLINE ? QString::number(computer->currentGameId) : tr("Unknown")) + '\n' +
               tr("HTTPS Port: %1").arg(computer->state == NvComputer::CS_ONLINE ? QString::number(computer->activeHttpsPort) : tr("Unknown"));
    }
    default:
        return QVariant();
    }
}

int ComputerModel::rowCount(const QModelIndex& parent) const
{
    // We should not return a count for valid index values,
    // only the parent (which will not have a "valid" index).
    if (parent.isValid()) {
        return 0;
    }

    return m_Computers.count();
}

QHash<int, QByteArray> ComputerModel::roleNames() const
{
    QHash<int, QByteArray> names;

    names[NameRole] = "name";
    names[OnlineRole] = "online";
    names[PairedRole] = "paired";
    names[BusyRole] = "busy";
    names[WakeableRole] = "wakeable";
    names[StatusUnknownRole] = "statusUnknown";
    names[ServerSupportedRole] = "serverSupported";
    names[DetailsRole] = "details";
    names[HostSoftwareRole] = "hostSoftware"; // [fork]
    names[UuidRole] = "uuid"; // [fork]

    // [fork] The redesigned PC card, spec/contract-data.md
    names[StateRole] = "state";
    names[KnownPairedRole] = "knownPaired";
    names[ColorKeyRole] = "colorKey";
    names[KeepFirstRole] = "keepFirst";
    names[WakeOnPickRole] = "wakeOnPick";
    names[ApolloVersionRole] = "apolloVersion";
    names[NetworkRole] = "network";
    names[LatencyMsRole] = "latencyMs";
    names[AddressRole] = "address";
    names[AddressNoteRole] = "addressNote";
    names[HasRemoteAddressRole] = "hasRemoteAddress";
    names[RemoteWorkedRole] = "remoteWorked";
    names[FoundAutomaticallyRole] = "foundAutomatically";
    names[LastSeenSecsRole] = "lastSeenSecs";
    names[LastSeenViaRole] = "lastSeenVia";
    names[RunningAppIdRole] = "runningAppId";
    names[RunningAppRole] = "runningApp";
    names[StreamStartedHereRole] = "streamStartedHere";
    names[StreamWidthRole] = "streamWidth";
    names[StreamHeightRole] = "streamHeight";
    names[StreamFpsRole] = "streamFps";
    names[StreamHdrRole] = "streamHdr";
    names[StreamCodecRole] = "streamCodec";
    names[HostUpdateRole] = "hostUpdate";
    names[ApolloUpToDateRole] = "apolloUpToDate";
    names[ApolloUpdatingRole] = "apolloUpdating";
    names[WakeFromOffRole] = "wakeFromOff";
    names[WakingRole] = "waking";
    names[WakeTimedOutRole] = "wakeTimedOut";
    names[PowerActionRole] = "powerAction";
    names[CanSleepRole] = "canSleep";
    names[CanShutDownRole] = "canShutDown";
    names[CanSetUpWakeRole] = "canSetUpWake";
    names[PreviewAppsRole] = "previewApps";
    names[AppCountRole] = "appCount";
    names[HiddenAppCountRole] = "hiddenAppCount";
    names[AppsCachedRole] = "appsCached";
    names[MainAppIdRole] = "mainAppId";
    names[MainAppRole] = "mainApp";

    return names;
}

Session* ComputerModel::createSessionForCurrentGame(int computerIndex)
{
    Q_ASSERT(computerIndex < m_Computers.count());

    NvComputer* computer = m_Computers[computerIndex];

    // We must currently be streaming a game to use this function
    Q_ASSERT(computer->currentGameId != 0);

    for (NvApp& app : computer->appList) {
        if (app.id == computer->currentGameId) {
            return StreamProfiles::createSession(computer, app); // [fork]
        }
    }

    // We have a current running app but it's not in our app list
    Q_ASSERT(false);
    return nullptr;
}

void ComputerModel::deleteComputer(int computerIndex)
{
    Q_ASSERT(computerIndex < m_Computers.count());

    const QString forkUuid = m_Computers[computerIndex]->uuid; // [fork]

    beginRemoveRows(QModelIndex(), computerIndex, computerIndex);

    // m_Computer[computerIndex] will be deleted by this call
    m_ComputerManager->deleteHost(m_Computers[computerIndex]);

    // [fork] What this Mac kept about the PC goes with it (its color, which PC is first, ...)
    ForkPcPrefs::get()->forget(forkUuid);
    m_ForkWasOnline.remove(forkUuid);
    m_ForkVia.remove(forkUuid);
    m_ForkLatency.remove(forkUuid);

    // Remove the now invalid item
    m_Computers.removeAt(computerIndex);

    endRemoveRows();
}

class DeferredWakeHostTask : public QRunnable
{
public:
    DeferredWakeHostTask(NvComputer* computer)
        : m_Computer(computer) {}

    void run()
    {
        m_Computer->wake();
    }

private:
    NvComputer* m_Computer;
};

void ComputerModel::wakeComputer(int computerIndex)
{
    Q_ASSERT(computerIndex < m_Computers.count());

    DeferredWakeHostTask* wakeTask = new DeferredWakeHostTask(m_Computers[computerIndex]);
    QThreadPool::globalInstance()->start(wakeTask);

    // [fork] The card says "Waking…" until the PC answers; if it doesn't in time, it says it can't be reached
    ForkPcPrefs::get()->noteWakeSent(m_Computers[computerIndex]->uuid);
    QTimer::singleShot((PcCardRules::k_WakeWaitSecs + 1) * 1000, this, &ComputerModel::forkRefreshAll);
}

void ComputerModel::renameComputer(int computerIndex, QString name)
{
    Q_ASSERT(computerIndex < m_Computers.count());

    m_ComputerManager->renameHost(m_Computers[computerIndex], name);
}

QString ComputerModel::generatePinString()
{
    return m_ComputerManager->generatePinString();
}

class DeferredTestConnectionTask : public QObject, public QRunnable
{
    Q_OBJECT
public:
    void run()
    {
        unsigned int portTestResult = LiTestClientConnectivity("qt.conntest.moonlight-stream.org", 443, ML_PORT_FLAG_ALL);
        if (portTestResult == ML_TEST_RESULT_INCONCLUSIVE) {
            emit connectionTestCompleted(-1, QString());
        }
        else {
            char blockedPorts[512];
            LiStringifyPortFlags(portTestResult, "\n", blockedPorts, sizeof(blockedPorts));
            emit connectionTestCompleted(portTestResult, QString(blockedPorts));
        }
    }

signals:
    void connectionTestCompleted(int result, QString blockedPorts);
};

void ComputerModel::testConnectionForComputer(int)
{
    DeferredTestConnectionTask* testConnectionTask = new DeferredTestConnectionTask();
    QObject::connect(testConnectionTask, &DeferredTestConnectionTask::connectionTestCompleted,
                     this, &ComputerModel::connectionTestCompleted);
    QThreadPool::globalInstance()->start(testConnectionTask);
}

void ComputerModel::pairComputer(int computerIndex, QString pin)
{
    Q_ASSERT(computerIndex < m_Computers.count());

    m_ComputerManager->pairHost(m_Computers[computerIndex], pin);
}

void ComputerModel::handlePairingCompleted(NvComputer*, QString error)
{
    emit pairingCompleted(error.isEmpty() ? QVariant() : error);
}

void ComputerModel::handleComputerStateChanged(NvComputer* computer)
{
    forkNoteTransitions(computer); // [fork]

    QVector<NvComputer*> newComputerList = m_ComputerManager->getComputers();

    // Reset the model if the structural layout of the list has changed
    if (m_Computers != newComputerList) {
        beginResetModel();
        m_Computers = newComputerList;
        endResetModel();
    }
    else {
        // Let the view know that this specific computer changed
        int index = m_Computers.indexOf(computer);
        emit dataChanged(createIndex(index, 0), createIndex(index, 0));
    }
}

#include "computermodel.moc"
