#pragma once

#include "backend/boxartmanager.h"
#include "backend/computermanager.h"
#include "streaming/session.h"

#include <QAbstractListModel>

class AppModel : public QAbstractListModel
{
    Q_OBJECT

    enum Roles
    {
        NameRole = Qt::UserRole,
        RunningRole,
        BoxArtRole,
        HiddenRole,
        AppIdRole,
        DirectLaunchRole,
        AppCollectorGameRole,
    };

public:
    explicit AppModel(QObject *parent = nullptr);

    // Must be called before any QAbstractListModel functions
    Q_INVOKABLE void initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames);

    Q_INVOKABLE Session* createSessionForApp(int appIndex);

    // [fork] The row of the app with this ID, or -1: rows shift when the multi-display app comes
    // and goes with the Mac's displays, so a row kept across a dialog can point at another app
    Q_INVOKABLE int forkIndexOfApp(int appId);

    Q_INVOKABLE int getDirectLaunchAppIndex();

    Q_INVOKABLE int getRunningAppId();

    Q_INVOKABLE QString getRunningAppName();

    Q_INVOKABLE void quitRunningApp();

    Q_INVOKABLE void setAppHidden(int appIndex, bool hidden);

    Q_INVOKABLE void setAppDirectLaunch(int appIndex, bool directLaunch);

    // [fork] The apps page's search: only apps whose names contain this text (in any case) stay,
    // and the running app always does, so the header's Resume and Quit can still reach it. Empty
    // shows every app again.
    Q_INVOKABLE void forkSetNameFilter(const QString& text);

    // [fork] The PC for the apps page's header: "address" (the one LuzLunar uses now), "local" or
    // "remote" (whether that's its address on this network or the one from outside), "software"
    // ("Apollo", "Sunshine" or "GeForce Experience"), "uuid", "online" and "lastAddress" (the PC's
    // LAN, typed, outside or IPv6 address, for a PC that's away)
    Q_INVOKABLE QVariantMap forkHostInfo();

    // [fork] The app that runs, for the apps page's header, whether or not the grid shows its tile:
    // "id", "name", and "boxart" when it's one of this model's rows; empty with nothing running
    Q_INVOKABLE QVariantMap forkRunningApp();

    // [fork] The apps page stays while its PC sleeps (All apps of an asleep PC): the apps of the
    // PC's last visit, nothing running, art only from the cache; only losing the pairing sends the
    // page back (computerLost). Off by default, which keeps upstream's behaviour: an offline PC
    // emits computerLost. AppView turns it on for an asleep PC's page, right after initialize().
    Q_INVOKABLE void forkKeepWhenOffline(bool keep);

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image);

signals:
    void computerLost();

private:
    void updateAppList(QVector<NvApp> newList);

    QVector<NvApp> getVisibleApps(const QVector<NvApp>& appList);

    bool isAppCurrentlyVisible(const NvApp& app);

    NvComputer* m_Computer = nullptr; // [fork] null until initialize(), which forkHostInfo() checks
    BoxArtManager m_BoxArtManager;
    ComputerManager* m_ComputerManager;
    QVector<NvApp> m_VisibleApps, m_AllApps;
    int m_CurrentGameId = 0; // [fork] set for an empty model too (initialize())
    bool m_ShowHiddenGames = false; // [fork]
    QString m_ForkNameFilter; // [fork] forkSetNameFilter()
    bool m_ForkKeepOffline = false; // [fork] forkKeepWhenOffline()
    bool m_ForkWasOffline = false; // [fork] the PC was away at the last update: its art may be missing
};
