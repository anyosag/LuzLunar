#include "forkupdaterules.h"

#include <memory>

#include <openssl/evp.h>

namespace ForkUpdateRules
{
    namespace
    {
        bool isLowerHex(std::string_view s, std::size_t length)
        {
            if (s.size() != length) {
                return false;
            }
            for (char c : s) {
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
                    return false;
                }
            }
            return true;
        }

        // A file name with no path in it: letters, digits, '.', '_' and '-', not starting with '.'
        bool isPlainFileName(std::string_view s)
        {
            if (s.empty() || s.size() > 128 || s.front() == '.') {
                return false;
            }
            for (char c : s) {
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '.' || c == '_' || c == '-')) {
                    return false;
                }
            }
            return true;
        }

        // Printable ASCII, so a version or date can't carry control characters into the UI
        bool isPrintable(std::string_view s)
        {
            for (char c : s) {
                if (c < 0x20 || c > 0x7e) {
                    return false;
                }
            }
            return true;
        }

        bool fail(std::string* error, const char* message)
        {
            if (error) {
                *error = message;
            }
            return false;
        }

        int base64Value(char c)
        {
            if (c >= 'A' && c <= 'Z') return c - 'A';
            if (c >= 'a' && c <= 'z') return c - 'a' + 26;
            if (c >= '0' && c <= '9') return c - '0' + 52;
            if (c == '+') return 62;
            if (c == '/') return 63;
            return -1;
        }

        bool isSpace(char c)
        {
            return c == ' ' || c == '\t' || c == '\r' || c == '\n';
        }
    }

    bool validate(const Manifest& m, std::string_view product, std::string_view urlPrefix, std::string* error)
    {
        if (m.product != product) {
            return fail(error, "the manifest is for another product");
        }
        if (m.channel != "master") {
            return fail(error, "the manifest isn't for a master build");
        }
        if (m.run <= 0) {
            return fail(error, "the manifest has no run number");
        }
        if (m.version.empty() || m.version.size() > 64 || !isPrintable(m.version)) {
            return fail(error, "the manifest has no valid version");
        }
        if (!isLowerHex(m.commit, 40)) {
            return fail(error, "the manifest has no valid commit");
        }
        if (m.published.size() > 64 || !isPrintable(m.published)) {
            return fail(error, "the manifest has no valid date");
        }
        if (m.notes.size() > 4000) {
            return fail(error, "the manifest's notes are too long");
        }
        if (!isPlainFileName(m.asset.name)) {
            return fail(error, "the asset's name isn't a plain file name");
        }
        // <prefix><tag>/<name>, where the tag is a plain name too
        std::string_view url = m.asset.url;
        if (url.size() > 512 || !isPrintable(url) || url.substr(0, urlPrefix.size()) != urlPrefix) {
            return fail(error, "the asset isn't from this repository's releases");
        }
        std::string_view rest = url.substr(urlPrefix.size());
        std::size_t slash = rest.find('/');
        if (slash == std::string_view::npos || !isPlainFileName(rest.substr(0, slash)) || rest.substr(slash + 1) != m.asset.name) {
            return fail(error, "the asset's address doesn't match its name");
        }
        if (!isLowerHex(m.asset.sha256, 64)) {
            return fail(error, "the asset has no valid SHA-256");
        }
        if (m.asset.size == 0 || m.asset.size > k_MaxAssetSize) {
            return fail(error, "the asset's size is missing or too large");
        }
        return true;
    }

    bool isUpdate(const Manifest& m, const Build& running)
    {
        return !running.isMaster() || m.run > running.run;
    }

    bool mayInstallAutomatically(const Manifest& m, const Build& running, bool automatic)
    {
        return automatic && running.isMaster() && m.run > running.run;
    }

    bool allowedDownloadUrl(std::string_view url)
    {
        constexpr std::string_view scheme = "https://";
        if (url.substr(0, scheme.size()) != scheme) {
            return false;
        }
        std::string_view rest = url.substr(scheme.size());
        std::string_view host = rest.substr(0, rest.find_first_of("/?#"));
        // No user info or port, so "github.com@elsewhere" or "github.com:1234" can't get through
        if (host.empty() || host.find_first_of("@:") != std::string_view::npos) {
            return false;
        }
        constexpr std::string_view assets = ".githubusercontent.com";
        return host == "github.com" ||
               (host.size() > assets.size() && host.substr(host.size() - assets.size()) == assets);
    }

    std::optional<std::string> decodeBase64(std::string_view text)
    {
        while (!text.empty() && isSpace(text.front())) {
            text.remove_prefix(1);
        }
        while (!text.empty() && isSpace(text.back())) {
            text.remove_suffix(1);
        }
        if (text.empty() || text.size() % 4 != 0) {
            return std::nullopt;
        }

        std::string out;
        out.reserve(text.size() / 4 * 3);
        for (std::size_t i = 0; i < text.size(); i += 4) {
            int v[4];
            int padding = 0;
            for (int j = 0; j < 4; j++) {
                char c = text[i + j];
                // Padding only at the very end: "xx==" or "xxx="
                if (c == '=' && i + 4 == text.size() && j >= 2 && (j == 3 || text[i + 3] == '=')) {
                    v[j] = 0;
                    padding++;
                    continue;
                }
                v[j] = base64Value(c);
                if (v[j] < 0 || padding > 0) {
                    return std::nullopt;
                }
            }
            uint32_t triple = (uint32_t)v[0] << 18 | (uint32_t)v[1] << 12 | (uint32_t)v[2] << 6 | (uint32_t)v[3];
            out += (char)(triple >> 16);
            if (padding < 2) {
                out += (char)(triple >> 8);
            }
            if (padding < 1) {
                out += (char)triple;
            }
        }
        return out;
    }

    bool verifyEd25519(const std::array<uint8_t, 32>& key, std::string_view message, std::string_view signature)
    {
        if (signature.size() != 64) {
            return false;
        }
        std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> pkey(
            EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr, key.data(), key.size()), EVP_PKEY_free);
        std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> ctx(EVP_MD_CTX_new(), EVP_MD_CTX_free);
        if (!pkey || !ctx || EVP_DigestVerifyInit(ctx.get(), nullptr, nullptr, nullptr, pkey.get()) != 1) {
            return false;
        }
        return EVP_DigestVerify(ctx.get(), (const unsigned char*)signature.data(), signature.size(),
                                (const unsigned char*)message.data(), message.size()) == 1;
    }

    bool verifyManifest(const std::array<uint8_t, 32>& key, std::string_view manifest, std::string_view signatureFile)
    {
        std::optional<std::string> signature = decodeBase64(signatureFile);
        return signature && verifyEd25519(key, manifest, *signature);
    }

    bool shouldRestartWhileIdle(bool ready, bool automatic, bool streaming, int64_t backgroundSeconds)
    {
        return ready && automatic && !streaming && backgroundSeconds >= k_IdleSecondsBeforeRestart;
    }

    std::optional<SwapResult> parseSwapResult(std::string_view text)
    {
        while (!text.empty() && isSpace(text.back())) {
            text.remove_suffix(1);
        }
        std::size_t space = text.find(' ');
        if (space == std::string_view::npos) {
            return std::nullopt;
        }
        std::string_view word = text.substr(0, space);
        std::string_view value = text.substr(space + 1);

        SwapResult result;
        if (word == "failed") {
            if (value != "quit" && value != "move" && value != "check") {
                return std::nullopt;
            }
            result.kind = SwapResult::Failed;
            result.reason = std::string(value);
            return result;
        }

        if (value.empty() || value.size() > 18 || value.find_first_not_of("0123456789") != std::string_view::npos) {
            return std::nullopt;
        }
        result.run = std::stoll(std::string(value));
        if (word == "installed") {
            result.kind = SwapResult::Installed;
        }
        else if (word == "rolledback") {
            result.kind = SwapResult::RolledBack;
        }
        else {
            return std::nullopt;
        }
        return result;
    }
}
