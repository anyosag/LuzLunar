#include "macdriverules.h"

#include <algorithm>

namespace MacDriveRules
{
std::vector<std::string> shares(const std::string& diskShare, bool admin, const std::string& volumeName,
                                const std::string& userName)
{
    std::vector<std::string> list;
    auto add = [&list](const std::string& share) {
        if (!share.empty() && std::find(list.begin(), list.end(), share) == list.end()) {
            list.push_back(share);
        }
    };
    if (!diskShare.empty()) {
        add(diskShare);
    }
    else if (admin) {
        add(volumeName);
    }
    add(userName);
    return list;
}

HostSupport hostSupport(const std::string& value)
{
    if (value.empty()) {
        return HostSupport::Missing;
    }
    return value == "1" ? HostSupport::On : HostSupport::Off;
}

Skip skip(const Facts& facts)
{
    if (!facts.enabled) {
        return Skip::Off;
    }
    if (!facts.viaLan) {
        return Skip::NotLan;
    }
    if (facts.host == HostSupport::Missing) {
        return Skip::HostTooOld;
    }
    if (facts.host == HostSupport::Off) {
        return Skip::HostOff;
    }
    if (facts.permissions < 0 || (facts.permissions & k_PermClientDrive) == 0) {
        return Skip::NoPermission;
    }
    if (!facts.passwordSaved) {
        return Skip::NoPassword;
    }
    if (!facts.passwordValid) {
        return Skip::PasswordChanged;
    }
    if (!facts.sharingOn) {
        return Skip::SharingOff;
    }
    return Skip::None;
}

bool silent(Skip reason)
{
    return reason == Skip::None || reason == Skip::Off || reason == Skip::NotLan;
}

Outcome outcome(const Reply& reply, const std::vector<std::string>& sent)
{
    if (reply.httpStatus == 200 || reply.httpStatus == 202) {
        if (reply.state == "mapping") {
            return Outcome::Pending;
        }
        if (reply.state == "mapped") {
            if (!reply.added) {
                return Outcome::Kept;
            }
            return !sent.empty() && reply.share != sent.front() ? Outcome::AddedHome : Outcome::Added;
        }
        if (reply.state == "failed") {
            const std::string& error = reply.error;
            if (error == "logon") {
                return Outcome::WrongPassword;
            }
            if (error == "ntlm_blocked") {
                return Outcome::NtlmBlocked;
            }
            if (error == "denied") {
                return Outcome::Denied;
            }
            if (error == "no_share") {
                return Outcome::NoShare;
            }
            if (error == "unreachable") {
                return Outcome::Unreachable;
            }
            if (error == "conflict") {
                return Outcome::Conflict;
            }
            if (error == "no_letter") {
                return Outcome::NoLetter;
            }
            if (error == "no_user") {
                return Outcome::NobodySignedIn;
            }
        }
        return Outcome::Failed;
    }
    if (reply.httpStatus == 401 || reply.httpStatus == 403 || reply.httpStatus == 404) {
        return Outcome::Refused;
    }
    return Outcome::Failed;
}

bool worthTelling(Outcome outcome)
{
    return outcome != Outcome::Pending && outcome != Outcome::Kept;
}
}
