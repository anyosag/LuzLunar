#include "computermodel.h"
#include "fork/forkhostpower.h" // [fork]
#include "fork/forkhostupdates.h" // [fork]
#include "fork/forkmultidisplay.h" // [fork]
#include "fork/forkpcprefs.h" // [fork]
#include "fork/forkpcprobe.h" // [fork]
#include "fork/clienthardware.h" // [fork]
#include "fork/pccardrules.h" // [fork]
#include "fork/streamprofiles.h" // [fork]

#include <QCoreApplication> // [fork]
#include <memory> // [fork]
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
    // Apollo told ForkHostPower and ForkHostUpdates, so those changes refresh the rows. What is
    // remembered about a PC coming and going, and the latency, is ForkPcProbe's (one for the process).
    connect(ForkPcPrefs::get(), &ForkPcPrefs::changed, this, &ComputerModel::forkHandlePrefsChanged);
    connect(ForkPcPrefs::get(), &ForkPcPrefs::orderChanged, this, &ComputerModel::forkHandleOrderChanged);
    connect(ForkHostPower::get(), &ForkHostPower::changed, this, &ComputerModel::forkHandleHostInfoChanged);
    connect(ForkHostUpdates::get(), &ForkHostUpdates::changed, this, &ComputerModel::forkHandleHostInfoChanged);
    connect(&m_ForkBoxArt, &BoxArtManager::boxArtLoadComplete, this, &ComputerModel::forkHandleBoxArtLoaded);
    connect(ForkPcProbe::get(), &ForkPcProbe::latencyChanged, this, &ComputerModel::forkHandleLatency);
    // The multi-display app comes and goes with the Mac's displays: preview, counts and main app change
    connect(ClientHardware::get(), &ClientHardware::changed, this, &ComputerModel::forkRefreshAll);

    ForkPcProbe::get()->attach(m_ComputerManager);
    for (NvComputer* computer : m_Computers) {
        QReadLocker lock(&computer->lock);
        m_ForkWasOnline.insert(computer->uuid, computer->state == NvComputer::CS_ONLINE);
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

    // Remove the item first (upstream did it after): deleteHost() tells the other models at once,
    // and this one must already be without the PC when it hears
    NvComputer* forkDeleted = m_Computers.takeAt(computerIndex);

    endRemoveRows();

    // forkDeleted will be deleted by this call
    m_ComputerManager->deleteHost(forkDeleted);

    // [fork] What this Mac kept about the PC goes with it (its color, which PC is first, ...). After
    // the row is gone: forgetting tells the other models, which must not re-read a list in the middle of this.
    m_ForkWasOnline.remove(forkUuid);
    ForkPcPrefs::get()->forget(forkUuid);
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
    if (computerIndex < 0 || computerIndex >= m_Computers.count()) { // [fork]
        return;
    }

    DeferredWakeHostTask* wakeTask = new DeferredWakeHostTask(m_Computers[computerIndex]);
    QThreadPool::globalInstance()->start(wakeTask);

    // [fork] The card says "Waking…" until the PC answers or 180 s pass. A PC that answers has
    // nothing to wake, so it gets no mark.
    NvComputer* computer = m_Computers[computerIndex];
    bool online;
    {
        QReadLocker lock(&computer->lock);
        online = computer->state == NvComputer::CS_ONLINE;
    }
    if (!online) {
        ForkPcPrefs::get()->noteWakeSent(computer->uuid);
    }
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
    // [fork] A PC that came back may have art that failed before
    {
        bool online;
        {
            QReadLocker lock(&computer->lock);
            online = computer->state == NvComputer::CS_ONLINE;
        }
        if (online && !m_ForkWasOnline.value(computer->uuid, false)) {
            m_ForkArtRequested.clear();
        }
        m_ForkWasOnline.insert(computer->uuid, online);
    }

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
        if (index >= 0) { // [fork] -1 for a PC that was just deleted
            emit dataChanged(createIndex(index, 0), createIndex(index, 0));
        }
    }
}

// [fork] ---- The redesigned PC card ------------------------------------------------------------

