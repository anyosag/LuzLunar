// Registers the fork's QML types without touching upstream's main.cpp.

#include <QCoreApplication>
#include <QQmlEngine>

#include "forkpreferences.h"
#include "streamprofiles.h"

namespace
{
    void registerForkQmlTypes()
    {
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
    }
}

Q_COREAPP_STARTUP_FUNCTION(registerForkQmlTypes)
