#pragma once

#include <QDateTime>
#include <QNetworkAccessManager>
#include <QObject>
#include <QTimer>

#include "forkupdaterules.h"

class QNetworkReply;

// LuzLunar's over-the-air updates: checks the fork's latest master release, downloads and checks
// the app (its signature against the key in updatekey.h, then its code signature against this
// app's), and swaps it in when you click Install, or by itself with automatic updates on: when you
// quit LuzLunar, or after a while in the background with no stream. See FORK.md, "Updates".
class ForkUpdater : public QObject
{
    Q_OBJECT

    // This build
    Q_PROPERTY(QString buildId READ buildId CONSTANT)
    Q_PROPERTY(qint64 run READ run CONSTANT)
    Q_PROPERTY(bool masterBuild READ masterBuild CONSTANT)

    // Whether this build can replace itself: macOS, signed with LuzLunar's certificate
    Q_PROPERTY(bool supported READ supported CONSTANT)

    // "idle", "checking", "downloading", "ready", "installing" or "failed", and what it means
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)

    // The latest master build, once checked
    Q_PROPERTY(bool updateAvailable READ updateAvailable NOTIFY changed)
    Q_PROPERTY(bool updateReady READ updateReady NOTIFY changed)
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY changed)
    Q_PROPERTY(QString latestNotes READ latestNotes NOTIFY changed)

    // How the last install went, from the swap helper; empty if there's nothing to report
    Q_PROPERTY(QString lastResult READ lastResult NOTIFY changed)

    // macOS refused to let LuzLunar replace itself (Privacy & Security › App Management)
    Q_PROPERTY(bool needsAppManagement READ needsAppManagement NOTIFY changed)

    // Install updates by themselves (off by default)
    Q_PROPERTY(bool automatic READ automatic WRITE setAutomatic NOTIFY automaticChanged)

public:
    static ForkUpdater* get();

    // Start checking: now, then every 30 minutes. [fork] main.qml calls it once the window is up,
    // so command-line runs (like the swap helper's --version check) never do.
    Q_INVOKABLE void start();

    Q_INVOKABLE void check();

    // Install the ready update and restart into it
    Q_INVOKABLE void installNow();

    Q_INVOKABLE void openAppManagementSettings();

    QString buildId() const;
    qint64 run() const { return m_Build.run; }
    bool masterBuild() const { return m_Build.isMaster(); }
    bool supported() const { return m_Supported; }
    QString state() const { return m_State; }
    QString message() const { return m_Message; }
    bool updateAvailable() const;
    bool updateReady() const { return m_State == QStringLiteral("ready"); }
    QString latestVersion() const;
    QString latestNotes() const;
    QString lastResult() const { return m_LastResult; }
    bool needsAppManagement() const { return m_NeedsAppManagement; }
    bool automatic() const { return m_Automatic; }
    void setAutomatic(bool automatic);

signals:
    void changed();
    void automaticChanged();

private:
    explicit ForkUpdater(QObject* parent = nullptr);

    QString updatesDir() const;
    QString runDir(qint64 run) const;
    void setState(const QString& state, const QString& message);
    void readLastResult();

    // A GET that follows redirects only to the hosts ForkUpdateRules::allowedDownloadUrl() allows
    QNetworkReply* get(const QString& url);
    void onManifest(const QByteArray& manifest, const QByteArray& signature);
    void download();
    void extract();
    void verifyExtracted();

    void install(int relaunch);
    void onQuit();
    void onIdleTick();

    ForkUpdateRules::Build m_Build;
    bool m_Supported = false;
    bool m_Started = false;
    bool m_Automatic = false;
    bool m_Installing = false;
    bool m_NeedsAppManagement = false;
    QString m_State = QStringLiteral("idle");
    QString m_Message;
    QString m_LastResult;

    bool m_HaveLatest = false;
    ForkUpdateRules::Manifest m_Latest;
    QString m_ReadyApp;         // the checked new LuzLunar.app

    QNetworkAccessManager m_Network;
    QTimer m_CheckTimer;
    QTimer m_IdleTimer;
    QDateTime m_InactiveSince;  // invalid while LuzLunar is the active app
};