// Everything a card needs from the NvComputer, copied under its lock. Roles that ask other objects
// (ForkMultiDisplay, ForkHostPower) work from the copy, because NvComputer's lock isn't recursive.
struct ComputerModel::Facts
{
    QString uuid;
    QString name;
    bool online = false;
    bool unknown = false;
    bool paired = false;
    bool knownPaired = false;
    bool wakeable = false;
    bool hasActive = false;
    bool activeIsLocal = false;
    bool activeIsRemote = false;
    bool foundAutomatically = true;
    int currentGameId = 0;     // 0 unless online
    int groupAppId = 0;
    QString activeAddress;
    QString localAddress;
    QString manualAddress;
    QString remoteAddress;
    QString ipv6Address;
    QVector<NvApp> apps;
};

ComputerModel::Facts ComputerModel::forkFacts(NvComputer* computer) const
{
    Facts f;
    QReadLocker lock(&computer->lock);
    f.uuid = computer->uuid;
    f.name = computer->name;
    f.online = computer->state == NvComputer::CS_ONLINE;
    f.unknown = computer->state == NvComputer::CS_UNKNOWN;
    f.paired = computer->pairState == NvComputer::PS_PAIRED;
    // A PC not asked yet since LuzLunar started has no pair state, but a pinned certificate means
    // it was paired from this Mac
    f.knownPaired = f.paired || (computer->pairState == NvComputer::PS_UNKNOWN && !computer->serverCert.isNull());
    f.wakeable = !computer->macAddress.isEmpty();
    f.hasActive = !computer->activeAddress.isNull();
    f.activeIsLocal = f.hasActive && computer->activeAddress == computer->localAddress;
    f.activeIsRemote = f.hasActive && computer->activeAddress == computer->remoteAddress;
    f.foundAutomatically = computer->manualAddress.isNull();
    // The running app is the PC's while it answers; the number goes stale once it's away
    f.currentGameId = f.online ? computer->currentGameId : 0;
    f.groupAppId = computer->forkDisplayGroupAppId;
    auto addr = [](const NvAddress& a) { return a.isNull() ? QString() : a.address(); };
    f.activeAddress = addr(computer->activeAddress);
    f.localAddress = addr(computer->localAddress);
    f.manualAddress = addr(computer->manualAddress);
    f.remoteAddress = addr(computer->remoteAddress);
    f.ipv6Address = addr(computer->ipv6Address);
    f.apps = computer->appList;
    return f;
}

static QVariantMap appMap(const NvApp& app, int runningId, const QUrl& art)
{
    QVariantMap map;
    map.insert(QStringLiteral("appid"), app.id);
    map.insert(QStringLiteral("name"), app.name);
    map.insert(QStringLiteral("boxart"), art.toString());
    map.insert(QStringLiteral("running"), runningId != 0 && app.id == runningId);
    return map;
}

// The apps the PC's card and All apps list: the multi-display app only when this Mac and the PC can
// stream several displays, or while it runs (so it can be quit); same test as AppModel
QVector<NvApp> ComputerModel::forkVisibleApps(const Facts& f, NvComputer* computer) const
{
    QVector<NvApp> visible;
    const bool groupOk = f.groupAppId == 0 || ForkMultiDisplay::canStreamGroup(computer);
    for (const NvApp& app : f.apps) {
        if (f.groupAppId != 0 && app.id == f.groupAppId && app.id != f.currentGameId && !groupOk) {
            continue;
        }
        visible.append(app);
    }
    return visible;
}

QVariantList ComputerModel::forkPreviewApps(const Facts& f, const QVector<NvApp>& visible, NvComputer* computer) const
{
    std::vector<PcCardRules::App> rules;
    for (const NvApp& app : visible) {
        PcCardRules::App a;
        a.id = app.id;
        a.name = app.name.toStdString();
        a.hidden = app.hidden;
        rules.push_back(a);
    }
    std::vector<std::string> recent;
    for (const QString& name : ForkPcPrefs::get()->recentApps(f.uuid)) {
        recent.push_back(name.toStdString());
    }

    QVariantList list;
    for (int i : PcCardRules::previewOrder(rules, f.currentGameId, recent)) {
        NvApp app = visible[i];
        QUrl art = m_ForkBoxArt.cachedBoxArt(computer, app.id);   // never fetches while the PC is away
        if (f.online) {
            const QPair<NvComputer*, int> request(computer, app.id);
            if (art.scheme() == QLatin1String("qrc") && !m_ForkArtRequested.contains(request)) {
                m_ForkArtRequested.insert(request);
                art = m_ForkBoxArt.loadBoxArt(computer, app);    // starts a fetch; dataChanged when it lands
            }
        }
        list.append(appMap(app, f.currentGameId, art));
    }
    return list;
}

