#pragma once

// The rules of LuzLunar's over-the-air updates, apart from Qt and any I/O (forkupdater.cpp does
// the rest): what a valid manifest is, whether it's an update, when it installs, and the checks on
// its signature. Apollo has the same rules (anyosag/Apollo src/fork/update_manifest.h).
//
// A manifest is the update.json CI publishes with each master build (FORK.md, "Updates"):
//   {"product": "luzlunar", "channel": "master", "run": 123, "version": "6.2.0-fork.ee5b3ba",
//    "commit": "<40 hex>", "published": "2026-10-18T20:00:00Z", "notes": "<commit subject>",
//    "asset": {"name": "LuzLunar-macOS-arm64.zip", "url": "https://github.com/...",
//              "sha256": "<64 hex>", "size": 12345678}}

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace ForkUpdateRules
{
    // The largest app zip and manifest an update may download
    inline constexpr uint64_t k_MaxAssetSize = 500ull * 1024 * 1024;
    inline constexpr std::size_t k_MaxManifestSize = 64 * 1024;

    // The running build, from the CI run that built it
    struct Build {
        int64_t run = 0;        // the workflow run number; 0 for a local build
        std::string channel;    // "master" for a build of a push to master

        bool isMaster() const { return channel == "master" && run > 0; }
    };

    struct Asset {
        std::string name;
        std::string url;
        std::string sha256;     // lowercase hex
        uint64_t size = 0;
    };

    struct Manifest {
        std::string product;
        std::string channel;
        int64_t run = 0;
        std::string version;
        std::string commit;
        std::string published;
        std::string notes;
        Asset asset;
    };

    // Whether every field of a manifest whose signature checked out is as it must be
    bool validate(const Manifest& m, std::string_view product, std::string_view urlPrefix, std::string* error);

    // A newer master build, or any master build when a branch or local build runs
    bool isUpdate(const Manifest& m, const Build& running);

    // Only a newer master build over a master build, so a build installed on purpose stays until clicked
    bool mayInstallAutomatically(const Manifest& m, const Build& running, bool automatic);

    // HTTPS to GitHub or the hosts GitHub serves release assets from, for downloads and their redirects
    bool allowedDownloadUrl(std::string_view url);

    // Strict, padded base64, ignoring surrounding whitespace
    std::optional<std::string> decodeBase64(std::string_view text);

    // A raw 64-byte Ed25519 signature over message, with a raw 32-byte public key
    bool verifyEd25519(const std::array<uint8_t, 32>& key, std::string_view message, std::string_view signature);

    // A manifest against its .sig file (base64 of the signature)
    bool verifyManifest(const std::array<uint8_t, 32>& key, std::string_view manifest, std::string_view signatureFile);

    // How long LuzLunar must have been in the background, with no stream, before it restarts into
    // an update by itself
    inline constexpr int64_t k_IdleSecondsBeforeRestart = 10 * 60;

    // With automatic updates on: restart into a ready update now?
    bool shouldRestartWhileIdle(bool ready, bool automatic, bool streaming, int64_t backgroundSeconds);

    // What the swap helper (mac/selfupdate_mac.mm) left in its result file
    struct SwapResult {
        enum Kind { Installed, RolledBack, Failed };
        Kind kind = Failed;
        int64_t run = 0;        // the update's run, for Installed and RolledBack
        std::string reason;     // for Failed: "quit", "move" or "check"
    };

    // "installed 123", "rolledback 123", "failed move"
    std::optional<SwapResult> parseSwapResult(std::string_view text);
}
