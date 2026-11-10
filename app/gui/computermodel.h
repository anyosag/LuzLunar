#include "backend/boxartmanager.h" // [fork]
#include "backend/computermanager.h"
#include "streaming/session.h"

#include <QAbstractListModel>
#include <QHash> // [fork]
#include <QSet> // [fork]
#include <QPair> // [fork]
#include <QVector> // [fork]

class ComputerModel : public QAbstractListModel
{
    Q_OBJECT

    enum Roles
    {
        NameRole = Qt::UserRole,
        OnlineRole,
        PairedRole,
        BusyRole,
        WakeableRole,
        StatusUnknownRole,
        ServerSupportedRole,
        DetailsRole,
        HostSoftwareRole, // [fork]
        UuidRole, // [fork] which PC, for ForkHostUpdates

        // [fork] The redesigned PC card (the contract is spec/contract-data.md). Appended, so the
        // numbers above stay (the screenshot harness reads role 256 by number).
        StateRole,
        KnownPairedRole,
        ColorKeyRole,
        KeepFirstRole,
        WakeOnPickRole,
        ApolloVersionRole,
        NetworkRole,
        LatencyMsRole,
        AddressRole,
        AddressNoteRole,
        HasRemoteAddressRole,
        RemoteWorkedRole,
        FoundAutomaticallyRole,
        LastSeenSecsRole,
        LastSeenViaRole,
        RunningAppIdRole,
        RunningAppRole,
        StreamStartedHereRole,
        StreamWidthRole,
        StreamHeightRole,
        StreamFpsRole,
        StreamHdrRole,
        StreamCodecRole,
        HostUpdateRole,
        ApolloUpToDateRole,
        ApolloUpdatingRole,
        WakeFromOffRole,
        WakingRole,
        WakeTimedOutRole,
        PowerActionRole,
        CanSleepRole,
        CanShutDownRole,
        CanSetUpWakeRole,
        PreviewAppsRole,
        AppCountRole,
        HiddenAppCountRole,
        AppsCachedRole,
        MainAppIdRole,
        MainAppRole
    };

public:
    explicit ComputerModel(QObject* object = nullptr);

    // Must be called before any QAbstractListModel functions
    Q_INVOKABLE void initialize(ComputerManager* computerManager);

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void deleteComputer(int computerIndex);

    Q_INVOKABLE QString generatePinString();

    Q_INVOKABLE void pairComputer(int computerIndex, QString pin);

    Q_INVOKABLE void testConnectionForComputer(int computerIndex);

    Q_INVOKABLE void wakeComputer(int computerIndex);

    Q_INVOKABLE void renameComputer(int computerIndex, QString name);

    Q_INVOKABLE Session* createSessionForCurrentGame(int computerIndex);

    // [fork] The row of the PC with this uuid, -1 for none (rows move when a name or the PC kept first changes)
    Q_INVOKABLE int forkIndexOf(const QString& uuid) const;

    // [fork] Starts a stream of one of the PC's apps without an AppModel (the card's tiles), or null
    Q_INVOKABLE Session* createSessionForApp(int computerIndex, int appId);

    // [fork] Quits the app running on the PC (the card's Quit button)
    Q_INVOKABLE void quitRunningApp(int computerIndex);

signals:
    void pairingCompleted(QVariant error);
    void connectionTestCompleted(int result, QString blockedPorts);

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handlePairingCompleted(NvComputer* computer, QString error);

    void forkHandlePrefsChanged(const QString& uuid); // [fork]
    void forkHandleHostInfoChanged(); // [fork]
    void forkHandleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image); // [fork]
    void forkHandleLatency(const QString& uuid); // [fork]
    void forkHandleOrderChanged(); // [fork]

private:
    // [fork]
    struct Facts;
    Facts forkFacts(NvComputer* computer) const;
    QVariant forkData(NvComputer* computer, int role) const;
    QVector<NvApp> forkVisibleApps(const Facts& facts, NvComputer* computer) const;
    QVariantList forkPreviewApps(const Facts& facts, const QVector<NvApp>& visible, NvComputer* computer) const;
    void forkRecheckOrder();
    void forkRefreshAll();

    QVector<NvComputer*> m_Computers;
    ComputerManager* m_ComputerManager;

    // [fork] Per PC (by uuid): whether the last poll found it online (to ask for its art again when it
    // returns); the art requests in flight, by PC pointer (a PC can be deleted meanwhile)
    QHash<QString, bool> m_ForkWasOnline;
    mutable QSet<QPair<NvComputer*, int>> m_ForkArtRequested;
    mutable BoxArtManager m_ForkBoxArt;
};