static qint64 nowSecs()
{
    return QDateTime::currentSecsSinceEpoch();
}

QVariant ComputerModel::forkData(NvComputer* computer, int role) const
{
    ForkPcPrefs* prefs = ForkPcPrefs::get();
    const Facts f = forkFacts(computer);
    const QString uuid = f.uuid;

    // What Apollo told ForkHostUpdates and ForkHostPower this session
    const QVariantMap updates = ForkHostUpdates::get()->status(uuid);
    const QVariantMap sleepInfo = ForkHostPower::get()->status(uuid);
    const QVariantMap wakeInfo = ForkHostPower::get()->wakeStatus(uuid);

    const bool updatesAnswered = updates.value(QStringLiteral("known")).toBool() &&
                                 updates.value(QStringLiteral("supported")).toBool() &&
                                 updates.value(QStringLiteral("permitted")).toBool();
    const QString liveVersion = updatesAnswered ? updates.value(QStringLiteral("version")).toString() : QString();
    const QString version = !liveVersion.isEmpty() ? liveVersion : prefs->apolloVersion(uuid);

    QString wakeFromOff = prefs->wakeFromOff(uuid);
    if (wakeInfo.value(QStringLiteral("known")).toBool() && wakeInfo.value(QStringLiteral("supported")).toBool()) {
        wakeFromOff = wakeInfo.value(QStringLiteral("fromOff")).toString();
    }
    if (wakeFromOff == QLatin1String("unsupported")) {
        wakeFromOff.clear();
    }

    const qint64 now = nowSecs();
    const qint64 wakeSent = prefs->wakeSentSecs(uuid);
    const bool waking = !f.online && wakeSent > 0 && now - wakeSent < PcCardRules::k_WakeWaitSecs;
    const bool wakeTimedOut = !f.online && prefs->isWakeTimedOut(uuid);

    const QString via = f.online ? (f.activeIsLocal ? QStringLiteral("home") : f.activeIsRemote ? QStringLiteral("internet") : prefs->lastSeenVia(uuid))
                                 : prefs->lastSeenVia(uuid);
    const QString network = QString::fromStdString(
        PcCardRules::network(f.online, f.hasActive, f.activeIsLocal, f.activeIsRemote));
    const bool remoteWorked = prefs->remoteWorkedSecs(uuid) > 0;

    const QVariantMap stream = prefs->lastStream(uuid);
    const bool startedHere = f.currentGameId != 0 && stream.value(QStringLiteral("appId")).toInt() == f.currentGameId;

    const qint64 powerAt = prefs->powerActionSecs(uuid);

    switch (role) {
    case StateRole: {
        PcCardRules::Inputs in;
        in.online = f.online;
        in.unknown = f.unknown;
        in.paired = f.paired;
        in.knownPaired = f.knownPaired;
        in.running = f.currentGameId != 0;
        in.wakeable = f.wakeable;
        in.waking = waking;
        in.powerAction = prefs->powerAction(uuid).toStdString();
        in.powerActionAgeSecs = powerAt > 0 ? now - powerAt : -1;
        in.wakeFromOff = wakeFromOff.toStdString();
        return QString::fromStdString(PcCardRules::state(in));
    }
    case KnownPairedRole:
        return f.knownPaired;
    case ColorKeyRole:
        // A PC that isn't paired is gray; a paired one has its own (and gets one the first time)
        return f.knownPaired ? prefs->colorKey(uuid) : QStringLiteral("gray");
    case KeepFirstRole:
        return prefs->keepFirst(uuid);
    case WakeOnPickRole:
        return prefs->wakeOnPick(uuid);
    case ApolloVersionRole:
        return version;
    case NetworkRole:
        return network;
    case LatencyMsRole:
        return f.online ? ForkPcProbe::get()->latencyMs(uuid) : -1;
    case AddressRole: {
        if (f.online && !f.activeAddress.isEmpty()) {
            return f.activeAddress;
        }
        if (via == QLatin1String("internet") && !f.remoteAddress.isEmpty()) {
            return f.remoteAddress;
        }
        for (const QString& a : { f.localAddress, f.manualAddress, f.remoteAddress, f.ipv6Address }) {
            if (!a.isEmpty()) {
                return a;
            }
        }
        return QString();
    }
    case AddressNoteRole:
        return QString::fromStdString(PcCardRules::addressNote(f.online, f.knownPaired, network.toStdString(),
                                                               remoteWorked, f.foundAutomatically));
    case HasRemoteAddressRole:
        return !f.remoteAddress.isEmpty();
    case RemoteWorkedRole:
        return remoteWorked;
    case FoundAutomaticallyRole:
        return f.foundAutomatically;
    case LastSeenSecsRole:
        return prefs->lastSeenSecs(uuid);
    case LastSeenViaRole:
        return prefs->lastSeenVia(uuid);
    case RunningAppIdRole:
        return f.currentGameId;
    case RunningAppRole:
        for (const NvApp& app : f.apps) {
            if (f.currentGameId != 0 && app.id == f.currentGameId) {
                return app.name;
            }
        }
        return QString();
    case StreamStartedHereRole:
        return startedHere;
    case StreamWidthRole:
        return startedHere ? stream.value(QStringLiteral("width")).toInt() : 0;
    case StreamHeightRole:
        return startedHere ? stream.value(QStringLiteral("height")).toInt() : 0;
    case StreamFpsRole:
        return startedHere ? stream.value(QStringLiteral("fps")).toInt() : 0;
    case StreamHdrRole:
        return startedHere && stream.value(QStringLiteral("hdr")).toBool();
    case StreamCodecRole:
        return startedHere ? stream.value(QStringLiteral("codec")).toString() : QString();
    case HostUpdateRole:
        return f.online && updates.value(QStringLiteral("update")).toBool() && updatesAnswered &&
               !updates.value(QStringLiteral("updating")).toBool();
    case ApolloUpToDateRole:
        if (f.online) {
            return updatesAnswered && !updates.value(QStringLiteral("update")).toBool() && !liveVersion.isEmpty();
        }
        return !prefs->apolloVersion(uuid).isEmpty() && !prefs->apolloUpdate(uuid);
    case ApolloUpdatingRole:
        return updates.value(QStringLiteral("updating")).toBool();
    case WakeFromOffRole:
        return wakeFromOff;
    case WakingRole:
        return waking;
    case WakeTimedOutRole:
        return wakeTimedOut;
    case PowerActionRole:
        return prefs->powerAction(uuid);
    case CanSleepRole:
        return f.online && f.paired && sleepInfo.value(QStringLiteral("supported")).toBool() &&
               sleepInfo.value(QStringLiteral("permitted")).toBool();
    case CanShutDownRole:
        return f.online && f.paired && sleepInfo.value(QStringLiteral("supported")).toBool() &&
               sleepInfo.value(QStringLiteral("permitted")).toBool() && sleepInfo.value(QStringLiteral("canShutDown")).toBool();
    case CanSetUpWakeRole:
        return f.online ? wakeInfo.value(QStringLiteral("supported")).toBool() : !wakeFromOff.isEmpty();
    case PreviewAppsRole:
        return forkPreviewApps(f, forkVisibleApps(f, computer), computer);
    case AppCountRole:
    case HiddenAppCountRole: {
        int count = 0, hidden = 0;
        for (const NvApp& app : forkVisibleApps(f, computer)) {
            count++;
            if (app.hidden) {
                hidden++;
            }
        }
        return role == AppCountRole ? count : hidden;
    }
    case AppsCachedRole:
        return !f.online && !f.apps.isEmpty();
    case MainAppIdRole:
    case MainAppRole: {
        const QVector<NvApp> visible = forkVisibleApps(f, computer);
        std::vector<PcCardRules::App> rules;
        std::vector<bool> direct;
        for (const NvApp& app : visible) {
            PcCardRules::App a;
            a.id = app.id;
            a.name = app.name.toStdString();
            a.hidden = app.hidden;
            rules.push_back(a);
            direct.push_back(app.directLaunch);
        }
        std::vector<std::string> recent;
        for (const QString& name : prefs->recentApps(uuid)) {
            recent.push_back(name.toStdString());
        }
        const int i = PcCardRules::mainApp(rules, direct, f.currentGameId, recent);
        if (role == MainAppIdRole) {
            return i >= 0 ? visible[i].id : 0;
        }
        return i >= 0 ? visible[i].name : QString();
    }
    default:
        return QVariant();
    }
}

