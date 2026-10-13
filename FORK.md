# LuzLunar

**LuzLunar** ("moonlight" in Spanish) is a personal fork of [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt) for an Apple Silicon Mac streaming from [Apollo](https://github.com/anyosag/Apollo).

It ships as `LuzLunar.app`, but keeps Moonlight's bundle ID (`com.moonlight-stream.Moonlight`) and settings domain, so paired PCs and settings carry over from the official app. Upstream code and upstream strings still say "Moonlight"; only the app bundle, the display name and the fork's own UI use LuzLunar.

## Builds

- `.github/workflows/fork-macos.yml` builds an arm64-only, ad-hoc signed `LuzLunar.app` and DMG with `scripts/fork/build-mac.sh`. The script renames the bundle after `macdeployqt`. The workflow runs on pushes to `master` and `claude/**` and on pull requests. It takes its runner, Qt version and aqtinstall pin from upstream's `build-win-mac.yml`.
- Upstream's `build.yml` (every platform) is disabled in this repo's Actions settings. The file stays unchanged so upstream merges stay clean.
- `.github/workflows/sync-upstream.yml` merges upstream `master` daily and builds when anything new arrives. To sync upstream workflow changes, it needs a `SYNC_TOKEN` secret: a fine-grained token for this repo with Contents and Workflows read/write.

## Installing a build

1. Download the `LuzLunar-macOS-arm64-…` artifact from the workflow run, then unzip it and open the DMG.
2. Drag LuzLunar to Applications and delete the official `Moonlight.app`. Both share a bundle ID and settings, so keep only one. Paired PCs and settings carry over.
3. The app is ad-hoc signed, not notarized. Open it the first time with right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/LuzLunar.app`.

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
| `app/main.cpp` | The native `macOS` Quick Controls style on macOS instead of Material |
| `app/gui/main.qml` | No Material import or background override; `ForkNativeToolbar` before the header, which collapses while it's active; `id: backButton`; `symbolName` on the toolbar buttons; title size |
| `app/gui/NavigableToolButton.qml` | `symbolName` and 20 pt tinted icons |
| `app/gui/NavigableItemDelegate.qml` | Rounded card background on `QtQuick.Templates` |
| `app/gui/NavigableDialog.qml` | `ForkDialogBackground` and padding on macOS |
| `app/gui/NavigableMenu.qml` | `popupType: Popup.Window` |
| `app/gui/PcView.qml`, `app/gui/AppView.qml` | Tile, icon and font sizes; tinted `IconImage`s; no Material import |
| `app/gui/AutoResizingComboBox.qml` | Indicator null check; the Material popup color only off macOS |
| `app/gui/SettingsView.qml` | Plain group box titles instead of sky blue |

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
- **Apollo clipboard sync** (`app/fork/clipboardsync.*`, `apolloclient.*`, `clipbundle.*`, `mac/pasteboard*`):
  - With LuzLunar's Apollo build (anyosag/Apollo), the clipboard travels as a *clipbundle* through `GET`/`POST /actions/clipboard?type=bundle&v=1`, using the paired client certificate. One bundle carries plain text, RTF, HTML, PNG/JPEG and Office's drawing format (`Art::GVML ClipFormat` on Windows, `com.microsoft.Art--GVML-ClipFormat` on the Mac), so formatting survives Word, Excel and PowerPoint copies between the Mac and the PC. Other Apollo versions answer 400, and sync falls back to plain text (`type=text`).
  - `clipbundle.*` is shared byte for byte with anyosag/Apollo (`src/fork/clipbundle.*`), and `tests/fork/clipbundle_test.cpp` runs in both repos' CI. Keep the copies identical. It has the compact little-endian format, zlib compression for text formats, a content hash, the Windows "HTML Format" header, and the send rules:
    - a file copy sends only its text
    - an image is sent only for picture copies (no text, or an image offered first), so an Excel range doesn't send a rendered bitmap
    - Word's HTML that points at local image files is dropped when RTF (which embeds the pictures) is there
    - bundles are limited to 64 MB
  - Only what changed is transferred. The PC returns a state token (its clipboard sequence number) and a content hash, and the Mac sends them back, so an unchanged clipboard costs a few bytes. Uploads are skipped while `NSPasteboard.changeCount` and the content hash are unchanged. This state lasts for the app's life, per host.
  - On the Mac, the pasteboard is read and written on the sync worker thread (`mac/pasteboard_mac.mm`), so streaming never waits for Office to render or for TIFF/HEIC to convert (with ImageIO). Images go as PNG, HEIC photos as JPEG.
  - Modes are Off, Shortcuts only (Ctrl+Option+Shift+U sends, G fetches) and Automatic (the default). Automatic sends the clipboard when a stream starts or regains focus, and fetches the PC's when it loses focus or ends.
  - Requests run one at a time on a worker thread and report back through an SDL event, because the Qt event loop is paused while streaming.
  - Sync never wipes the local clipboard with an empty one and never sends back content that came from the host. Password-manager clips (`org.nspasteboard.ConcealedType`/`TransientType`, or Windows' `ExcludeClipboardContentFromMonitorProcessing`) are never synced automatically, and when sent with the shortcut they're marked private on the other side. Logs show types and sizes, never content.
  - The host must be Apollo, and Apollo must give this device its Clipboard permissions. Sync checks this through serverinfo `<Permission>`.
- **Notch info bar** (`app/fork/mac/notchbar.*`, `app/fork/streamstats.*`):
  - In fullscreen on a MacBook with a camera notch, the strip beside the notch shows the app and PC name on the left. On the right it shows the frame rate, network latency, bitrate, codec and loss.
  - macOS keeps a fullscreen window below the notch, so the bar is a separate non-activating panel above the stream's level that joins its fullscreen Space. It uses Liquid Glass (`NSGlassEffectView`) on macOS 26 and vibrancy before that.
  - Stats come from the decoder's once-a-second stats tick, computed only while the bar is listening.
  - The bar shows only while the stream is fullscreen on the active Space of a display with a notch. Turn it off in Settings › Keyboard & Clipboard.
- **Native macOS look** (`app/gui/Fork*.qml`, `app/fork/windowchrome.*`, `app/fork/mac/windowchrome_mac.mm`):
  - On macOS the app uses Qt's native `macOS` style, so controls follow the system appearance and accent color. Other platforms keep Material.
  - On macOS 15 and later the main window gets a real `NSToolbar` (Liquid Glass buttons on macOS 26) with SF Symbols. `ForkNativeToolbar.qml` mirrors main.qml's toolbar buttons into it and clicks the QML button when a native one is clicked, so upstream's behavior and shortcuts stay. The QML toolbar collapses while the native one is active.
  - Rounded tiles with hover, press and focus states; dialogs are rounded panels with a shadow.
  - SF Symbols in QML come from an image provider (`image://sfsymbol/<name>`, `app/fork/sfsymbols.*`, `app/fork/mac/sfsymbolprovider.mm`), because Qt Quick's `icon.name` can't reach them. Elsewhere `SfSymbols.available` is false and the SVGs stay.
  - The app icon is an Icon Composer icon (`scripts/fork/LuzLunar.icon`: a crescent moon behind sparkles), which macOS 26 renders in Liquid Glass. `build-mac.sh` compiles it with `actool` into `Assets.car` plus a flattened `LuzLunar.icns` for older macOS.
  - CI saves screenshots of the main views in light and dark (`app/fork/screenshotharness.cpp`, the `LuzLunar-screenshots-*` artifact).
