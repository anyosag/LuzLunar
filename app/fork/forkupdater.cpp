#include "forkupdater.h"

#include <memory>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QPointer>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>

#include "forkpreferences.h"
#include "mac/selfupdate_mac.h"
#include "streaming/session.h"
#include "updatekey.h"

// CI sets these for the build (scripts/fork/build-mac.sh); a local build is a branch build
#ifndef FORK_BUILD_RUN
#define FORK_BUILD_RUN 0
#endif
#ifndef FORK_BUILD_CHANNEL
#define FORK_BUILD_CHANNEL "local"
#endif

#define SER_AUTOUPDATE "fork/autoUpdate"

namespace
{
    const int k_CheckIntervalMs = 30 * 60 * 1000;
    const int k_FirstCheckDelayMs = 20 * 1000;
    const int k_IdleTickMs = 60 * 1000;
    const char k_AppName[] = "LuzLunar.app";

    std::string toStd(const QJsonValue& value)
    {
        return value.toString().toStdString();
    }

    // A JSON number that's a whole number, or -1
    qint64 toWhole(const QJsonValue& value)
    {
        if (!value.isDouble()) {
            return -1;
        }
        double d = value.toDouble();
        qint64 whole = static_cast<qint64>(d);
        return static_cast<double>(whole) == d ? whole : -1;
    }
}

ForkUpdater* ForkUpdater::get()
{
    static ForkUpdater* s_Instance = new ForkUpdater(QCoreApplication::instance());
    return s_Instance;
}

ForkUpdater::ForkUpdater(QObject* parent)
    : QObject(parent)
{
    m_Build.run = FORK_BUILD_RUN;
    m_Build.channel = FORK_BUILD_CHANNEL;
    m_Supported = SelfUpdateMac::signedWithCertificate();
    m_Automatic = QSettings().value(SER_AUTOUPDATE, false).toBool();

    m_CheckTimer.setInterval(k_CheckIntervalMs);
    connect(&m_CheckTimer, &QTimer::timeout, this, &ForkUpdater::check);
    m_IdleTimer.setInterval(k_IdleTickMs);
    connect(&m_IdleTimer, &QTimer::timeout, this, &ForkUpdater::onIdleTick);
}

QString ForkUpdater::buildId() const
{
    return ForkPreferences::get()->buildId();
}

bool ForkUpdater::updateAvailable() const
{
    return m_HaveLatest && ForkUpdateRules::isUpdate(m_Latest, m_Build);
}

QString ForkUpdater::latestVersion() const
{
    return m_HaveLatest ? QString::fromStdString(m_Latest.version) : QString();
}

QString ForkUpdater::latestNotes() const
{
    return m_HaveLatest ? QString::fromStdString(m_Latest.notes) : QString();
}

void ForkUpdater::setAutomatic(bool automatic)
{
    if (automatic == m_Automatic) {
        return;
    }
    m_Automatic = automatic;
    QSettings().setValue(SER_AUTOUPDATE, automatic);
    emit automaticChanged();
}

QString ForkUpdater::updatesDir() const
{
    return QDir(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)).filePath(QStringLiteral("updates"));
}

QString ForkUpdater::runDir(qint64 run) const
{
    return QDir(updatesDir()).filePath(QString::number(run));
}

void ForkUpdater::setState(const QString& state, const QString& message)
{
    m_State = state;
    m_Message = message;
    emit changed();
}

void ForkUpdater::start()
{
    if (m_Started) {
        return;
    }
    m_Started = true;

    QDir().mkpath(updatesDir());

    // Tells a swap helper waiting on this build that it started
    QFile started(QDir(updatesDir()).filePath(QStringLiteral("started")));
    if (started.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        started.write(buildId().toUtf8());
    }
    readLastResult();

    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive) {
            m_InactiveSince = QDateTime();
        }
        else if (!m_InactiveSince.isValid()) {
            m_InactiveSince = QDateTime::currentDateTimeUtc();
        }
    });
    connect(qApp, &QCoreApplication::aboutToQuit, this, &ForkUpdater::onQuit);

    // The CI screenshot run shouldn't reach out to GitHub
    if (qEnvironmentVariableIsSet("LUZLUNAR_SCREENSHOTS")) {
        return;
    }
    QTimer::singleShot(k_FirstCheckDelayMs, this, &ForkUpdater::check);
    m_CheckTimer.start();
    m_IdleTimer.start();
}