int ComputerModel::forkIndexOf(const QString& uuid) const
{
    for (int i = 0; i < m_Computers.count(); i++) {
        if (m_Computers[i]->uuid == uuid) {
            return i;
        }
    }
    return -1;
}

Session* ComputerModel::createSessionForApp(int computerIndex, int appId)
{
    if (computerIndex < 0 || computerIndex >= m_Computers.count()) {
        return nullptr;
    }

    NvComputer* computer = m_Computers[computerIndex];
    NvApp found;
    {
        QReadLocker lock(&computer->lock);
        for (const NvApp& app : computer->appList) {
            if (app.id == appId) {
                found = app;
                break;
            }
        }
    }
    if (found.id == 0) {
        return nullptr;
    }
    return StreamProfiles::createSession(computer, found);
}

void ComputerModel::quitRunningApp(int computerIndex)
{
    if (computerIndex < 0 || computerIndex >= m_Computers.count()) {
        return;
    }
    m_ComputerManager->quitRunningApp(m_Computers[computerIndex]);
}

void ComputerModel::forkRefreshAll()
{
    if (!m_Computers.isEmpty()) {
        emit dataChanged(createIndex(0, 0), createIndex(m_Computers.count() - 1, 0));
    }
}

// The PC kept first changed the order: reset when the list differs
void ComputerModel::forkRecheckOrder()
{
    QVector<NvComputer*> newList = m_ComputerManager->getComputers();
    if (m_Computers != newList) {
        beginResetModel();
        m_Computers = newList;
        endResetModel();
    }
}

