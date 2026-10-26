#pragma once

#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QThreadPool>

class ComputerManager;

// Settings › Display › Multiple displays: what DisplayExtend's Host says about the iMac, and
// "Set up the iMac", which pairs the Moonlight inside the iMac's DisplayExtend client with this
// Mac's Apollo PCs so the iMac can stream its display straight from the PC
// (forkdisplayroute.*). Everything goes through DisplayExtend's Host on this Mac
// (forkdisplayextend.*); nothing is installed or typed on the iMac. LuzLunar picks the PIN: the
// Host has the iMac run Moonlight's pair with it, and Apollo takes it from this Mac with
// POST /actions/pairdevice (the "Pair other devices" permission), for the waiting device at the
// iMac's address only.
class ForkImacSetup : public QObject
{
    Q_OBJECT

    // One line on DisplayExtend and the iMac, for Settings; empty until the first refresh
    Q_PROPERTY(QString status READ status NOTIFY changed)

    // DisplayExtend's Host answered, with the iMac connected
    Q_PROPERTY(bool available READ available NOTIFY changed)

    // The iMac can stream from a PC, and an online Apollo PC it isn't paired with can pair it
    Q_PROPERTY(bool canSetUp READ canSetUp NOTIFY changed)

    Q_PROPERTY(bool busy READ busy NOTIFY changed)

public:
    static ForkImacSetup* get();

    QString status() const { return m_Status; }
    bool available() const { return m_Available; }
    bool canSetUp() const { return m_CanSetUp; }
    bool busy() const { return m_Busy; }

    Q_INVOKABLE void setComputerManager(QObject* manager);

    // Asks DisplayExtend's Host again
    Q_INVOKABLE void refresh();

    // Pairs the iMac with each online Apollo PC that can pair it and isn't paired yet
    Q_INVOKABLE void setUp();

signals:
    void changed();

    // A setup's outcome, for a toast
    void finished(QString text);

private:
    explicit ForkImacSetup(QObject* parent = nullptr);

    void applyStatus(const QString& status, bool available, bool directReady, const QStringList& pairedHostIds);
    void updateCanSetUp();

    QPointer<ComputerManager> m_Manager;
    QThreadPool m_Pool;
    QString m_Status;
    bool m_Available = false;
    bool m_DirectReady = false;      // the iMac's client offers direct streams and its Moonlight is verified
    QStringList m_PairedHostIds;
    bool m_CanSetUp = false;
    bool m_Busy = false;
};