void ForkUpdater::readLastResult()
{
    QFile file(QDir(updatesDir()).filePath(QStringLiteral("result")));
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    std::optional<ForkUpdateRules::SwapResult> result = ForkUpdateRules::parseSwapResult(file.read(256).toStdString());
    file.close();
    file.remove();
    if (!result) {
        return;
    }

    switch (result->kind) {
    case ForkUpdateRules::SwapResult::Installed:
        m_LastResult = tr("Updated to %1").arg(buildId());
        // Started fine, so the previous build isn't needed to go back to
        QDir(QDir(updatesDir()).filePath(QStringLiteral("previous"))).removeRecursively();
        QDir(QDir(updatesDir()).filePath(QStringLiteral("failed.app"))).removeRecursively();
        break;
    case ForkUpdateRules::SwapResult::RolledBack:
        m_LastResult = tr("The update didn't start, so LuzLunar went back to %1.").arg(buildId());
        break;
    case ForkUpdateRules::SwapResult::Failed:
        if (result->reason == "move") {
            m_NeedsAppManagement = true;
            m_LastResult = tr("macOS didn't let LuzLunar replace itself. Allow LuzLunar in Privacy & Security › App Management, then install the update again.");
        }
        else if (result->reason == "check") {
            m_LastResult = tr("The downloaded build didn't start, so LuzLunar kept this one.");
        }
        else {
            m_LastResult = tr("LuzLunar didn't quit in time, so the update wasn't installed.");
        }
        break;
    }
    emit changed();
}

QNetworkReply* ForkUpdater::get(const QString& url)
{
    QNetworkRequest request{QUrl(url)};
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::UserVerifiedRedirectPolicy);
    request.setTransferTimeout(60 * 1000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("LuzLunar-updater"));

    QNetworkReply* reply = m_Network.get(request);
    connect(reply, &QNetworkReply::redirected, reply, [reply](const QUrl& target) {
        if (ForkUpdateRules::allowedDownloadUrl(target.toString(QUrl::FullyEncoded).toStdString())) {
            emit reply->redirectAllowed();
        }
        else {
            reply->abort();
        }
    });
    return reply;
}

void ForkUpdater::check()
{
    if (!m_Started || m_State == QStringLiteral("checking") || m_State == QStringLiteral("downloading") || m_State == QStringLiteral("installing")) {
        return;
    }
    setState(QStringLiteral("checking"), tr("Checking for updates…"));

    // The manifest, then its signature
    QNetworkReply* manifestReply = get(QString::fromUtf8(ForkUpdateKey::k_ManifestUrl.data(), ForkUpdateKey::k_ManifestUrl.size()));
    connect(manifestReply, &QNetworkReply::finished, this, [this, manifestReply]() {
        manifestReply->deleteLater();
        QByteArray manifest = manifestReply->readAll();
        if (manifestReply->error() != QNetworkReply::NoError || manifest.size() > (qsizetype)ForkUpdateRules::k_MaxManifestSize) {
            setState(QStringLiteral("failed"), tr("Couldn't check for updates: %1").arg(manifestReply->errorString()));
            return;
        }

        QNetworkReply* signatureReply = get(QString::fromUtf8(ForkUpdateKey::k_SignatureUrl.data(), ForkUpdateKey::k_SignatureUrl.size()));
        connect(signatureReply, &QNetworkReply::finished, this, [this, signatureReply, manifest]() {
            signatureReply->deleteLater();
            QByteArray signature = signatureReply->read(1024);
            if (signatureReply->error() != QNetworkReply::NoError) {
                setState(QStringLiteral("failed"), tr("Couldn't check for updates: %1").arg(signatureReply->errorString()));
                return;
            }
            onManifest(manifest, signature);
        });
    });
}