void ComputerModel::forkHandleOrderChanged()
{
    forkRecheckOrder();
}

void ComputerModel::forkHandlePrefsChanged(const QString& uuid)
{
    const int row = uuid.isEmpty() ? -1 : forkIndexOf(uuid);
    if (row >= 0) {
        emit dataChanged(createIndex(row, 0), createIndex(row, 0));
    } else {
        forkRefreshAll();
    }

    // The card shows the result of Sleep PC or Shut Down PC for a minute, then goes by what the poll says
    if (!uuid.isEmpty() && !ForkPcPrefs::get()->powerAction(uuid).isEmpty()) {
        QTimer::singleShot((PcCardRules::k_GoingDownSecs + 1) * 1000, this, &ComputerModel::forkRefreshAll);
    }
}

void ComputerModel::forkHandleLatency(const QString& uuid)
{
    const int row = forkIndexOf(uuid);
    if (row >= 0) {
        emit dataChanged(createIndex(row, 0), createIndex(row, 0), QVector<int>() << LatencyMsRole);
    }
}

// Apollo answered ForkHostPower or ForkHostUpdates: remember what a card needs while the PC is away,
// then refresh the rows
void ComputerModel::forkHandleHostInfoChanged()
{
    for (NvComputer* computer : m_Computers) {
        QString uuid;
        {
            QReadLocker lock(&computer->lock);
            uuid = computer->uuid;
        }
        const QVariantMap updates = ForkHostUpdates::get()->status(uuid);
        if (updates.value(QStringLiteral("known")).toBool() && updates.value(QStringLiteral("supported")).toBool() &&
                updates.value(QStringLiteral("permitted")).toBool() &&
                !updates.value(QStringLiteral("version")).toString().isEmpty()) {
            ForkPcPrefs::get()->noteApollo(uuid, updates.value(QStringLiteral("version")).toString(),
                                           updates.value(QStringLiteral("update")).toBool());
        }
        const QVariantMap wake = ForkHostPower::get()->wakeStatus(uuid);
        if (wake.value(QStringLiteral("known")).toBool()) {
            ForkPcPrefs::get()->noteWakeFromOff(uuid, wake.value(QStringLiteral("supported")).toBool()
                                                      ? wake.value(QStringLiteral("fromOff")).toString()
                                                      : QStringLiteral("unsupported"));
        }
    }
    forkRefreshAll();
}

void ComputerModel::forkHandleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl)
{
    // The PC may have been deleted since the request: only a PC in the list counts, and nothing
    // reads the pointer otherwise
    const int row = m_Computers.indexOf(computer);
    if (row < 0) {
        return;
    }
    m_ForkArtRequested.remove(QPair<NvComputer*, int>(computer, app.id));
    emit dataChanged(createIndex(row, 0), createIndex(row, 0), QVector<int>() << PreviewAppsRole);
}

#include "computermodel.moc"
