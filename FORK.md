# LuzLunar

**LuzLunar** ("moonlight" in Spanish) is a personal fork of [moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt) for an Apple Silicon Mac streaming from [Apollo](https://github.com/anyosag/Apollo). It's macOS-only and needs Qt 6.8 or later (`app/fork/fork.pri` stops qmake on older Qt). Its look changes aren't gated per platform, so other platforms would get them too, untested.

It ships as `LuzLunar.app`, but keeps Moonlight's bundle ID (`com.moonlight-stream.Moonlight`) and settings domain, so paired PCs and settings carry over from the official app. Upstream code and upstream strings still say "Moonlight"; only the app bundle, the display name and the fork's own UI use LuzLunar.

## Builds

- `.github/workflows/fork-macos.yml` builds an arm64-only, ad-hoc signed `LuzLunar.app` and DMG with `scripts/fork/build-mac.sh`. The script renames the bundle after `macdeployqt`. The workflow runs on pushes to `master` and `claude/**` and on pull requests. It takes its runner, Qt version and aqtinstall pin from upstream's `build-win-mac.yml`.
- Locally, run `bash scripts/fork/build-mac.sh Release` from the repo root (paths with spaces are fine). It needs Qt's tools on `PATH`; with Homebrew that's `qtbase`, `qtdeclarative`, `qtsvg` and `qtimageformats`, the last for the WebP the native spinner uses. Two optional switches, both off in CI:
  - `LUZLUNAR_SKIP_DMG=1` skips the DMG, so `create-dmg` isn't needed.
  - `LUZLUNAR_INSTALL=1` quits LuzLunar, moves `/Applications/LuzLunar.app` to the Trash and installs the new build.
- Every build has a build ID: the version plus the commit, like `6.2.0-fork.ee5b3ba`, the same as in the artifact and DMG names. It's shown at the bottom of Settings › Keyboard & Clipboard (`ForkPreferences.buildId`, from qmake's `FORK_BUILD_ID`) and is the bundle's `CFBundleVersion`, so Finder's Get Info tells copies apart.
- Upstream's `build.yml` (every platform) is disabled in this repo's Actions settings. The file stays unchanged so upstream merges stay clean.
- `.github/workflows/sync-upstream.yml` merges upstream `master` daily and builds when anything new arrives. To sync upstream workflow changes, it needs a `SYNC_TOKEN` secret: a fine-grained token for this repo with Contents and Workflows read/write.

## Installing a build

1. Download the `LuzLunar-macOS-arm64-…` artifact from the workflow run, then unzip it and open the DMG.
2. Drag LuzLunar to Applications and delete the official `Moonlight.app`. Both share a bundle ID and settings, so keep only one. Paired PCs and settings carry over. Also delete older LuzLunar copies outside Applications (an unzipped artifact folder, a mounted DMG), or Spotlight and Launchpad may open one of them; the build ID in Settings shows which build is running.
3. The app is ad-hoc signed, not notarized. Open it the first time with right-click → Open, or run `xattr -dr com.apple.quarantine /Applications/LuzLunar.app`.

## Keeping upstream merges clean

Fork code lives in new files: `app/fork/`, fork QML files in `app/gui/`, `scripts/fork/` and `.github/workflows/fork-*.yml`. Upstream files only get small hooks marked `[fork]`; they're listed below. If a sync fails with a conflict, merge upstream manually, keep upstream's change and re-apply the marked hook.

| Upstream file | Hook |
|---|---|
| `app/app.pro` | `include(fork/fork.pri)` at the end; `$$shell_quote()` around the Info.plist `cp`/`sed` paths, so builds work from paths with spaces |
| `app/streaming/input/keyboard.cpp` | `ForkInput::preprocessKeyEvent()` right after the special key combos; `forkForceGui` in the META modifier check and the LGUI/RGUI cases |
| `app/streaming/session.cpp` | `ForkStreamExtensions` created after `RichPresenceManager` in `exec()`, and `handleEvent()` before the event `switch`; `ForkStreamStats::reportConnectionStatus()` in `clConnectionStatusUpdate()`, after the `connectionWarnings` check |
| `app/gui/SettingsView.qml` | `ForkSettingsGroupBox` between the Input and Gamepad groups |
| `app/settings/streamingpreferences.h` | `friend class StreamProfiles` next to the private constructor |
| `app/gui/appmodel.cpp`, `app/gui/computermodel.cpp`, `app/cli/startstream.cpp` | `new Session(...)` replaced with `StreamProfiles::createSession(...)` |
| `app/gui/AppView.qml` | "Stream Settings..." menu item after "Hide Game", and the `StreamProfileDialog` next to `quitAppDialog` |
| `app/streaming/video/ffmpeg.cpp` | `ForkStreamStats::publish()` in the once-a-second stats block of `submitDecodeUnit()` |
| `app/main.cpp` | The native `macOS` Quick Controls style on macOS instead of Material |
| `app/gui/main.qml` | No Material import or background override; a transparent window `color` while the native chrome is active; `ForkNativeToolbar` before the header, with each button's `focused` state; while it's active the header is clipped to zero height but its buttons stay in the focus chain; Escape on a toolbar button returns to the page; the Settings button leaves the chain on the Settings page and the Update tooltip stays hidden with the native toolbar; `id: backButton`; `symbolName` on the toolbar buttons; title size |
| `app/gui/NavigableToolButton.qml` | `symbolName` (an SF Symbol from the image provider, `iconSource` as fallback), 20 pt tinted icons, hidden from VoiceOver while the native toolbar shows them |
| `app/gui/NavigableItemDelegate.qml` | Rounded card background on `QtQuick.Templates`, with a `cornerRadius` property |
| `app/gui/NavigableDialog.qml` | `ForkDialogBackground` as the background, padding, and the style's header and footer panels hidden |
| `app/gui/NavigableMessageDialog.qml` | Icon is a tinted `IconImage` (was `Image`); `ForkBusyIndicator` |
| `app/gui/StreamSegue.qml`, `QuitSegue.qml`, `CliPair.qml`, `CliStartStreamSegue.qml`, `CliQuitStreamSegue.qml` | `ForkBusyIndicator`, and the stage label at least its own height |
| `app/gui/NavigableMenu.qml` | `popupType: Popup.Item` (in-window, so gamepad keys reach it) |
| `app/gui/PcView.qml`, `app/gui/AppView.qml` | Tile, icon and font sizes; tinted `IconImage`s from 2x images; AppView's box art cut to 12 pt rounded corners (`MultiEffect` mask) inside a card whose corners nest around it; `ForkBusyIndicator` for the search spinner; no Material import |
| `app/gui/AutoResizingComboBox.qml` | Indicator null check; the Material popup color only off macOS; versionless Controls import and `popup.popupType: Popup.Item` (in-window, so gamepad keys reach it) |
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
  - Messages ("Clipboard sent to the PC", errors) appear beside the notch while the notch bar is on screen, and in Moonlight's status overlay otherwise.