void ForkUpdater::onManifest(const QByteArray& manifest, const QByteArray& signature)
{
    if (!ForkUpdateRules::verifyManifest(ForkUpdateKey::k_PublicKey, manifest.toStdString(), signature.toStdString())) {
        setState(QStringLiteral("failed"), tr("The update's signature doesn't match LuzLunar's key, so it was ignored."));
        return;
    }

    QJsonParseError parseError;
    QJsonDocument document = QJsonDocument::fromJson(manifest, &parseError);
    if (document.isNull() || !document.isObject()) {
        setState(QStringLiteral("failed"), tr("The update's description can't be read."));
        return;
    }
    QJsonObject json = document.object();
    QJsonObject asset = json.value(QStringLiteral("asset")).toObject();

    ForkUpdateRules::Manifest m;
    m.product = toStd(json.value(QStringLiteral("product")));
    m.channel = toStd(json.value(QStringLiteral("channel")));
    m.run = toWhole(json.value(QStringLiteral("run")));
    m.version = toStd(json.value(QStringLiteral("version")));
    m.commit = toStd(json.value(QStringLiteral("commit")));
    m.published = toStd(json.value(QStringLiteral("published")));
    m.notes = toStd(json.value(QStringLiteral("notes")));
    m.asset.name = toStd(asset.value(QStringLiteral("name")));
    m.asset.url = toStd(asset.value(QStringLiteral("url")));
    m.asset.sha256 = toStd(asset.value(QStringLiteral("sha256")));
    qint64 size = toWhole(asset.value(QStringLiteral("size")));
    m.asset.size = size > 0 ? static_cast<uint64_t>(size) : 0;

    std::string error;
    if (!ForkUpdateRules::validate(m, ForkUpdateKey::k_Product, ForkUpdateKey::k_AssetUrlPrefix, &error)) {
        setState(QStringLiteral("failed"), tr("The update was ignored: %1").arg(QString::fromStdString(error)));
        return;
    }

    bool sameAsReady = m_HaveLatest && m_Latest.run == m.run && !m_ReadyApp.isEmpty();
    m_Latest = m;
    m_HaveLatest = true;

    if (!ForkUpdateRules::isUpdate(m, m_Build)) {
        m_ReadyApp.clear();
        setState(QStringLiteral("idle"), tr("LuzLunar is up to date."));
        return;
    }
    if (sameAsReady) {
        setState(QStringLiteral("ready"), tr("%1 is ready to install.").arg(latestVersion()));
        return;
    }
    download();
}

void ForkUpdater::download()
{
    // Earlier runs' downloads aren't needed any more
    QDir updates(updatesDir());
    for (const QString& entry : updates.entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool isRun = false;
        qint64 run = entry.toLongLong(&isRun);
        if (isRun && run != m_Latest.run) {
            QDir(updates.filePath(entry)).removeRecursively();
        }
    }

    QString dir = runDir(m_Latest.run);
    QDir().mkpath(dir);
    QString zipPath = QDir(dir).filePath(QString::fromStdString(m_Latest.asset.name));

    // Downloaded and checked on an earlier check
    if (QFile::exists(zipPath)) {
        extract();
        return;
    }

    setState(QStringLiteral("downloading"), tr("Downloading %1…").arg(latestVersion()));

    auto* file = new QFile(zipPath + QStringLiteral(".part"), this);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        delete file;
        setState(QStringLiteral("failed"), tr("Couldn't save the update."));
        return;
    }

    QNetworkReply* reply = get(QString::fromStdString(m_Latest.asset.url));
    auto* hash = new QCryptographicHash(QCryptographicHash::Sha256);
    uint64_t expectedSize = m_Latest.asset.size;
    auto received = std::make_shared<uint64_t>(0);

    connect(reply, &QNetworkReply::readyRead, this, [reply, file, hash, received, expectedSize]() {
        QByteArray chunk = reply->readAll();
        *received += chunk.size();
        if (*received > expectedSize) {
            reply->abort();
            return;
        }
        hash->addData(chunk);
        file->write(chunk);
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, file, hash, received, expectedSize, zipPath]() {
        reply->deleteLater();
        QByteArray rest = reply->readAll();
        if (!rest.isEmpty() && *received + rest.size() <= expectedSize) {
            *received += rest.size();
            hash->addData(rest);
            file->write(rest);
        }
        file->close();
        QString digest = QString::fromLatin1(hash->result().toHex());
        delete hash;

        bool ok = reply->error() == QNetworkReply::NoError && *received == expectedSize &&
                  digest == QString::fromStdString(m_Latest.asset.sha256);
        if (!ok) {
            file->remove();
            delete file;
            setState(QStringLiteral("failed"), reply->error() != QNetworkReply::NoError
                                                   ? tr("Couldn't download the update: %1").arg(reply->errorString())
                                                   : tr("The download doesn't match the update's SHA-256, so it was thrown away."));
            return;
        }
        QFile::remove(zipPath);
        file->rename(zipPath);
        delete file;
        extract();
    });
}

