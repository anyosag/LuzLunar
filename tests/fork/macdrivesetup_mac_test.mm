// Tests for app/fork/mac/macdrivesetup_mac.mm on the Mac running them: the account, File Sharing,
// what it shares, and a keychain item of the tests' own. A standalone program for the fork's CI:
//   clang++ -std=c++17 -Wall -Wextra -Iapp tests/fork/macdrivesetup_mac_test.mm app/fork/mac/macdrivesetup_mac.mm
//       -framework Foundation -framework AppKit -framework OpenDirectory -framework Security -framework SystemConfiguration

#include "fork/mac/macdrivesetup.h"

#include <cstdio>
#include <string>

#include <unistd.h>

#include <Security/Security.h>

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static const char* sharingName(MacDriveSetup::WindowsSharing sharing)
{
    switch (sharing) {
    case MacDriveSetup::WindowsSharing::On:
        return "on";
    case MacDriveSetup::WindowsSharing::Off:
        return "off";
    case MacDriveSetup::WindowsSharing::Unknown:
        break;
    }
    return "unknown";
}

int main()
{
    std::string user = MacDriveSetup::userName();
    std::string computer = MacDriveSetup::computerName();
    std::string volume = MacDriveSetup::startupVolumeName();
    CHECK(!user.empty());
    CHECK(!computer.empty());
    CHECK(!volume.empty());

    // What this Mac has; CI's runner has File Sharing off and no share of its disk
    std::string disk = MacDriveSetup::diskShareName();
    std::printf("account %s (%s), computer \"%s\", startup volume \"%s\", File Sharing %s, disk share \"%s\", Windows File Sharing %s\n",
                user.c_str(), MacDriveSetup::isAdmin() ? "administrator" : "standard", computer.c_str(), volume.c_str(),
                MacDriveSetup::fileSharingOn() ? "on" : "off", disk.c_str(), sharingName(MacDriveSetup::windowsSharing()));

    // Never a password that isn't the account's
    CHECK(!MacDriveSetup::verifyPassword(""));
    CHECK(!MacDriveSetup::verifyPassword("not the password of this account " + std::to_string(getpid())));

    // A keychain item of the tests' own, never the real one, and no keychain prompt on a CI runner:
    // a locked keychain fails instead
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    SecKeychainSetUserInteractionAllowed(false);
#pragma clang diagnostic pop
    MacDriveSetup::setKeychainServiceForTests("LuzLunar Mac drive test " + std::to_string(getpid()));
    MacDriveSetup::forgetPassword();
    CHECK(!MacDriveSetup::hasPassword());
    CHECK(MacDriveSetup::loadPassword().empty());
    CHECK(!MacDriveSetup::savePassword(""));
    if (MacDriveSetup::savePassword("sp ace \"quote\" ñ€")) {
        CHECK(MacDriveSetup::hasPassword());
        CHECK(MacDriveSetup::loadPassword() == "sp ace \"quote\" ñ€");
        CHECK(MacDriveSetup::savePassword("second"));
        CHECK(MacDriveSetup::loadPassword() == "second");
        MacDriveSetup::forgetPassword();
        CHECK(!MacDriveSetup::hasPassword());
        CHECK(MacDriveSetup::loadPassword().empty());
    }
    else {
        std::printf("the keychain refused a new item here; skipped its round trip\n");
    }

    if (s_Failures == 0) {
        std::printf("macdrivesetup: all tests passed\n");
        return 0;
    }
    std::printf("macdrivesetup: %d failure(s)\n", s_Failures);
    return 1;
}
