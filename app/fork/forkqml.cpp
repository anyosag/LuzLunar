// Fork startup: the app's display name and the fork's QML types, without touching upstream's main.cpp.

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QUrl>

#include "clienthardware.h"
#include "forkaspectratios.h"
#include "forkhostpower.h"
#include "forkgrouplaunch.h"
#include "forkhostupdates.h"
#include "forkimacsetup.h"
#include "forkpreferences.h"
#include "forkupdater.h"
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

        // LuzLunar's colors and type (app/gui/ForkThemeData.qml)
        qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/gui/ForkThemeData.qml")), "ForkTheme", 1, 0, "ForkTheme");
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
        // Over-the-air updates of LuzLunar and of Apollo PCs (FORK.md, "Updates")
        qmlRegisterSingletonType<ForkUpdater>("ForkUpdater", 1, 0, "ForkUpdater",
                                              [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkUpdater* updater = ForkUpdater::get();
            QQmlEngine::setObjectOwnership(updater, QQmlEngine::CppOwnership);
            return updater;
        });
        qmlRegisterSingletonType<ForkHostUpdates>("ForkHostUpdates", 1, 0, "ForkHostUpdates",
                                                  [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkHostUpdates* updates = ForkHostUpdates::get();
            QQmlEngine::setObjectOwnership(updates, QQmlEngine::CppOwnership);
            return updates;
        });
        // Sleep PC, the pair to Wake PC, for Apollo PCs (FORK.md, "Sleep PC")
        qmlRegisterSingletonType<ForkHostPower>("ForkHostPower", 1, 0, "ForkHostPower",
                                                [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkHostPower* power = ForkHostPower::get();
            QQmlEngine::setObjectOwnership(power, QQmlEngine::CppOwnership);
            return power;
        });
        // Multi-display streams: the launch screen's displays and the iMac's route check
        qmlRegisterSingletonType<ForkGroupLaunch>("ForkGroupLaunch", 1, 0, "ForkGroupLaunch",
                                                  [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkGroupLaunch* launch = ForkGroupLaunch::get();
            QQmlEngine::setObjectOwnership(launch, QQmlEngine::CppOwnership);
            return launch;
        });
        // Multi-display streams: the iMac behind DisplayExtend, and pairing it with Apollo PCs
        qmlRegisterSingletonType<ForkImacSetup>("ForkImacSetup", 1, 0, "ForkImacSetup",
                                                [](QQmlEngine*, QJSEngine*) -> QObject* {
            ForkImacSetup* setup = ForkImacSetup::get();
            QQmlEngine::setObjectOwnership(setup, QQmlEngine::CppOwnership);
            return setup;
        });
    }
}

Q_COREAPP_STARTUP_FUNCTION(registerForkQmlTypes)
