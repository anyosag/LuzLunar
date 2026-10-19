#pragma once

#include <QDateTime>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>

class ComputerManager;
class QThreadPool;

// Apollo's over-the-air updates, seen from LuzLunar: each paired Apollo PC's version and update
// state (its /actions/update), and asking it to check, install, or install by itself. Apollo does
// the work and only takes builds signed by the fork's CI (anyosag/Apollo src/fork/updater.h).
// It needs the PC's "Update Apollo" permission, which clients with every permission have.
class ForkHostUpdates : public QObject
{
    Q_OBJECT

    // Bumped whenever any PC's state changes, so QML bindings on status() update
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    static ForkHostUpdates* get();

    // [fork] main.qml hands over its ComputerManager, then PCs are checked now and every 30 minutes
    Q_INVOKABLE void setComputerManager(QObject* manager);

    // A PC's state, by its uuid (ComputerModel's "uuid" role):
    //   known: answered at least once; supported: it's an Apollo that updates itself;
    //   permitted: this Mac may ask it to; busy: a request is in flight;
    //   updating: it's installing, so it's expected to go offline for a minute;
    //   version, latestVersion, latestNotes, update (a newer build is out), state, message,
    //   automatic, lastResult; error: why the last request failed
    Q_INVOKABLE QVariantMap status(const QString& uuid) const;

    Q_INVOKABLE void refresh(const QString& uuid);
    Q_INVOKABLE void refreshAll();
    Q_INVOKABLE void check(const QString& uuid);
    Q_INVOKABLE void install(const QString& uuid);
    Q_INVOKABLE void setAutomatic(const QString& uuid, bool automatic);

    int revision() const { return m_Revision; }

signals:
    void changed();

    // A PC finished updating (or went back), for a toast
    void finished(const QString& uuid, const QString& text);

private:
    struct Host {
        bool known = false;
        bool supported = false;
        bool permitted = false;
        int inFlight = 0;
        bool updating = false;
        QDateTime updateStarted;
        QString versionBefore;
        QJsonObject status;
        QString error;
    };

    explicit ForkHostUpdates(QObject* parent = nullptr);

    // GET /actions/update, or POST body to it
    void send(const QString& uuid, const QByteArray& body);
    void onResponse(const QString& uuid, int httpStatus, const QByteArray& body, const QString& networkError);
    void pollUpdating();

    QPointer<ComputerManager> m_Manager;
    QHash<QString, Host> m_Hosts;
    QThreadPool* m_Pool;
    QTimer m_RefreshTimer;
    QTimer m_UpdatingTimer;
    int m_Revision = 0;
};
