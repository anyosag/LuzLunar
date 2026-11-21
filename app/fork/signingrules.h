#pragma once

#include <string>
#include <string_view>

// Which signatures an over-the-air update may carry (mac/selfupdate_mac.mm checks them), apart
// from macOS so it can be unit tested (tests/fork/signingrules_test.cpp).
//
// A build is accepted when it meets the running build's own designated requirement (the same
// certificate), or, when the build was given an Apple Team ID (LUZLUNAR_TEAM_ID, see FORK.md,
// "Updates"), when it's signed by that team through Apple's certificate authority. That second
// requirement lets a LuzLunar signed with the self-signed certificate move to an Apple-issued one
// (Apple Development or Developer ID) over the air. macOS's Local Network permission tracks
// identity reliably only for Apple-issued signatures (TN3179), so with one an update no longer
// shows up as a new app in Privacy & Security › Local Network.
namespace SigningRules
{
    // A Team ID: 10 characters, A-Z and 0-9
    inline bool validTeamId(std::string_view team)
    {
        if (team.size() != 10) {
            return false;
        }
        for (char c : team) {
            if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) {
                return false;
            }
        }
        return true;
    }

    // A bundle's signing identifier, like com.moonlight-stream.Moonlight: letters, digits, '.', '-'
    // and '_', so it can be quoted in a requirement as is
    inline bool validIdentifier(std::string_view identifier)
    {
        if (identifier.empty() || identifier.size() > 255) {
            return false;
        }
        for (char c : identifier) {
            if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_')) {
                return false;
            }
        }
        return true;
    }

    // The code requirement for the same identifier signed by team through Apple; empty when
    // either is invalid, so nothing extra is accepted
    inline std::string teamRequirement(std::string_view identifier, std::string_view team)
    {
        if (!validIdentifier(identifier) || !validTeamId(team)) {
            return std::string();
        }
        return "anchor apple generic and identifier \"" + std::string(identifier) +
               "\" and certificate leaf[subject.OU] = \"" + std::string(team) + "\"";
    }
}
