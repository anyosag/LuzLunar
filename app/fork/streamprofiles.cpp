#include "streamprofiles.h"

#include <QMetaProperty>
#include <QReadLocker>
#include <QSettings>

#include "backend/computermanager.h"
#include "backend/nvapp.h"
#include "backend/nvcomputer.h"
#include "forkaspect.h"
#include "settings/streamingpreferences.h"
#include "streaming/session.h"
#include "SDL_compat.h"

#define SER_PROFILES "fork/profiles"

namespace
{
    // Keys whose values are booleans; the rest are integers (including the codec enum)
    const QStringList k_BoolKeys = {
        "enableHdr", "enableYUV444", "absoluteMouseMode", "enableVsync", "framePacing", "fullscreenStretch",
    };

    QString groupFor(const QString& hostUuid, const QString& appName)
    {
        // Hex-encode the app name so characters like '/' can't break the settings path
        return QString(SER_PROFILES "/%1/%2").arg(hostUuid, QString::fromLatin1(appName.toUtf8().toHex()));
    }

    QVariant typedValue(const QString& key, const QVariant& value)
    {
        return k_BoolKeys.contains(key) ? QVariant(value.toBool()) : QVariant(value.toInt());
    }

    // Copies every writable property plus the members that have no writable property
    void copyPreferences(const StreamingPreferences* from, StreamingPreferences* to)
    {
        const QMetaObject* metaObject = from->metaObject();
        for (int i = metaObject->propertyOffset(); i < metaObject->propertyCount(); i++) {
            QMetaProperty property = metaObject->property(i);
            if (property.isWritable()) {
                property.write(to, property.read(from));
            }
        }

        to->packetSize = from->packetSize;
        to->recommendedFullScreenMode = from->recommendedFullScreenMode;
    }
}

StreamProfiles* StreamProfiles::get()
{
    static StreamProfiles* s_Instance = new StreamProfiles();
    return s_Instance;
}

StreamProfiles::StreamProfiles(QObject* parent)
    : QObject(parent)
{
}

const QStringList& StreamProfiles::overridableKeys()
{
    static const QStringList keys = {
        "videoCodecConfig", "enableHdr", "enableYUV444", "absoluteMouseMode", "enableVsync", "framePacing",
        "fullscreenStretch", "width", "height", "fps", "bitrateKbps",
    };
    return keys;
}

QString StreamProfiles::hostUuid(QObject* computerManager, int computerIndex) const
{
    auto manager = qobject_cast<ComputerManager*>(computerManager);
    if (manager == nullptr) {
        return QString();
    }

    QVector<NvComputer*> computers = manager->getComputers();
    if (computerIndex < 0 || computerIndex >= computers.count()) {
        return QString();
    }

    NvComputer* computer = computers.at(computerIndex);
    QReadLocker lock(&computer->lock);
    return computer->uuid;
}

QVariantMap StreamProfiles::profile(const QString& hostUuid, const QString& appName) const
{
    QVariantMap profile;
    if (hostUuid.isEmpty()) {
        return profile;
    }

    QSettings settings;
    settings.beginGroup(groupFor(hostUuid, appName));
    for (const QString& key : overridableKeys()) {
        if (settings.contains(key)) {
            profile.insert(key, typedValue(key, settings.value(key)));
        }
    }
    return profile;
}

void StreamProfiles::saveProfile(const QString& hostUuid, const QString& appName, const QVariantMap& profile)
{
    if (hostUuid.isEmpty()) {
        return;
    }

    QSettings settings;
    settings.remove(groupFor(hostUuid, appName));
    settings.beginGroup(groupFor(hostUuid, appName));
    for (const QString& key : overridableKeys()) {
        QVariant value = profile.value(key);
        if (value.isValid() && !value.isNull()) {
            settings.setValue(key, typedValue(key, value));
        }
    }
}

Session* StreamProfiles::createSession(NvComputer* computer, NvApp& app, StreamingPreferences* cliPreferences)
{
    QString hostUuid;
    {
        QReadLocker lock(&computer->lock);
        hostUuid = computer->uuid;
    }

    // A new StreamingPreferences loads the saved global settings
    StreamingPreferences* prefs = new StreamingPreferences(nullptr);
    QVariantMap saved;
    for (const QString& key : overridableKeys()) {
        saved.insert(key, prefs->property(key.toUtf8().constData()));
    }

    // Start from the settings this stream would use without a profile
    copyPreferences(cliPreferences ? cliPreferences : StreamingPreferences::get(), prefs);

    QVariantMap profile = get()->profile(hostUuid, app.name);
    int defaultBitrate = StreamingPreferences::getDefaultBitrate(prefs->width, prefs->height, prefs->fps, prefs->enableYUV444);
    bool usingDefaultBitrate = prefs->bitrateKbps == defaultBitrate;
    bool bitrateInputsChanged = false;
    QStringList applied, keptFromCommandLine;

    for (auto it = profile.cbegin(); it != profile.cend(); ++it) {
        QByteArray name = it.key().toUtf8();

        // A value that differs from the saved setting here was set by a command line flag
        if (cliPreferences && prefs->property(name.constData()) != saved.value(it.key())) {
            keptFromCommandLine.append(it.key());
            continue;
        }

        if (prefs->setProperty(name.constData(), it.value())) {
            applied.append(QString("%1=%2").arg(it.key(), it.value().toString()));
            if (it.key() == "width" || it.key() == "height" || it.key() == "fps" || it.key() == "enableYUV444") {
                bitrateInputsChanged = true;
            }
        }
    }

    // Apollo makes its virtual display at exactly this size, and moonlight-common-c only rounds
    // the height to even after the launch request, so send even sizes (a command line size can
    // be odd)
    int evenWidth = ForkAspect::evenDown(prefs->width);
    int evenHeight = ForkAspect::evenDown(prefs->height);
    if ((evenWidth != prefs->width || evenHeight != prefs->height) && evenWidth > 0 && evenHeight > 0) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Rounded the stream size %dx%d to %dx%d",
                    prefs->width, prefs->height, evenWidth, evenHeight);
        prefs->width = evenWidth;
        prefs->height = evenHeight;
    }

    // Scale the bitrate with a profile's resolution or frame rate, unless a custom bitrate is in use
    if (bitrateInputsChanged && usingDefaultBitrate && !profile.contains("bitrateKbps") &&
            !keptFromCommandLine.contains("bitrateKbps")) {
        prefs->bitrateKbps = StreamingPreferences::getDefaultBitrate(prefs->width, prefs->height, prefs->fps, prefs->enableYUV444);
        applied.append(QString("bitrateKbps=%1 (default for the profile's resolution)").arg(prefs->bitrateKbps));
    }

    if (!applied.isEmpty() || !keptFromCommandLine.isEmpty()) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[fork] Stream profile for \"%s\": %s%s%s",
                    qPrintable(app.name),
                    qPrintable(applied.join(' ')),
                    keptFromCommandLine.isEmpty() ? "" : " | command line kept: ",
                    qPrintable(keptFromCommandLine.join(' ')));
    }

    Session* session = new Session(computer, app, prefs);
    prefs->setParent(session);
    return session;
}
