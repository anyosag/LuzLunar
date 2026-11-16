#pragma once

#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QVariantMap>

#include "wakeoutsiderules.h"

class ComputerManager;
class NvComputer;

// [fork] Wake PC from outside the PC's home network (wakeoutsiderules.h has the rules and the
// words; FORK.md, "Wake from outside").
//
// Says where a Wake PC goes from where this Mac is: a broadcast on the PC's home network, or, away,
// the home's own address for the router to pass on. Each Wake PC is logged as "[fork] Wake PC to
// ..." (luz-debug.py luz log -g Wake). And it checks, from home, whether the home's address reaches
// the PC and which of its addresses the router passes it on to: Moonlight's unauthenticated
// serverinfo through that address (the router passes its own address back in, and Apollo's
// <LocalIP> says where the request came in). The result is kept per PC
// (ForkPcPrefs::outsideCheck()), so the steps can say it while this Mac is away. (This Mac's ARP
// table would show the PC's other addresses, but macOS 26 hides it from apps that aren't Apple's
// own.) Main thread, except the check's own worker.
class ForkWakeOutside : public QObject
{
    Q_OBJECT

    // Bumped whenever a check starts or ends, for bindings on status()
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    static ForkWakeOutside* get();

    // ComputerModel hands over its manager; later calls do nothing
    void setComputerManager(ComputerManager* manager);

    // Where a Wake PC to this PC goes from here now
    struct Route {
        QString route;      // home, outside, none
        QString address;    // the address the card names for an outside one
        WakeOutsideRules::Where where;
    };
    Route routeFor(NvComputer* computer) const;

    // A Wake PC is being sent to this PC (ComputerModel::wakeComputer()): notes where it goes for
    // the card (ForkPcPrefs::noteWakeRoute()) and logs it
    void noteWake(NvComputer* computer);

    // For ForkWakeOutsideDialog and Set Up Wake from Off's last section: { intro, rows [{id, kind,
    // title, detail}], atHome, online, checking, blocker (why Check Again can't run, "" when it can),
    // checked (it ran at least once) }
    Q_INVOKABLE QVariantMap status(const QString& uuid) const;

    // Checks from home now, when this Mac is on the PC's home network and the PC answers
    Q_INVOKABLE void check(const QString& uuid);

    // The PC came online on its home network: checks when one is due (WakeOutsideRules::checkDue())
    void checkIfDue(const QString& uuid);

    // Shut Down PC's warning while this Mac is away from the PC's home network; "" at home
    Q_INVOKABLE QString shutDownWarning(const QString& uuid) const;

    int revision() const { return m_Revision; }

signals:
    void changed();

    // A Wake PC from outside got no answer in time, for a toast (main.qml)
    void missed(const QString& uuid, const QString& text);

private:
    ForkWakeOutside();

    NvComputer* find(const QString& uuid) const;
    void onWakeTimedOut(const QString& uuid);
    void bump();

    QPointer<ComputerManager> m_Manager;
    QSet<QString> m_Checking;
    int m_Revision = 0;
};
