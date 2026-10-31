// Unit tests for app/fork/forkkeymap.cpp, built and run by .github/workflows/fork-macos.yml:
//   clang++ -std=c++17 -Iapp -Ilibs/mac/include/SDL2 tests/fork/keymap_test.cpp app/fork/forkkeymap.cpp
#include "fork/forkkeymap.h"

#include <cstdio>

using namespace ForkKeymap;

static int s_Failures = 0;

#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            s_Failures++;                                               \
        }                                                               \
    } while (0)

int main()
{
    const Map mac = { { TargetWin, TargetAlt, TargetCtrl } }; // Control->Win, Option->Alt, Command->Ctrl
    const Map dropOption = { { TargetCtrl, TargetNone, TargetWin } };

    // Identity
    CHECK(isIdentity(identity()));
    CHECK(!isIdentity(mac));
    CHECK(remapModifiers(KMOD_LCTRL | KMOD_LSHIFT, identity()) == (KMOD_LCTRL | KMOD_LSHIFT));

    // Classification keeps the side
    bool right = true;
    CHECK(classify(SDL_SCANCODE_LGUI, &right) == PhysicalGui && !right);
    CHECK(classify(SDL_SCANCODE_RCTRL, &right) == PhysicalCtrl && right);
    CHECK(classify(SDL_SCANCODE_RALT, &right) == PhysicalAlt && right);
    CHECK(classify(SDL_SCANCODE_C, &right) == NotModifier);

    // Target scancodes keep the side
    CHECK(targetScancode(TargetCtrl, false) == SDL_SCANCODE_LCTRL);
    CHECK(targetScancode(TargetWin, true) == SDL_SCANCODE_RGUI);
    CHECK(targetScancode(TargetNone, false) == SDL_SCANCODE_UNKNOWN);

    // Cmd+C becomes Ctrl+C, and Shift survives
    CHECK(remapModifiers(KMOD_LGUI, mac) == KMOD_LCTRL);
    CHECK(remapModifiers(KMOD_RGUI | KMOD_LSHIFT, mac) == (KMOD_RCTRL | KMOD_LSHIFT));

    // Control becomes Windows, Option stays Alt, locks are untouched
    CHECK(remapModifiers(KMOD_LCTRL | KMOD_LALT | KMOD_CAPS, mac) == (KMOD_LGUI | KMOD_LALT | KMOD_CAPS));

    // Held Control (-> Win) forces the Windows modifier; held Command (-> Ctrl) doesn't
    CHECK(heldNonGuiMappedToWin(KMOD_LCTRL, mac));
    CHECK(!heldNonGuiMappedToWin(KMOD_LGUI, mac));
    CHECK(!heldNonGuiMappedToWin(KMOD_NONE, mac));

    // A key mapped to nothing loses its modifier bit
    CHECK(remapModifiers(KMOD_LALT | KMOD_LCTRL, dropOption) == KMOD_LCTRL);

    // Left Alt+M goes with Ctrl, which Windows reads as AltGr+M (µ); locks don't matter
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_LALT) == (KMOD_LALT | KMOD_LCTRL));
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_LALT | KMOD_CAPS) == (KMOD_LALT | KMOD_LCTRL | KMOD_CAPS));
    // Right Alt is AltGr already; other keys, other modifiers or none are left alone
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_RALT) == KMOD_RALT);
    CHECK(leftAltMicro(SDL_SCANCODE_N, KMOD_LALT) == KMOD_LALT);
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_LALT | KMOD_LSHIFT) == (KMOD_LALT | KMOD_LSHIFT));
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_LALT | KMOD_LCTRL) == (KMOD_LALT | KMOD_LCTRL));
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_LALT | KMOD_LGUI) == (KMOD_LALT | KMOD_LGUI));
    CHECK(leftAltMicro(SDL_SCANCODE_M, KMOD_NONE) == KMOD_NONE);
    // Mac Option+M: Option stays Alt after the remapping, so it still applies
    CHECK(leftAltMicro(SDL_SCANCODE_M, remapModifiers(KMOD_LALT, mac)) == (KMOD_LALT | KMOD_LCTRL));

    if (s_Failures == 0) {
        std::printf("All key remapping tests passed\n");
    }
    return s_Failures == 0 ? 0 : 1;
}
