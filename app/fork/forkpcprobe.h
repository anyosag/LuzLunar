#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVector>

class ComputerManager;
class NvComputer;

// [fork] The one object per process that watches the PCs for the cards in Your PCs: what the cards
// remember about a PC that goes away or comes back (when and where it was last seen, whether its
// outside address worked, a Sleep PC / Shut Down PC that is over), and how fast each online PC
// answers. ComputerModels (there are several: Your PCs, Settings) only read it, so opening a page
// doesn't repeat any of it. The latency is the time of a TCP connect to the PC's HTTP port, measured
// on a worker thread every 10 s while LuzLunar is the active app and nothing is streaming.
class ForkPcProbe : public QObject
{
    Q_OBJECT

public:
    static ForkPcProbe* get();

    // The first ComputerModel hands over the manager; later calls do nothing
    void attach(ComputerManager* manager);

    // Median of the last 5 samples in ms, -1 for none
    int latencyMs(const QString& uuid) const;

signals:
    void latencyChanged(QString uuid);

private slots:
    void handleComputerStateChanged(NvComputer* computer);
    void probe();
    void handleApplicationState();
    void writeLastSeen();

private:
    ForkPcProbe();

    void note(NvComputer* computer);
    void updateTimer();
    void addSample(const QString& uuid, int ms);

    QPointer<ComputerManager> m_Manager;
    QHash<QString, bool> m_WasOnline;
    QHash<QString, QString> m_Via;
    QHash<QString, QVector<int>> m_Latency;
    QSet<QString> m_Probing;
    QTimer m_Timer;
};
