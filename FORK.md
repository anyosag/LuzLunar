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
| `app/streaming/session.cpp` | `ForkStreamExtensions` created after `RichPresenceManager` in `exec()` (given `*m_Preferences`, for Fullscreen fill), and `handleEvent()` before the event `switch`; `ForkStreamStats::reportConnectionStatus()` in `clConnectionStatusUpdate()`, after the `connectionWarnings` check; `ForkVideoScaling::useSpacesFullscreen()` on the `shouldUseFullScreenSpaces` result in `initialize()`, before it sets the fullscreen Spaces hint (picks by aspect ratio on a notched display) |
| `app/gui/SettingsView.qml` | `ForkThisMacGroupBox` and `ForkSettingsGroupBox` between the Input and Gamepad groups; `ForkStretchOption` under the Display mode combo box; `ForkAspectRatioPicker` above the resolution and FPS row (it refills the resolution combo box's list); the resolution combo box opens `forkCustomResolutionDialog` (`ForkCustomResolutionDialog`, declared after the upstream `customResolutionDialog`, which stays but is never opened) for its Custom entry; `ForkHardwareWarnings` under the resolution and FPS row |
| `app/settings/streamingpreferences.h` | `friend class StreamProfiles` next to the private constructor; the `fullscreenStretch` property, member and change signal, after `windowMode` |
| `app/settings/streamingpreferences.cpp` | `SER_FULLSCREENSTRETCH`, read in `reload()` and written in `save()`, after `windowMode` |
| `app/streaming/streamutils.cpp` | `scaleSourceToDestinationSurface()` returns early while `ForkVideoScaling::stretchActive()`, which leaves the destination as the whole surface: a stretch |
| `app/streaming/video/ffmpeg-renderers/vt_avsamplelayer.mm` | The display layer's `videoGravity` is `AVLayerVideoGravityResize` while stretching |
| `app/streaming/video/ffmpeg-renderers/vt_metal.mm` | The stretch state (`m_LastStretch`) is part of the video quad's cache key in `updateVideoRegionSizeForFrame()` |
| `app/gui/appmodel.cpp`, `app/gui/computermodel.cpp`, `app/cli/startstream.cpp` | `new Session(...)` replaced with `StreamProfiles::createSession(...)` |
| `app/gui/AppView.qml` | "Stream Settings..." menu item after "Hide Game", and the `StreamProfileDialog` next to `quitAppDialog` |
| `app/streaming/video/ffmpeg.cpp` | `ForkStreamStats::publish()` in the once-a-second stats block of `submitDecodeUnit()` |
| `app/streaming/video/overlaymanager.cpp` | `setOverlayRenderer()` notifies a new renderer of the overlays already on, so they survive a fullscreen toggle |
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
  - An app's context menu has "Stream Settings...". Each app can override codec, HDR, YUV 4:4:4, mouse mode, V-Sync, frame pacing, fullscreen fill (fit or stretch), resolution, frame rate and bitrate. It also has Office and Gaming presets.
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
  - A notched display has two shapes: the full panel, including the strip beside the notch (3024×1964, about 1.54:1, on a 14" MacBook Pro), and the area below the notch (3024×1890, 16:10). Fullscreen picks by the stream's aspect ratio, at any size (`ForkVideoScaling::useSpacesFullscreen()` in `app/fork/forkvideoscaling.*`, with the rule in `forkpolicy.*` and tests in `tests/fork/policy_test.cpp`):
    - The full panel's ratio (3024×1964, 1512×982…): a borderless window the size of the screen, video under the notch. The bar can't show, and the controller notices the window covers its screen and keeps the corner pill off it, so messages use Moonlight's red overlay.
    - The ratio below the notch (3024×1890, 2560×1600, 1920×1200…): a macOS fullscreen Space below the notch, with the bar.
    - Any other ratio (16:9, 21:9, 4:3…): a Space below the notch while the bar is on or Fullscreen fill is Stretch, because only a Space leaves the strip beside the notch for the bar, and a stretched picture must never be drawn under the notch; with both off, upstream's choice.
    - Upstream matched only the two exact native sizes. In Fullscreen mode every other size got the borderless window, which lacks the fullscreen style, so the bar never showed.
  - Messages appear in a third pill beside the notch. A red dot blinks twice, then grows into the pill; the app name fades out if they don't both fit. With Reduce Motion the pill just fades in and out.
    - Moonlight's poor connection warning ("Slow connection to PC · reduce your bitrate") stays until the connection recovers. It arrives on moonlight-common-c's receive thread through `ForkStreamStats::reportConnectionStatus()`, which tells `Session` whether the bar showed it.
    - Clipboard messages come through `ClipboardSync::setMessageSink()` and stay 3 seconds. One that arrives during the warning shows, then the warning returns.
    - While the stream is windowed, both appear in a pill in the window's bottom-left corner instead (`ForkCornerMessage`): the same glass capsule, icon and text, fading in as it rises 6 pt (only fading with Reduce Motion). It's a child window of the stream window, so it moves, resizes and changes Spaces with it, and clicks pass through it.
    - Fullscreen on a display without a notch, or with the bar turned off, they stay in Moonlight's red status overlay as before.
    - A warning that's up moves along: between the bar and the corner pill, into the overlay when neither is on screen, and back out when one returns. The connection status only arrives when it changes, so `ForkStreamStats` keeps the last one for `connectionPoor()` and `setConnectionWarningInOverlay()`.
  - The bar stays hidden while the stream window enters or leaves fullscreen. Once the panel's first fullscreen Space is gone (the stream went windowed), macOS keeps it on the desktop's Space, and ordering it in again doesn't move it. So when the shown panel isn't on the active Space, its pills move to a new panel, which joins the stream's Space.
- **Fullscreen stretch** (`app/fork/forkvideoscaling.*`, `app/gui/ForkStretchOption.qml`):
  - Apollo makes a virtual display at any size, so a stream's aspect ratio can differ from the screen's. Fullscreen fits it with black bars; "Fullscreen fill" in Settings › Basic Settings, under Display mode, can be set to Stretch to fill the screen instead, which distorts the picture. It's saved as `fullscreenstretch`, and each app can override it in "Stream Settings..." (Global, Fit or Stretch, profile key `fullscreenStretch`).
  - It only applies in fullscreen, both Fullscreen and Borderless windowed. A windowed stream always fits, and the setting is disabled while Display mode is Windowed.
  - `ForkVideoScaling::stretchActive()` is true while the session's preference is on and the stream window has an SDL fullscreen flag (`SDL_WINDOW_FULLSCREEN_DESKTOP` includes `SDL_WINDOW_FULLSCREEN`'s bit, so both kinds count). `ForkStreamExtensions` turns it on with the session's own copy of the settings, so app profiles count, and off when the stream ends. It's one atomic window pointer plus a flags read, because libplacebo's pacer thread and vt_metal's display-link thread call it. The rule is `ForkPolicy::stretchActive()`, tested in `tests/fork/policy_test.cpp`. Each change is logged as `[fork] Fullscreen stretch on` / `off`.
  - Every renderer and the mouse mapping get the stretch from `StreamUtils::scaleSourceToDestinationSurface()`, which returns early and leaves the destination as the whole surface. That covers libplacebo, vt_metal, the SDL renderer, and absolute mouse and touch, so clicks land on the stretched picture. The window sizing in `Session` also calls it, but only while the window isn't fullscreen. `vt_avsamplelayer` picks `AVLayerVideoGravityResize` when it's created (it's recreated when the window changes), and `vt_metal` adds the stretch state to the cache key of its video quad.
  - On a notched display a stretched stream stays below the notch: any ratio that isn't the full panel's goes into a Space, like with the notch bar. A stream with the full panel's ratio still fills the panel, since it has nothing to distort.
  - With Stretch chosen, Settings shows how far off the picture is on the first display, like "16:9 on this screen: 11% taller". On a notched display it measures against the area below the notch, except for a stream with the full panel's ratio, which fills the panel and shows no distortion.
- **This Mac** (`app/fork/clienthardware.*`, `app/fork/mac/clienthardware_mac.mm`, `app/fork/forkhwrules.*`):
  - `ClientHardware` (a QML singleton) knows the Mac LuzLunar runs on: the chip (`machdep.cpu.brand_string`), the Metal GPU (none in some CI VMs), the hardware decoders and the displays. Settings shows it in a "This Mac" group (`ForkThisMacGroupBox.qml`). It reads again on `refresh()` and whenever macOS reports changed screen parameters.
  - Decoders come from `VTIsHardwareDecodeSupported` for H.264, HEVC and AV1. HEVC Main10 has no API, so `hasHevcMain10()` copies the GPU rules of `VTBaseRenderer::checkDecoderCapabilities()` in `vt_base.mm`; keep the two in sync.
  - Displays come in `CGGetActiveDisplayList` order, the index `StreamUtils::getNativeDesktopMode()` takes. Its native and below-the-notch pixel sizes are used as they are, so they match the session's notch logic. AppKit adds the name, scale, notch (`safeAreaInsets.top > 0`), refresh rate (`maximumFramesPerSecond`) and HDR (EDR headroom above 1).
  - A notched display has two shapes, and both are in the list: the full panel (`nativeWidth` × `nativeHeight`, `fullRatio`, 3024×1964 and "1.54:1") and the area below the notch (`safeWidth` × `safeHeight`, `belowNotchRatio`, 3024×1890 and "16:10"). They're equal without a notch. The aspect ratio picker walks this list.
  - `ForkHwRules::checkStream()` (pure C++, `tests/fork/hwrules_test.cpp`) gives advisory warnings, which Settings shows under the resolution and FPS row (`ForkHardwareWarnings.qml`) and the stream profile dialog shows for the profile's values, falling back to the global ones. It warns about:
    - forced H.264 above 4096 pixels on a side (the hardware limit)
    - a forced codec without a hardware decoder
    - HDR without hardware HEVC Main10 or AV1, or with H.264 forced
    - a side above 8192
    - a frame rate more than 5 above the display's refresh rate
  - `ForkHwRules::ratioLabel()` names aspect ratios: the usual name within 1% (16:9, 16:10, 21:9, 32:9, 4:3, 3:2, 5:4, 1:1), else a reduced W:H up to 32:32, else a decimal like "1.54:1".
- **Aspect ratios** (`app/fork/forkaspect.*`, `forkaspectratios.*`, `app/gui/ForkAspectRatioPicker.qml`, `ForkCustomResolutionDialog.qml`):
  - Apollo makes a virtual display at exactly the size a stream asks for, so any aspect ratio works. Settings › Basic Settings has an "Aspect ratio" dropdown above Resolution. Choosing a ratio refills the Resolution list with sizes of that ratio and selects the one that fills the display; the bitrate follows, as for any pick from the list. At startup the ratio of the saved size is selected (`AspectRatios.keyFor()`), and the saved size itself never changes. A size that isn't in the list stays as "Custom (W×H)".
  - The ratios, in order: the display's own shapes, then 16:10, 16:9, 21:9, 32:9, 4:3, 3:2, 5:4, 1:1 and "Custom ratio…" (a W:H field: `21:9`, `12:5`, `2.39:1`). A notched display has two shapes, offered separately: "Full display, with the notch area" (3024×1964, 1.54:1) and "Below the notch" (3024×1890, 16:10). Without a notch there's "Native (16:9)". A standard ratio that a shape already is (16:10 below the notch) isn't listed twice. With more than one display a "For display" box appears, built-in first.
  - The sizes (`ForkAspect::presetsFor()`, pure C++, `tests/fork/aspect_test.cpp`): the largest even size of the ratio that fits the display ("fills this display"), 720, 1080, 1440, 2160 and 2880 lines, and well-known monitor sizes within 1% of the ratio, like 2560×1080 and 3440×1440 (a well-known size replaces the generated one of its height, so 21:9 has no 3412×1440). Sizes above the display are kept and marked "larger than this display", since Apollo can render above the panel's resolution. Every side is even and within 256 to 8192.
  - The display a size is measured against (the box): the full panel for "Full display", the area below the notch for "Below the notch". For any other ratio on a notched display, the area below the notch while the stream goes there (the notch bar or Stretch is on, or upstream's choice for the window mode is a Space, which Borderless windowed is), else the full panel, the same decision `ForkPolicy::useSpacesFullscreen()` makes when the stream starts. The list refills when those settings change.
  - "Custom" in the resolution list opens `ForkCustomResolutionDialog` instead of upstream's dialog: width and height from 256 to 8192, "Keep aspect ratio" (the picker's ratio, or the starting size's), the typed size's ratio live ("3440 × 1440 · 21:9"), and a note when odd sizes will be rounded down to even. It has no GeForce Experience warning, since Apollo makes the display. The stream profile dialog's Resolution row offers the same ratios (an Aspect ratio row that isn't saved) and the same dialog as "Custom…"; profiles still store width and height.
  - `StreamProfiles::createSession()` rounds the session's width and height down to even and logs `[fork] Rounded the stream size WxH to W'xH'`. Apollo got odd sizes as typed, while moonlight-common-c only rounds the height, and only after the launch request.
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
