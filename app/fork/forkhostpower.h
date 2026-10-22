#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>

class ComputerManager;
class QThreadPool;

// [fork] Sleep PC: putting a paired Apollo PC to sleep from LuzLunar, the pair to Wake PC
// (anyosag/Apollo src/fork/host_sleep.h). Each PC says through its /actions/sleep whether it can
// sleep now and which app it would quit first; it's asked when the PC's menu opens. Apollo never
// sleeps while anything streams, and needs the PC's "Sleep PC" permission, which clients with
// every permission have.
class ForkHostPower : public QObject
{
    Q_OBJECT

    // Bumped whenever any PC's state changes, so QML bindings on status() update
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    static ForkHostPower* get();

    // main.qml hands over its ComputerManager; PCs are asked a little later and every 30 minutes
    Q_INVOKABLE void setComputerManager(QObject* manager);

    // A PC's state, by its uuid (ComputerModel's "uuid" role):
    //   known: answered at least once; supported: its Apollo can sleep from LuzLunar;
    //   permitted: this Mac may ask it to; available: it can sleep now;
    //   reason: "none", "streaming", "updating", "sleeping" or "app_running";
    //   app: the app still running, which sleeping would quit; busy: a request is in flight
    Q_INVOKABLE QVariantMap status(const QString& uuid) const;

    Q_INVOKABLE void refresh(const QString& uuid);
    Q_INVOKABLE void refreshAll();

    // Asks the PC for a fresh token, then to sleep. appToQuit: the app the warning named, which the
    // user agreed to quit, or empty; if another app runs by then, it asks again instead. finished()
    // tells how it went.
    Q_INVOKABLE void sleep(const QString& uuid, const QString& appToQuit);

    int revision() const { return m_Revision; }

signals:
    void changed();

    // sleep()'s outcome, for a toast
    void finished(const QString& uuid, bool ok, const QString& text);

private:
    struct Host {
        bool known = false;
        bool supported = false;
        bool permitted = false;
        bool available = false;
        QString reason;
        QString app;
        int inFlight = 0;
    };

    struct Answer {
        int httpStatus = 0;
        QVariantMap json;
        QString networkError;
    };

    explicit ForkHostPower(QObject* parent = nullptr);

    void onStatus(const QString& uuid, const Answer& answer);
    void onSlept(const QString& uuid, bool ok, const QString& text, const Answer& status);

    QPointer<ComputerManager> m_Manager;
    QHash<QString, Host> m_Hosts;
    QThreadPool* m_Pool;
    QTimer m_RefreshTimer;
    int m_Revision = 0;
};
