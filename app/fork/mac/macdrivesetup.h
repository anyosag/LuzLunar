#pragma once

#include <string>

// [fork] What showing this Mac as a drive on the PC (macdrive.*) needs from macOS: the account,
// File Sharing and what it shares, and the account's password, kept in the login keychain.
// Thread-safe; nothing here asks for a permission.
namespace MacDriveSetup
{
    enum class WindowsSharing {
        Unknown,
        On,     // the account keeps the hash Windows' NTLM sign-in needs
        Off,    // it doesn't: Windows File Sharing isn't on for it
    };

#ifdef __APPLE__
    // The account's short name, which is also its home folder's share
    std::string userName();

    // Like "Gonzalo's MacBook Pro", for Explorer's name of the drive
    std::string computerName();

    // A member of the admin group, which macOS shares every volume with
    bool isAdmin();

    // File Sharing answers on the SMB port (445)
    bool fileSharingOn();

    // A File Sharing share of the startup disk, by its SMB name; empty without one
    std::string diskShareName();

    // The startup volume's name, like "Macintosh HD"
    std::string startupVolumeName();

    // From the account's authentication record; a hint only
    WindowsSharing windowsSharing();

    // Whether password opens this account
    bool verifyPassword(const std::string& password);

    // The account's password in the login keychain, for LuzLunar only
    bool savePassword(const std::string& password);
    std::string loadPassword();     // empty without one
    bool hasPassword();             // without reading it
    void forgetPassword();

    // System Settings › General › Sharing
    void openSharingSettings();

    // Tests keep their keychain item apart from the real one
    void setKeychainServiceForTests(const std::string& service);
#else
    inline std::string userName() { return std::string(); }
    inline std::string computerName() { return std::string(); }
    inline bool isAdmin() { return false; }
    inline bool fileSharingOn() { return false; }
    inline std::string diskShareName() { return std::string(); }
    inline std::string startupVolumeName() { return std::string(); }
    inline WindowsSharing windowsSharing() { return WindowsSharing::Unknown; }
    inline bool verifyPassword(const std::string&) { return false; }
    inline bool savePassword(const std::string&) { return false; }
    inline std::string loadPassword() { return std::string(); }
    inline bool hasPassword() { return false; }
    inline void forgetPassword() {}
    inline void openSharingSettings() {}
    inline void setKeychainServiceForTests(const std::string&) {}
#endif
}
