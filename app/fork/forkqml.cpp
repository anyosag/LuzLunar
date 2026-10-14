// Registers the fork's QML types without touching upstream's main.cpp.

#include <QCoreApplication>
#include <QQmlEngine>

#include "forkpreferences.h"

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
    }
}

Q_COREAPP_STARTUP_FUNCTION(registerForkQmlTypes)
