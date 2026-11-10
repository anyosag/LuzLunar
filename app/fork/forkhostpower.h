#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantMap>

#include "wakesetuprules.h"

class ComputerManager;
class QThreadPool;

// [fork] Sleep PC and Shut Down PC: putting a paired Apollo PC to sleep, or shutting it down, from
// LuzLunar, the pair to Wake PC (anyosag/Apollo src/fork/host_sleep.h). Each PC says through its
// /actions/sleep whether it can sleep now and which app it would quit first; it's asked when the
// PC's menu opens. Apollo never sleeps while anything streams, and needs the PC's "Sleep and Shut
// Down PC" permission, which clients with every permission have.
//
// Set Up Wake from Off (anyosag/Apollo src/fork/wake_setup.h): /actions/wake says what stops Wake
// PC from turning the PC on once it's off, and fixes it; WakeSetupRules (wakesetuprules.h) has the
// words. It also says how the PC was last turned on, so the toast after Wake PC can say whether
// it woke from sleep or was turned on.
class ForkHostPower : public QObject
{
    Q_OBJECT

    // Bumped whenever any PC's state changes, so QML bindings on status() and wakeStatus() update
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    static ForkHostPower* get();

    // main.qml hands over its ComputerManager; PCs are asked a little later and every 30 minutes
    Q_INVOKABLE void setComputerManager(QObject* manager);

    // A PC's state, by its uuid (ComputerModel's "uuid" role):
    //   known: answered at least once; supported: its Apollo can sleep from LuzLunar;
    //   permitted: this Mac may ask it to; available: it can sleep now;
    //   reason: "none", "streaming", "updating", "sleeping" or "app_running";
    //   app: the app still running, which sleeping would quit; busy: a request is in flight;
    //   canShutDown: its Apollo can also shut it down (Shut Down PC)
    Q_INVOKABLE QVariantMap status(const QString& uuid) const;

    // Asks /actions/sleep and /actions/wake again
    Q_INVOKABLE void refresh(const QString& uuid);
    Q_INVOKABLE void refreshAll();

    // Asks the PC for a fresh token, then to sleep. appToQuit: the app the warning named, which the
    // user agreed to quit, or empty; if another app runs by then, it asks again instead. finished()
    // tells how it went. afterStream: a stream with the PC just ended (the notch bar's "Quit <app>
    // and Sleep PC"), and Apollo drops a stream a moment after it ends, so a PC still streaming is
    // asked again a few times.
    Q_INVOKABLE void sleep(const QString& uuid, const QString& appToQuit, bool afterStream = false);

    // The same, to shut the PC down fully (not Fast Startup's hybrid shutdown), so Wake PC can turn
    // it on again. Only for an Apollo that says canShutDown: an older one would sleep instead.
    Q_INVOKABLE void shutDown(const QString& uuid, const QString& appToQuit);

    // Set Up Wake from Off, by the PC's uuid:
    //   known: Apollo answered; supported: its Apollo has /actions/wake; permitted: this Mac may ask;
    //   busy: a request is in flight; fromOff: "ready", "fixable", "blocked" or "unknown";
    //   summary, rows [{id, kind ("ok", "warn", "info"), title, detail}], bios, away (the router
    //   step, with the PC's LAN address and MAC), fixConfirmation, shutDownWarning;
    //   canFix, canUndo, applying, reason ("none", "streaming", "updating", "applying")
    Q_INVOKABLE QVariantMap wakeStatus(const QString& uuid) const;
    Q_INVOKABLE void refreshWake(const QString& uuid);

    // Fix on PC and Undo Changes: a fresh token, the request, then the PC asked every 3 s for up to a
    // minute (its network adapter restarts) until the change is done; wakeFinished() tells how it went
    Q_INVOKABLE void fixWake(const QString& uuid);
    Q_INVOKABLE void undoWake(const QString& uuid);

    // PcView's Wake PC was sent; when the PC then comes online (noteOnline()), poweredOn() says
    // whether it woke from sleep or was turned on, by Wake-on-LAN when the PC can tell
    Q_INVOKABLE void noteWakeSent(const QString& uuid);
    Q_INVOKABLE void noteOnline(const QString& uuid);

    int revision() const { return m_Revision; }

signals:
    void changed();

    // sleep()'s and shutDown()'s outcome, for a toast
    void finished(const QString& uuid, bool ok, const QString& text);

    // fixWake()'s and undoWake()'s outcome, for a toast
    void wakeFinished(const QString& uuid, bool ok, const QString& text);

    // A PC Wake PC was sent to is online: "<PC> is awake", "<PC> is on" or "<PC> turned on by Wake-on-LAN"
    void poweredOn(const QString& uuid, const QString& text);

private:
    struct Host {
        bool known = false;
        bool supported = false;
        bool permitted = false;
        bool available = false;
        bool canShutDown = false;
        QString reason;
        QString app;
        int inFlight = 0;

        bool wakeKnown = false;
        bool wakeSupported = false;
        bool wakePermitted = false;
        WakeSetupRules::Status wake;
        int wakeInFlight = 0;
        qint64 wakeSentAtMs = 0;    // when Wake PC was sent, until the PC is online
    };

    struct Answer {
        int httpStatus = 0;
        QVariantMap json;
        QString networkError;
    };

    // A PC's name, LAN address and MAC, for the texts
    struct Names {
        QString name;
        QString ip;
        QString mac;
    };

    explicit ForkHostPower(QObject* parent = nullptr);

    void requestPower(const QString& uuid, const QString& appToQuit, bool afterStream, bool off);
    void changeWake(const QString& uuid, bool undo);
    void requestWake(const QString& uuid, bool afterWake);
    Names names(const QString& uuid) const;

    void onStatus(const QString& uuid, const Answer& answer);
    void onSlept(const QString& uuid, bool ok, const QString& text, const Answer& status, bool off);
    void onWakeStatus(const QString& uuid, const Answer& answer);

    static WakeSetupRules::Status parseWake(const QVariantMap& json);

    QPointer<ComputerManager> m_Manager;
    QHash<QString, Host> m_Hosts;
    QThreadPool* m_Pool;
    QTimer m_RefreshTimer;
    int m_Revision = 0;
};
