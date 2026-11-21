#pragma once

#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QTimer>

#include "localnetworkrules.h"

class ComputerManager;

// [fork] Whether macOS lets LuzLunar use the local network (Privacy & Security › Local Network),
// which it can quietly lose after an update (localnetworkrules.h). While LuzLunar is the active app
// it connects UDP sockets, sending nothing, to Bonjour's group and to each PC's LAN address: every
// 5 seconds while that's refused, every minute otherwise. Your PCs and Settings › Host & network
// show a warning with a button to System Settings while it's blocked; a toast says so once per run
// (in an update's words right after one), and again when it's back, when each PC that answered
// through the router is asked at its LAN address, as Bonjour would.
class ForkLocalNetwork : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool blocked READ blocked NOTIFY changed)

public:
    static ForkLocalNetwork* get();

    // ForkPcProbe hands over the manager; later calls do nothing
    void attach(ComputerManager* manager);

    // ForkUpdater, when the last run ended in an installed update: this is its first run
    void noteJustUpdated();

    bool blocked() const { return m_Access == LocalNetworkRules::Access::Blocked; }

    Q_INVOKABLE void checkNow();

    // System Settings › Privacy & Security › Local Network
    Q_INVOKABLE void openSettings();

signals:
    void changed();

    // A toast for main.qml
    void notice(QString text);

private slots:
    void handleApplicationState(Qt::ApplicationState state);

private:
    ForkLocalNetwork();

    void scheduleNext();
    void finished(LocalNetworkRules::Access access, const QString& refused, int error, const QStringList& reachable);
    void moveToLan(LocalNetworkRules::Access before, const QStringList& reachable);

    QPointer<ComputerManager> m_Manager;
    LocalNetworkRules::Access m_Access = LocalNetworkRules::Access::Unknown;
    bool m_Checking = false;
    bool m_BlockedTold = false;
    bool m_JustUpdated = false;
    QTimer m_Timer;
};
