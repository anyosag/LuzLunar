#include "fork/mac/selfupdate_mac.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QProcess>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <Security/Security.h>

namespace
{
    // Waits for LuzLunar to quit, checks the new build starts (a bad signature gets it killed),
    // moves it into place keeping the previous build, and puts the previous build back if the new
    // one doesn't write its "started" marker after a relaunch. The next LuzLunar reads "result".
    const char k_SwapScript[] = R"SH(#!/bin/sh
# [fork] LuzLunar's update swap, written and started by app/fork/mac/selfupdate_mac.mm
pid="$1"; app="$2"; new="$3"; dir="$4"; run="$5"; relaunch="$6"
name=$(basename "$app")
previous="$dir/previous"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
exec >>"$dir/update.log" 2>&1
echo "$(date '+%Y-%m-%d %H:%M:%S') installing run $run over $app"

result() { echo "$1" > "$dir/result.tmp" && mv -f "$dir/result.tmp" "$dir/result"; }
reopen() { case "$relaunch" in 1) open "$app" ;; 2) open -g "$app" ;; esac; }

# The build's own --version exits 0; one macOS won't run is killed or fails
starts() {
  executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$1/Contents/Info.plist") || return 1
  perl -e 'alarm 60; exec @ARGV' "$1/Contents/MacOS/$executable" --version >/dev/null 2>&1
}

i=0
while kill -0 "$pid" 2>/dev/null; do
  i=$((i + 1))
  if [ $i -gt 600 ]; then echo "LuzLunar didn't quit"; result "failed quit"; exit 1; fi
  sleep 0.1
done

if ! starts "$new"; then echo "the new build doesn't start"; result "failed check"; reopen; exit 1; fi

rm -rf "$previous"
mkdir -p "$previous"
if ! mv "$app" "$previous/$name"; then
  echo "couldn't move $app aside"; result "failed move"; reopen; exit 1
fi
if ! mv "$new" "$app"; then
  echo "couldn't move the new build into place"; mv "$previous/$name" "$app"; result "failed move"; reopen; exit 1
fi
"$lsregister" -f "$app"
result "installed $run"
echo "installed"

[ "$relaunch" = 0 ] && exit 0
rm -f "$dir/started"
reopen
i=0
while [ ! -e "$dir/started" ]; do
  i=$((i + 1))
  if [ $i -gt 300 ]; then
    echo "the new build didn't start; putting the previous one back"
    pkill -f "$app/Contents/MacOS/"
    sleep 1
    rm -rf "$dir/failed.app"
    mv "$app" "$dir/failed.app" && mv "$previous/$name" "$app"
    "$lsregister" -f "$app"
    result "rolledback $run"
    reopen
    exit 1
  fi
  sleep 0.1
done
echo "the new build started"
)SH";

    QString describe(CFErrorRef error)
    {
        if (error == nullptr) {
            return QStringLiteral("unknown error");
        }
        CFStringRef description = CFErrorCopyDescription(error);
        QString text = QString::fromCFString(description);
        CFRelease(description);
        return text;
    }

    // The running app's static code, or null
    SecStaticCodeRef copySelfStaticCode()
    {
        SecCodeRef self = nullptr;
        if (SecCodeCopySelf(kSecCSDefaultFlags, &self) != errSecSuccess) {
            return nullptr;
        }
        SecStaticCodeRef staticCode = nullptr;
        OSStatus status = SecCodeCopyStaticCode(self, kSecCSDefaultFlags, &staticCode);
        CFRelease(self);
        return status == errSecSuccess ? staticCode : nullptr;
    }
}

namespace SelfUpdateMac
{
    QString bundlePath()
    {
        return QString::fromNSString([[NSBundle mainBundle] bundlePath]);
    }

    bool signedWithCertificate()
    {
        SecStaticCodeRef staticCode = copySelfStaticCode();
        if (staticCode == nullptr) {
            return false;
        }
        CFDictionaryRef info = nullptr;
        OSStatus status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &info);
        CFRelease(staticCode);
        if (status != errSecSuccess || info == nullptr) {
            return false;
        }
        // An ad-hoc signature has no certificates
        CFArrayRef certificates = (CFArrayRef)CFDictionaryGetValue(info, kSecCodeInfoCertificates);
        bool signedWithCertificate = certificates != nullptr && CFArrayGetCount(certificates) > 0;
        CFRelease(info);
        return signedWithCertificate;
    }

    bool meetsOwnRequirement(const QString& appPath, QString* error)
    {
        SecStaticCodeRef self = copySelfStaticCode();
        if (self == nullptr) {
            *error = QStringLiteral("couldn't read LuzLunar's own signature");
            return false;
        }
        SecRequirementRef requirement = nullptr;
        OSStatus status = SecCodeCopyDesignatedRequirement(self, kSecCSDefaultFlags, &requirement);
        CFRelease(self);
        if (status != errSecSuccess || requirement == nullptr) {
            *error = QStringLiteral("couldn't read LuzLunar's own signing requirement");
            return false;
        }

        NSURL* url = [NSURL fileURLWithPath:appPath.toNSString()];
        SecStaticCodeRef code = nullptr;
        status = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &code);
        if (status != errSecSuccess || code == nullptr) {
            CFRelease(requirement);
            *error = QStringLiteral("the download isn't an app");
            return false;
        }

        CFErrorRef cfError = nullptr;
        status = SecStaticCodeCheckValidityWithErrors(code, kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode,
                                                      requirement, &cfError);
        CFRelease(code);
        CFRelease(requirement);
        if (status != errSecSuccess) {
            *error = QStringLiteral("the new build isn't signed like this one: %1").arg(describe(cfError));
            if (cfError != nullptr) {
                CFRelease(cfError);
            }
            return false;
        }
        return true;
    }

    bool startSwap(const QString& updatesDir, const QString& newAppPath, qint64 run, Relaunch relaunch, QString* error)
    {
        QString script = QDir(updatesDir).filePath(QStringLiteral("swap.sh"));
        QFile file(script);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) || file.write(k_SwapScript) < 0) {
            *error = QStringLiteral("couldn't write the update helper");
            return false;
        }
        file.close();
        file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

        QStringList arguments = {
            script,
            QString::number(QCoreApplication::applicationPid()),
            bundlePath(),
            newAppPath,
            updatesDir,
            QString::number(run),
            QString::number(static_cast<int>(relaunch)),
        };
        if (!QProcess::startDetached(QStringLiteral("/bin/sh"), arguments)) {
            *error = QStringLiteral("couldn't start the update helper");
            return false;
        }
        return true;
    }

    void openAppManagementSettings()
    {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"]];
    }
}