- **Notch info bar** (`app/fork/mac/notchbar.*`, `app/fork/streamstats.*`):
  - In fullscreen on a MacBook with a camera notch, the strip beside the notch shows the app and PC name on the left. On the right it shows the frame rate, network latency, bitrate, codec and loss.
  - macOS keeps a fullscreen window below the notch, so the bar is a separate non-activating panel above the stream's level that joins its fullscreen Space. It uses Liquid Glass (`NSGlassEffectView`) on macOS 26 and vibrancy before that.
  - Stats come from the decoder's once-a-second stats tick, computed only while the bar is listening.
  - The bar shows only while the stream is fullscreen on the active Space of a display with a notch. Turn it off in Settings › Keyboard & Clipboard.
  - Messages appear in a third pill beside the notch. A red dot blinks twice, then grows into the pill; the app name fades out if they don't both fit. With Reduce Motion the pill just fades in and out.
    - Moonlight's poor connection warning ("Slow connection to PC · reduce your bitrate") stays until the connection recovers. It arrives on moonlight-common-c's receive thread through `ForkStreamStats::reportConnectionStatus()`, which tells `Session` whether the bar showed it.
    - Clipboard messages come through `ClipboardSync::setMessageSink()` and stay 3 seconds. One that arrives during the warning shows, then the warning returns.
    - While the bar isn't on screen (windowed, no notch, or turned off), both stay in Moonlight's red status overlay as before.
- **Native macOS look** (`app/gui/Fork*.qml`, `app/fork/windowchrome.*`, `app/fork/mac/windowchrome_mac.mm`):
  - The app uses Qt's native `macOS` style, so controls follow the system appearance and accent color. `main.cpp` still picks Material elsewhere, but the QML look changes aren't gated, since LuzLunar is macOS-only.
  - On macOS 15 and later the main window gets a real `NSToolbar` (Liquid Glass buttons on macOS 26) with SF Symbols. `ForkNativeToolbar.qml` mirrors main.qml's toolbar buttons into it and clicks the QML button when a native one is clicked, so upstream's behavior and shortcuts stay. While the native toolbar is active, the QML toolbar is clipped to zero height but stays in the focus chain. Keyboard and gamepad navigation still reach its buttons (Up from a grid's top row, Tab on Settings), and the native item of the focused button is highlighted: prominent on macOS 26, selected before. The delegate builds a new `NSToolbarItem` each time AppKit asks, from per-item state.
  - The window is translucent while the native chrome is active. A full-window backdrop sits in the window frame below Qt's content view, title bar included:
    - macOS 26: Liquid Glass (`NSGlassEffectView`), tinted 70% toward the window background color so content stays readable.
    - Earlier macOS: a behind-window blur.
    - To show it, `forkqml.cpp` turns on Qt's alpha buffer and main.qml's window `color` is transparent.
  - Rounded tiles with hover, press and focus states; dialogs are rounded panels with a shadow.
  - Menus and combo box lists open inside the main window (`Popup.Item`), because gamepad navigation sends its keys to the main window.
  - Spinners use `ForkBusyIndicator`, which has a fixed size. The style's spinner is an animated WebP, so builds need the `qtimageformats` plugin (CI installs it).
  - SF Symbols in QML come from an image provider (`image://sfsymbol/<name>`, `app/fork/sfsymbols.*`, `app/fork/mac/sfsymbolprovider.mm`), because Qt Quick's `icon.name` can't reach them. Elsewhere `SfSymbols.available` is false and the SVGs stay.
  - The app icon is an Icon Composer icon (`scripts/fork/LuzLunar.icon`: a crescent moon behind sparkles), which macOS 26 renders in Liquid Glass. `build-mac.sh` compiles it with `actool` into `Assets.car` plus a flattened `LuzLunar.icns` for older macOS.
  - CI saves screenshots of the main views in light and dark (`app/fork/screenshotharness.cpp`, the `LuzLunar-screenshots-*` artifact).
