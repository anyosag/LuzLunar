#pragma once

#include <QObject>
#include <QVariantMap>

class NvApp;
class NvComputer;
class Session;
class StreamingPreferences;

// Per-app stream settings ("profiles") that override the global settings for one app, e.g.
// HEVC 4:4:4 for an office desktop and AV1 HDR for games. Profiles are keyed by host and app
// name (Apollo changes app IDs when an app's name or image changes) and are stored under
// "fork/profiles" in Moonlight's settings. A field missing from a profile uses the global setting.
class StreamProfiles : public QObject
{
    Q_OBJECT

public:
    static StreamProfiles* get();

    // The settings a profile can override, named like the StreamingPreferences properties
    static const QStringList& overridableKeys();

    Q_INVOKABLE QString hostUuid(QObject* computerManager, int computerIndex) const;
    Q_INVOKABLE QVariantMap profile(const QString& hostUuid, const QString& appName) const;
    Q_INVOKABLE void saveProfile(const QString& hostUuid, const QString& appName, const QVariantMap& profile);

    // Creates the Session for an app with the app's profile applied to a private copy of the
    // settings; the global settings are never changed. Command line flags win over the
    // profile: pass the preferences the command line changed as cliPreferences.
    static Session* createSession(NvComputer* computer, NvApp& app, StreamingPreferences* cliPreferences = nullptr);

private:
    explicit StreamProfiles(QObject* parent = nullptr);
};
