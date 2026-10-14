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
| `app/settings/streamingpreferences.h` | `friend class StreamProfiles` next to the private constructor |
| `app/gui/appmodel.cpp`, `app/gui/computermodel.cpp`, `app/cli/startstream.cpp` | `new Session(...)` replaced with `StreamProfiles::createSession(...)` |
| `app/gui/AppView.qml` | "Stream Settings..." menu item after "Hide Game", and the `StreamProfileDialog` next to `quitAppDialog` |
| `app/streaming/video/ffmpeg.cpp` | `ForkStreamStats::publish()` in the once-a-second stats block of `submitDecodeUnit()` |

## Fork features

- **Mac keyboard remapping** (`app/fork/forkkeymap.*`, `forkinput.*`, `forkpreferences.*`):
  - Command, Control and Option can each send Ctrl, Alt, the Windows key or nothing. The defaults are Command → Ctrl, Control → Windows and Option → Alt.
  - Moonlight's Ctrl+Option+Shift shortcuts still match the physical keys.
  - While streaming with Command remapped, Cmd+Q/Cmd+H go to the host (`app/fork/mac/macintegration.mm`).
  - Settings live under `fork/keyTargets` in Moonlight's preferences.
  - Unit tests are in `tests/fork/keymap_test.cpp`.
- **Per-app stream profiles** (`app/fork/streamprofiles.*`, `app/gui/StreamProfileDialog.qml`):
  - An app's context menu has "Stream Settings...". Each app can override codec, HDR, YUV 4:4:4, mouse mode, V-Sync, frame pacing, resolution, frame rate and bitrate. It also has Office and Gaming presets.
  - Each session gets its own copy of the settings with the profile applied, so the global settings never change. Command line flags win over the profile.
  - Profiles are stored under `fork/profiles/<host uuid>/<hex app name>`.
  - CI warns if streaming code starts reading the global settings directly, which would bypass profiles.
- **Apollo clipboard sync** (`app/fork/clipboardsync.*`, `apolloclient.*`):
  - Text is shared through Apollo's HTTPS `GET`/`POST /actions/clipboard?type=text`, using the paired client certificate.
  - Modes are Off, Shortcuts only (Ctrl+Option+Shift+U sends, G fetches) and Automatic (the default). Automatic sends the clipboard when a stream starts or regains focus, and fetches the PC's when it loses focus or ends.
  - Requests run one at a time on a worker thread and report back through an SDL event, because the Qt event loop is paused while streaming.
  - Sync never wipes the local clipboard with empty text and never sends back text that came from the host. It skips password-manager clips (`org.nspasteboard.ConcealedType`/`TransientType`) and never logs clipboard contents.
  - The host must be Apollo, and Apollo must give this device its Clipboard permissions. Sync checks this through serverinfo `<Permission>`.
- **Notch info bar** (`app/fork/mac/notchbar.*`, `app/fork/streamstats.*`):
  - In fullscreen on a MacBook with a camera notch, the strip beside the notch shows the app and PC name on the left. On the right it shows the frame rate, network latency, bitrate, codec and loss.
  - macOS keeps a fullscreen window below the notch, so the bar is a separate non-activating panel above the stream's level that joins its fullscreen Space. It uses Liquid Glass (`NSGlassEffectView`) on macOS 26 and vibrancy before that.
  - Stats come from the decoder's once-a-second stats tick, computed only while the bar is listening.
  - The bar shows only while the stream is fullscreen on the active Space of a display with a notch. Turn it off in Settings › Keyboard & Clipboard.
