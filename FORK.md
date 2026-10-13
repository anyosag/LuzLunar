# anyosag/moonlight-qt

A personal fork of [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt) for an Apple Silicon Mac streaming from [Apollo](https://github.com/anyosag/Apollo).

## Builds

- `.github/workflows/fork-macos.yml` builds an arm64-only, ad-hoc signed DMG with `scripts/fork/build-mac.sh`. It runs on pushes to `master` and `claude/**` and on pull requests. It takes its runner, Qt version and aqtinstall pin from upstream's `build-win-mac.yml`.
- Upstream's `build.yml` (every platform) is disabled in this repo's Actions settings. The file stays unchanged so upstream merges stay clean.
- `.github/workflows/sync-upstream.yml` merges upstream `master` daily and builds when anything new arrives. To sync upstream workflow changes, it needs a `SYNC_TOKEN` secret: a fine-grained token for this repo with Contents and Workflows read/write.

## Installing a build

1. Download the `Moonlight-macOS-arm64-…` artifact from the workflow run, then unzip it and open the DMG.
2. Drag Moonlight to Applications, replacing the official app. The bundle ID is unchanged, so paired PCs and settings carry over.
3. The app is ad-hoc signed, not notarized. Open it the first time with right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/Moonlight.app`.

## Keeping upstream merges clean

Fork code lives in new files: `app/fork/`, fork QML files in `app/gui/`, `scripts/fork/` and `.github/workflows/fork-*.yml`. Upstream files only get small hooks marked `[fork]`; they're listed below. If a sync fails with a conflict, merge upstream manually, keep upstream's change and re-apply the marked hook.

| Upstream file | Hook |
|---|---|
| `app/app.pro` | `include(fork/fork.pri)` at the end |
| `app/streaming/input/keyboard.cpp` | `ForkInput::preprocessKeyEvent()` right after the special key combos; `forkForceGui` in the META modifier check and the LGUI/RGUI cases |
| `app/streaming/session.cpp` | `ForkStreamExtensions` created after `RichPresenceManager` in `exec()`, and `handleEvent()` before the event `switch` |
| `app/gui/SettingsView.qml` | `ForkSettingsGroupBox` between the Input and Gamepad groups |

## Fork features

- **Mac keyboard remapping** (`app/fork/forkkeymap.*`, `forkinput.*`, `forkpreferences.*`):
  - Command, Control and Option can each send Ctrl, Alt, the Windows key or nothing. The defaults are Command → Ctrl, Control → Windows and Option → Alt.
  - Moonlight's Ctrl+Option+Shift shortcuts still match the physical keys.
  - While streaming with Command remapped, Cmd+Q/Cmd+H go to the host (`app/fork/mac/macintegration.mm`).
  - Settings live under `fork/keyTargets` in Moonlight's preferences.
  - Unit tests are in `tests/fork/keymap_test.cpp`.
