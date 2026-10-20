#pragma once

#include <string>
#include <vector>

// [fork] The rules of showing this Mac as a network drive on the PC (macdrive.*), kept free of Qt
// and macOS so tests can build them alone: which shares Apollo is asked to try, whether a stream
// asks at all, and what Apollo's answer comes to.
namespace MacDriveRules
{
    // Apollo's "Network Drive" permission (client_drive), in its <Permission> bits
    constexpr long long k_PermClientDrive = 0x00400000;

    // The shares to ask for, in order: the whole disk, then the home folder. diskShare is File
    // Sharing's share of the startup disk, by its SMB name ("" when there's none). Without one, an
    // administrator gets macOS's own share of the startup volume, by the volume's name. userName is
    // the home folder's share. Empty names are left out, and none twice.
    std::vector<std::string> shares(const std::string& diskShare, bool admin, const std::string& volumeName,
                                    const std::string& userName);

    // What /serverinfo's <LuzMacDrive> says
    enum class HostSupport {
        Missing,    // an Apollo from before the Mac drive
        Off,        // fork_mac_drive is off, or Apollo doesn't run as its service
        On,
    };
    HostSupport hostSupport(const std::string& value);

    // Why a stream doesn't ask the PC for the drive
    enum class Skip {
        None,               // it asks
        Off,                // the setting is off (nothing to say)
        NotLan,             // the stream doesn't go over the LAN (nothing to say)
        HostTooOld,
        HostOff,
        NoPermission,       // Apollo doesn't give this Mac its Network Drive permission
        NoPassword,         // no Mac password saved in Settings
        PasswordChanged,    // the saved one doesn't open this account any more
        SharingOff,         // File Sharing is off on this Mac
    };

    struct Facts {
        bool enabled = false;
        bool viaLan = false;
        HostSupport host = HostSupport::Missing;
        long long permissions = -1;     // Apollo's <Permission> bits, or -1 if it didn't say
        bool passwordSaved = false;
        bool passwordValid = false;
        bool sharingOn = false;
    };

    Skip skip(const Facts& facts);

    // Whether a reason is worth telling: the setting being off or a stream away from home isn't
    bool silent(Skip reason);

    // Apollo's answer to POST or GET /actions/drive, as parsed
    struct Reply {
        int httpStatus = 0;     // 0 without an answer
        std::string state;      // "none", "mapping", "mapped", "failed"
        std::string letter;
        std::string share;
        bool added = false;
        std::string error;      // when failed, or Apollo's "error" for a refusal
        long long code = 0;
    };

    enum class Outcome {
        Pending,            // still being mapped
        Added,              // the drive is new, and the first share asked for
        AddedHome,          // the drive is new, but only a later share (the home folder) could be
        Kept,               // the drive from an earlier stream is still there
        WrongPassword,      // the Mac's File Sharing refused the account: Windows File Sharing is off for it
        NtlmBlocked,
        Denied,             // the account may not open the shares
        NoShare,
        Unreachable,
        Conflict,
        NoLetter,
        NobodySignedIn,
        Refused,            // Apollo refused the request (permission, not streaming, not the LAN)
        Failed,
    };

    Outcome outcome(const Reply& reply, const std::vector<std::string>& sent);

    // Whether the stream says so beside the notch: a drive kept from before isn't news
    bool worthTelling(Outcome outcome);
}
