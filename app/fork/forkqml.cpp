// Fork startup: the app's display name and the fork's QML types, without touching upstream's main.cpp.

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlEngine>

#include "forkpreferences.h"
#include "streamprofiles.h"
#include "windowchrome.h"

namespace
{
    void registerForkQmlTypes()
    {
        // Only the name people see. The application name stays "Moonlight", because it locates
        // Moonlight's settings (paired PCs, preferences), which LuzLunar shares.
        QGuiApplication::setApplicationDisplayName(QStringLiteral("LuzLunar"));

        qmlRegisterSingletonType<ForkPreferences>("ForkPreferences", 1, 0, "ForkPreferences",
                                                  [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkPreferences* prefs = ForkPreferences::get();
            QQmlEngine::setObjectOwnership(prefs, QQmlEngine::CppOwnership);
            return prefs;
        });
        qmlRegisterSingletonType<StreamProfiles>("StreamProfiles", 1, 0, "StreamProfiles",
                                                 [](QQmlEngine*, QJSEngine*) -> QObject* {
            StreamProfiles* profiles = StreamProfiles::get();
            QQmlEngine::setObjectOwnership(profiles, QQmlEngine::CppOwnership);
            return profiles;
        });
        qmlRegisterSingletonType<ForkWindowChrome>("WindowChrome", 1, 0, "WindowChrome",
                                                   [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkWindowChrome* chrome = ForkWindowChrome::get();
            QQmlEngine::setObjectOwnership(chrome, QQmlEngine::CppOwnership);
            return chrome;
        });
    }
}

Q_COREAPP_STARTUP_FUNCTION(registerForkQmlTypes)
