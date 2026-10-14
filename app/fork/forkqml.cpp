// Fork startup: the app's display name and the fork's QML types, without touching upstream's main.cpp.

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickWindow>

#include "clienthardware.h"
#include "forkaspectratios.h"
#include "forkpreferences.h"
#include "sfsymbols.h"
#include "streamprofiles.h"
#include "windowchrome.h"

namespace
{
    void registerForkQmlTypes()
    {
        // Only the name people see. The application name stays "Moonlight", because it locates
        // Moonlight's settings (paired PCs, preferences), which LuzLunar shares.
        QGuiApplication::setApplicationDisplayName(QStringLiteral("LuzLunar"));

#ifdef Q_OS_DARWIN
        // Windows need an alpha channel from the start for the translucent (Liquid Glass) window
        // background that ForkWindowChrome puts behind the main window's content
        QQuickWindow::setDefaultAlphaBuffer(true);
#endif

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
        qmlRegisterSingletonType<ForkSfSymbols>("SfSymbols", 1, 0, "SfSymbols",
                                                [](QQmlEngine* engine, QJSEngine*) -> QObject* {
            ForkSfSymbols* symbols = ForkSfSymbols::get(engine);
            QQmlEngine::setObjectOwnership(symbols, QQmlEngine::CppOwnership);
            return symbols;
        });
        qmlRegisterSingletonType<ClientHardware>("ClientHardware", 1, 0, "ClientHardware",
                                                 [](QQmlEngine*, QJSEngine*) -> QObject* {
            ClientHardware* hardware = ClientHardware::get();
            QQmlEngine::setObjectOwnership(hardware, QQmlEngine::CppOwnership);
            return hardware;
        });
        qmlRegisterSingletonType<AspectRatios>("AspectRatios", 1, 0, "AspectRatios",
                                               [](QQmlEngine*, QJSEngine*) -> QObject* {
            AspectRatios* ratios = AspectRatios::get();
            QQmlEngine::setObjectOwnership(ratios, QQmlEngine::CppOwnership);
            return ratios;
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