void ForkUpdater::extract()
{
    QString dir = runDir(m_Latest.run);
    QString zipPath = QDir(dir).filePath(QString::fromStdString(m_Latest.asset.name));
    QString extracted = QDir(dir).filePath(QStringLiteral("extracted"));
    QDir(extracted).removeRecursively();

    setState(QStringLiteral("downloading"), tr("Unpacking %1…").arg(latestVersion()));

    // ditto keeps the bundle's signature and extended attributes, as it was zipped
    auto* process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus status) {
        process->deleteLater();
        if (status != QProcess::NormalExit || exitCode != 0) {
            QDir(runDir(m_Latest.run)).removeRecursively();
            setState(QStringLiteral("failed"), tr("Couldn't unpack the update."));
            return;
        }
        verifyExtracted();
    });
    process->start(QStringLiteral("/usr/bin/ditto"), {QStringLiteral("-x"), QStringLiteral("-k"), zipPath, extracted});
}

void ForkUpdater::verifyExtracted()
{
    QString app = QDir(QDir(runDir(m_Latest.run)).filePath(QStringLiteral("extracted"))).filePath(QString::fromLatin1(k_AppName));
    if (!QFileInfo(app).isDir()) {
        QDir(runDir(m_Latest.run)).removeRecursively();
        setState(QStringLiteral("failed"), tr("The update doesn't contain LuzLunar."));
        return;
    }

    // Only a build signed like this one keeps LuzLunar's permissions; anything else is refused
    QString error;
    if (!SelfUpdateMac::meetsOwnRequirement(app, &error)) {
        QDir(runDir(m_Latest.run)).removeRecursively();
        setState(QStringLiteral("failed"), tr("The update was refused: %1").arg(error));
        return;
    }

    m_ReadyApp = app;
    if (!m_Supported) {
        setState(QStringLiteral("ready"), tr("%1 is ready, but this build can't replace itself. Install it by hand once.").arg(latestVersion()));
    }
    else {
        setState(QStringLiteral("ready"), tr("%1 is ready to install.").arg(latestVersion()));
    }
}

void ForkUpdater::installNow()
{
    install(SelfUpdateMac::RelaunchFront);
}

void ForkUpdater::install(int relaunch)
{
    if (m_State != QStringLiteral("ready") || m_ReadyApp.isEmpty() || m_Installing) {
        return;
    }
    if (!m_Supported) {
        setState(QStringLiteral("ready"), tr("This build is signed ad hoc, so it can't check an update is LuzLunar's. Install the update by hand once."));
        return;
    }
    if (Session::get() != nullptr) {
        setState(QStringLiteral("ready"), tr("%1 installs once the stream ends.").arg(latestVersion()));
        return;
    }

    QString bundle = SelfUpdateMac::bundlePath();
    if (bundle.contains(QStringLiteral("/AppTranslocation/")) || !QFileInfo(QFileInfo(bundle).absolutePath()).isWritable()) {
        setState(QStringLiteral("ready"), tr("Move LuzLunar to the Applications folder, then install the update."));
        return;
    }

    QString error;
    if (!SelfUpdateMac::startSwap(updatesDir(), m_ReadyApp, m_Latest.run, static_cast<SelfUpdateMac::Relaunch>(relaunch), &error)) {
        setState(QStringLiteral("failed"), tr("Couldn't install the update: %1").arg(error));
        return;
    }
    m_Installing = true;
    setState(QStringLiteral("installing"), tr("Installing %1…").arg(latestVersion()));

    // The helper waits for LuzLunar to quit before it swaps the app
    if (relaunch != SelfUpdateMac::RelaunchNone) {
        QTimer::singleShot(0, qApp, &QCoreApplication::quit);
    }
}

void ForkUpdater::onQuit()
{
    // Automatic updates install as LuzLunar quits, without opening it again
    if (m_Automatic && !m_Installing && m_State == QStringLiteral("ready") && ForkUpdateRules::mayInstallAutomatically(m_Latest, m_Build, true)) {
        install(SelfUpdateMac::RelaunchNone);
    }
}

void ForkUpdater::onIdleTick()
{
    qint64 background = m_InactiveSince.isValid() ? m_InactiveSince.secsTo(QDateTime::currentDateTimeUtc()) : 0;
    bool ready = m_State == QStringLiteral("ready") && m_HaveLatest && ForkUpdateRules::mayInstallAutomatically(m_Latest, m_Build, true);
    if (ForkUpdateRules::shouldRestartWhileIdle(ready, m_Automatic, Session::get() != nullptr, background)) {
        install(SelfUpdateMac::RelaunchBackground);
    }
}

void ForkUpdater::openAppManagementSettings()
{
    SelfUpdateMac::openAppManagementSettings();
}
