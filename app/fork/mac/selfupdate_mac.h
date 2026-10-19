#pragma once

#include <QString>

// [fork] LuzLunar replacing itself with a downloaded build (forkupdater.cpp): code signature checks
// and the helper that swaps the app bundle once LuzLunar has quit.
namespace SelfUpdateMac
{
    // How the swap helper opens the new build afterwards
    enum Relaunch {
        RelaunchNone = 0,       // LuzLunar was quit on purpose
        RelaunchFront = 1,      // Install and restart
        RelaunchBackground = 2, // an automatic restart while LuzLunar was in the background
    };

#ifdef Q_OS_DARWIN
    // The running app's bundle, e.g. /Applications/LuzLunar.app
    QString bundlePath();

    // Whether this build is signed with a certificate rather than ad hoc, so a downloaded build can
    // be held to the same signer
    bool signedWithCertificate();

    // Whether the bundle at appPath is validly signed and meets this app's designated requirement:
    // the same bundle ID and signing certificate, so macOS keeps its permissions (Accessibility)
    bool meetsOwnRequirement(const QString& appPath, QString* error);

    // Start the swap helper. It waits for this process to exit, checks the new build starts, moves
    // it into the running app's place (keeping the previous one in updatesDir/previous), and puts
    // the previous one back if the new one doesn't start. Its result goes to updatesDir/result.
    bool startSwap(const QString& updatesDir, const QString& newAppPath, qint64 run, Relaunch relaunch, QString* error);

    // Privacy & Security › App Management, which macOS may require before an app can replace itself
    void openAppManagementSettings();
#else
    inline QString bundlePath() { return QString(); }
    inline bool signedWithCertificate() { return false; }
    inline bool meetsOwnRequirement(const QString&, QString* error) { *error = QStringLiteral("updates are only for macOS"); return false; }
    inline bool startSwap(const QString&, const QString&, qint64, Relaunch, QString* error) { *error = QStringLiteral("updates are only for macOS"); return false; }
    inline void openAppManagementSettings() {}
#endif
}
