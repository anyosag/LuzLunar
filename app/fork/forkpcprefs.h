#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <QVariantMap>

// [fork] What LuzLunar keeps about each PC on this Mac only, for the redesigned Your PCs: its color,
// the PC kept first, whether picking an app wakes it, and what its card says while it's away (when
// and where it was last seen, whether it answered at its outside address, what this Mac last asked
// of it, whether it can wake from off, its Apollo version), the apps last streamed from it and the
// last stream's format. Under "fork/firstPc" and "fork/pcs/<uuid>/" in Moonlight's settings, never
// in the "hosts" array (upstream Moonlight rewrites that whole array). Main thread, except
// firstPcUuid().
class ForkPcPrefs : public QObject
{
    Q_OBJECT

    // Bumped on every change, for bindings on the getters
    Q_PROPERTY(int revision READ revision NOTIFY changed)

    // Customize's swatches, in order
    Q_PROPERTY(QStringList colorIds READ colorIds CONSTANT)

    // The first word of the macOS account's full name (the short user name when it has none). In a
    // screenshot run it is the sample "Gonzalo", and the account isn't read.
    Q_PROPERTY(QString firstName READ firstName CONSTANT)

    // LUZLUNAR_DEMO=1: Your PCs plays its autoplay demo (the OptionLoop board). Never on by default.
    Q_PROPERTY(bool demoMode READ demoMode CONSTANT)

    // LUZLUNAR_SCREENSHOTS is set: pages draw deterministic frames from sample data
    Q_PROPERTY(bool screenshotMode READ screenshotMode CONSTANT)

public:
    static ForkPcPrefs* get();

    int revision() const { return m_Revision; }
    QStringList colorIds() const;
    QString firstName() const;
    bool demoMode() const;
    bool screenshotMode() const;

    // The PC's color: the stored one, else the first of the palette's order that no other PC has
    // (card.md §2.2), which is stored then so it never changes by itself. A PC that isn't paired
    // is drawn gray by the page; ComputerModel's "colorKey" role is already that.
    Q_INVOKABLE QString colorKey(const QString& uuid);
    Q_INVOKABLE void setColorKey(const QString& uuid, const QString& key);

    // Keep it first in the carousel: one PC at most; turning it on clears it on the others
    Q_INVOKABLE bool keepFirst(const QString& uuid) const;
    Q_INVOKABLE void setKeepFirst(const QString& uuid, bool on);

    // Picking an app on a sleeping PC wakes it first (on unless set otherwise)
    Q_INVOKABLE bool wakeOnPick(const QString& uuid) const;
    Q_INVOKABLE void setWakeOnPick(const QString& uuid, bool on);

    // The uuid of the PC kept first, "" for none. Any thread: ComputerManager::getComputers() sorts
    // with it.
    static QString firstPcUuid();

    // Removes everything kept about the PC (it was removed from LuzLunar)
    Q_INVOKABLE void forget(const QString& uuid);

    // --- Remembered for the cards of PCs that are away (ComputerModel writes them) ---

    // When the PC was last online (seconds since 1970 UTC, 0 never) and through which address:
    // "home", "internet" or ""
    qint64 lastSeenSecs(const QString& uuid) const;
    QString lastSeenVia(const QString& uuid) const;
    void noteLastSeen(const QString& uuid, qint64 secs, const QString& via);

    // The PC answered at its outside address (seconds, 0 never)
    qint64 remoteWorkedSecs(const QString& uuid) const;
    void noteRemoteWorked(const QString& uuid, qint64 secs);

    // What this Mac last asked of the PC: "sleep" or "off" (ForkHostPower), "" none; and when
    QString powerAction(const QString& uuid) const;
    qint64 powerActionSecs(const QString& uuid) const;
    void notePowerAction(const QString& uuid, const QString& action);
    void clearPowerAction(const QString& uuid);

    // Apollo's version and whether it had an update, from its last answer
    QString apolloVersion(const QString& uuid) const;
    bool apolloUpdate(const QString& uuid) const;
    void noteApollo(const QString& uuid, const QString& version, bool update);

    // Apollo's last answer on waking from off: ready, fixable, blocked, unknown, unsupported; ""
    QString wakeFromOff(const QString& uuid) const;
    void noteWakeFromOff(const QString& uuid, const QString& fromOff);

    // A stream of an app started here: its format, and the app moves to the front of the PC's
    // recent apps (names, newest first, at most 8)
    void noteStream(const QString& uuid, int appId, const QString& appName, int width, int height,
                    int fps, bool hdr, const QString& codec);
    QVariantMap lastStream(const QString& uuid) const;     // { appId, appName, width, height, fps, hdr, codec } or {}
    QStringList recentApps(const QString& uuid) const;

    // Wake PC was sent from this Mac (memory only): the card says "Waking…" until the PC answers
    // or k_WakeWaitSecs pass
    void noteWakeSent(const QString& uuid);
    void clearWakeSent(const QString& uuid);
    qint64 wakeSentSecs(const QString& uuid) const;        // 0 none

signals:
    // Something about this PC changed (ComputerModel and the dialogs listen)
    void changed(QString uuid);

private:
    ForkPcPrefs();

    static bool validUuid(const QString& uuid);
    static QString key(const QString& uuid, const QString& name);
    QVariant read(const QString& uuid, const QString& name) const;
    void write(const QString& uuid, const QString& name, const QVariant& value, bool notify = true);
    void bump(const QString& uuid);

    int m_Revision = 0;
    QHash<QString, qint64> m_WakeSent;
};
