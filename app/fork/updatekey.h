#pragma once

// Where LuzLunar's over-the-air updates come from, and the key they must be signed with.
//
// CI's publish job (.github/workflows/fork-macos.yml) signs each master build's update.json with
// the Ed25519 key in the `release` environment's FORK_UPDATE_KEY secret. Apollo checks its own
// updates against the same public key (anyosag/Apollo src/fork/update_key.h). See FORK.md, "Updates".

#include <array>
#include <cstdint>
#include <string_view>

namespace ForkUpdateKey
{
    // The raw Ed25519 public key that signs update manifests
    inline constexpr std::array<uint8_t, 32> k_PublicKey = {
        0xa7, 0xd6, 0xa2, 0x94, 0x4a, 0x31, 0xa7, 0xb1, 0x42, 0xb9, 0xde, 0x92, 0xc5, 0xc7, 0x0f, 0x5c,
        0x0f, 0x80, 0xb0, 0x35, 0x71, 0x10, 0x3c, 0x1c, 0x61, 0x43, 0x56, 0xe2, 0xa6, 0x32, 0x18, 0x5e,
    };

    // The product a manifest must name, so Apollo's manifests can't pass as LuzLunar's
    inline constexpr std::string_view k_Product = "luzlunar";

    // The latest release's manifest and its signature (GitHub redirects these to the latest release)
    inline constexpr std::string_view k_ManifestUrl = "https://github.com/anyosag/LuzLunar/releases/latest/download/update.json";
    inline constexpr std::string_view k_SignatureUrl = "https://github.com/anyosag/LuzLunar/releases/latest/download/update.json.sig";

    // Every asset a manifest names must be under this prefix
    inline constexpr std::string_view k_AssetUrlPrefix = "https://github.com/anyosag/LuzLunar/releases/download/";
}
