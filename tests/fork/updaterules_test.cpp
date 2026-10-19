// Tests for app/fork/forkupdaterules.*: what a valid update manifest is, when an update installs,
// the swap helper's result file, and the signature check against a throwaway Ed25519 key.
//   clang++ -std=c++17 -Iapp/fork -I<openssl>/include tests/fork/updaterules_test.cpp \
//     app/fork/forkupdaterules.cpp -L<openssl>/lib -lcrypto

#include "forkupdaterules.h"
#include "updatekey.h"

#include <cstdio>
#include <string>

#include <openssl/evp.h>

using namespace ForkUpdateRules;

static int s_Failures = 0;

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++; \
        } \
    } while (0)

static const std::string k_Prefix = "https://github.com/anyosag/LuzLunar/releases/download/";

static Manifest goodManifest()
{
    Manifest m;
    m.product = "luzlunar";
    m.channel = "master";
    m.run = 200;
    m.version = "6.2.0-fork.ee5b3ba";
    m.commit = "0123456789abcdef0123456789abcdef01234567";
    m.published = "2026-10-18T20:00:00Z";
    m.notes = "Fix the thing";
    m.asset.name = "LuzLunar-macOS-arm64.zip";
    m.asset.url = k_Prefix + "luzlunar-b200/LuzLunar-macOS-arm64.zip";
    m.asset.sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    m.asset.size = 90 * 1024 * 1024;
    return m;
}

static bool valid(const Manifest& m)
{
    return validate(m, "luzlunar", k_Prefix, nullptr);
}

static void testValidate()
{
    std::string error;
    CHECK(validate(goodManifest(), "luzlunar", k_Prefix, &error));
    CHECK(error.empty());

    Manifest m;
    m = goodManifest(); m.product = "apollo"; CHECK(!valid(m));
    m = goodManifest(); m.channel = "branch"; CHECK(!valid(m));
    m = goodManifest(); m.run = 0; CHECK(!valid(m));
    m = goodManifest(); m.version = ""; CHECK(!valid(m));
    m = goodManifest(); m.version = "6.2\n0"; CHECK(!valid(m));
    m = goodManifest(); m.commit = "abc"; CHECK(!valid(m));
    m = goodManifest(); m.notes = std::string(5000, 'x'); CHECK(!valid(m));
    m = goodManifest(); m.asset.name = "../LuzLunar.zip"; CHECK(!valid(m));
    m = goodManifest(); m.asset.name = ".zip"; CHECK(!valid(m));
    m = goodManifest(); m.asset.url = "https://example.com/LuzLunar-macOS-arm64.zip"; CHECK(!valid(m));
    m = goodManifest(); m.asset.url = k_Prefix + "luzlunar-b200/Other.zip"; CHECK(!valid(m));
    m = goodManifest(); m.asset.url = k_Prefix + "../x/LuzLunar-macOS-arm64.zip"; CHECK(!valid(m));
    m = goodManifest(); m.asset.url = k_Prefix + "a/b/LuzLunar-macOS-arm64.zip"; CHECK(!valid(m));
    m = goodManifest(); m.asset.sha256 = "0123"; CHECK(!valid(m));
    m = goodManifest(); m.asset.sha256 = std::string(64, 'F'); CHECK(!valid(m));
    m = goodManifest(); m.asset.size = 0; CHECK(!valid(m));
    m = goodManifest(); m.asset.size = k_MaxAssetSize + 1; CHECK(!valid(m));

    CHECK(!validate(goodManifest(), "luzlunar", "https://github.com/someone/LuzLunar/releases/download/", &error));
    CHECK(!error.empty());
}

static void testOrdering()
{
    Manifest m = goodManifest();
    Build older{150, "master"};
    Build same{200, "master"};
    Build newer{250, "master"};
    Build branch{900, "branch"};
    Build local{0, "local"};

    CHECK(isUpdate(m, older));
    CHECK(!isUpdate(m, same));
    CHECK(!isUpdate(m, newer));
    CHECK(isUpdate(m, branch));
    CHECK(isUpdate(m, local));

    CHECK(mayInstallAutomatically(m, older, true));
    CHECK(!mayInstallAutomatically(m, older, false));
    CHECK(!mayInstallAutomatically(m, same, true));
    CHECK(!mayInstallAutomatically(m, branch, true));
    CHECK(!mayInstallAutomatically(m, local, true));
    CHECK(!(Build{0, "master"}.isMaster()));
}

static void testUrls()
{
    CHECK(allowedDownloadUrl("https://github.com/anyosag/LuzLunar/releases/latest/download/update.json"));
    CHECK(allowedDownloadUrl("https://objects.githubusercontent.com/github-production-release-asset/1?x=y"));
    CHECK(allowedDownloadUrl("https://release-assets.githubusercontent.com/x"));
    CHECK(!allowedDownloadUrl("http://github.com/x"));
    CHECK(!allowedDownloadUrl("https://github.com.evil.com/x"));
    CHECK(!allowedDownloadUrl("https://github.com@evil.com/x"));
    CHECK(!allowedDownloadUrl("https://github.com:444/x"));
    CHECK(!allowedDownloadUrl("https://evilgithubusercontent.com/x"));
    CHECK(!allowedDownloadUrl("file:///Applications/LuzLunar.app"));
    CHECK(allowedDownloadUrl(ForkUpdateKey::k_ManifestUrl));
    CHECK(allowedDownloadUrl(ForkUpdateKey::k_SignatureUrl));
    CHECK(std::string(ForkUpdateKey::k_AssetUrlPrefix) == k_Prefix);
}

static void testIdle()
{
    CHECK(shouldRestartWhileIdle(true, true, false, k_IdleSecondsBeforeRestart));
    CHECK(!shouldRestartWhileIdle(true, true, false, k_IdleSecondsBeforeRestart - 1));
    CHECK(!shouldRestartWhileIdle(true, true, true, 3600));
    CHECK(!shouldRestartWhileIdle(true, false, false, 3600));
    CHECK(!shouldRestartWhileIdle(false, true, false, 3600));
}

static void testSwapResult()
{
    auto installed = parseSwapResult("installed 200\n");
    CHECK(installed && installed->kind == SwapResult::Installed && installed->run == 200);
    auto rolledBack = parseSwapResult("rolledback 201");
    CHECK(rolledBack && rolledBack->kind == SwapResult::RolledBack && rolledBack->run == 201);
    auto failed = parseSwapResult("failed move\n");
    CHECK(failed && failed->kind == SwapResult::Failed && failed->reason == "move");
    CHECK(parseSwapResult("failed check").has_value());
    CHECK(parseSwapResult("failed quit").has_value());
    CHECK(!parseSwapResult("failed other").has_value());
    CHECK(!parseSwapResult("installed").has_value());
    CHECK(!parseSwapResult("installed abc").has_value());
    CHECK(!parseSwapResult("updated 5").has_value());
    CHECK(!parseSwapResult("").has_value());
}

static void testBase64()
{
    CHECK(decodeBase64("aGVsbG8=") == std::optional<std::string>("hello"));
    CHECK(decodeBase64("aGVsbA==") == std::optional<std::string>("hell"));
    CHECK(decodeBase64(" aGVs\n") == std::optional<std::string>("hel"));
    CHECK(!decodeBase64("aGVsbG8").has_value());
    CHECK(!decodeBase64("aG=sbG8=").has_value());
    CHECK(!decodeBase64("aGVsbG8=aGVs").has_value());
    CHECK(!decodeBase64("").has_value());
}

static void testSignature()
{
    // A throwaway key, signing the way CI does (openssl pkeyutl -sign -rawin)
    EVP_PKEY* key = nullptr;
    EVP_PKEY_CTX* kctx = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, nullptr);
    CHECK(kctx && EVP_PKEY_keygen_init(kctx) == 1 && EVP_PKEY_keygen(kctx, &key) == 1);
    EVP_PKEY_CTX_free(kctx);
    if (key == nullptr) {
        return;
    }
    std::array<uint8_t, 32> pub{};
    std::size_t pubSize = pub.size();
    CHECK(EVP_PKEY_get_raw_public_key(key, pub.data(), &pubSize) == 1 && pubSize == 32);

    std::string manifest = R"({"product":"luzlunar","run":200})";
    unsigned char sig[64];
    std::size_t sigSize = sizeof(sig);
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    CHECK(EVP_DigestSignInit(ctx, nullptr, nullptr, nullptr, key) == 1);
    CHECK(EVP_DigestSign(ctx, sig, &sigSize, (const unsigned char*)manifest.data(), manifest.size()) == 1);
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);

    unsigned char encoded[128] = {};
    EVP_EncodeBlock(encoded, sig, (int)sigSize);
    std::string sigFile = std::string((char*)encoded) + "\n";

    CHECK(verifyManifest(pub, manifest, sigFile));
    std::string tampered = manifest;
    tampered[3] ^= 1;
    CHECK(!verifyManifest(pub, tampered, sigFile));
    std::array<uint8_t, 32> otherKey = pub;
    otherKey[5] ^= 1;
    CHECK(!verifyManifest(otherKey, manifest, sigFile));
    CHECK(!verifyManifest(pub, manifest, "garbage"));
    CHECK(!verifyEd25519(pub, manifest, "short"));
    // Not signed by LuzLunar's real key
    CHECK(!verifyManifest(ForkUpdateKey::k_PublicKey, manifest, sigFile));
}

int main()
{
    testValidate();
    testOrdering();
    testUrls();
    testIdle();
    testSwapResult();
    testBase64();
    testSignature();

    if (s_Failures == 0) {
        std::printf("updaterules: all tests passed\n");
        return 0;
    }
    std::printf("updaterules: %d failure(s)\n", s_Failures);
    return 1;
}
