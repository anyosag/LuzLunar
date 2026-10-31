#!/bin/bash
# LuzLunar build for Apple Silicon: scripts/generate-dmg.sh, but arm64 only, renamed and re-signed.
# Requires create-dmg from https://github.com/sindresorhus/create-dmg and Qt's tools on PATH.
#
# An unsigned arm64 app doesn't launch on Apple Silicon (macdeployqt invalidates the linker's
# ad-hoc signature), so the bundle is re-signed: with the certificate in LUZLUNAR_SIGN_IDENTITY
# when it's set, ad-hoc otherwise. macOS ties privacy permissions such as Accessibility to the
# signature, and an ad-hoc signature changes with every build, so only certificate-signed builds
# keep them across updates. Hardened runtime (--options runtime) is left off: without a Team ID it
# makes library validation reject the bundled Qt frameworks.
#
# Paths are quoted throughout, so the checkout may live in a folder whose name has spaces.
# Optional switches for local builds (CI sets neither of the first two):
#   LUZLUNAR_SKIP_DMG=1  skip the DMG, e.g. when create-dmg isn't installed
#   LUZLUNAR_INSTALL=1   replace /Applications/LuzLunar.app with this build; the old copy goes to the Trash
#   LUZLUNAR_SIGN_IDENTITY=<SHA-1>  sign with this certificate (CI sets it from the LUZLUNAR_SIGNING_P12
#                        secret); LUZLUNAR_SIGN_KEYCHAIN names the keychain that holds it, if not the default
BUILD_CONFIG=$1

fail()
{
	echo "$1" 1>&2
	exit 1
}

if [ "$BUILD_CONFIG" != "Debug" ] && [ "$BUILD_CONFIG" != "Release" ]; then
  fail "Invalid build configuration - expected 'Debug' or 'Release'"
fi

BUILD_ROOT="$PWD/build"
SOURCE_ROOT="$PWD"
BUILD_FOLDER="$BUILD_ROOT/build-$BUILD_CONFIG"
INSTALLER_FOLDER="$BUILD_ROOT/installer-$BUILD_CONFIG"
APP="$BUILD_FOLDER/app/Moonlight.app"
APP_NAME=LuzLunar

# install-qt-action provides qmake; Homebrew also names it qmake6
QMAKE=${QMAKE:-$(command -v qmake || command -v qmake6)}
[ -n "$QMAKE" ] || fail "qmake not found! Put Qt's bin folder on PATH."

# LuzLunar's version, like 1.16, or 1.16-dev.ee5b3ba for a build that isn't a published update. CI
# works it out from the updates published before (scripts/fork/version.sh); a local build is
# local.<commit>. The app shows it in Settings and About, so copies can be told apart.
if [ -n "$CI_VERSION" ]; then
  VERSION=$CI_VERSION
else
  VERSION="local.$(git -C "$SOURCE_ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
fi

echo Updating dependencies
python3 "$SOURCE_ROOT/setup-deps.py" || fail "Dependency download failed!"

echo Applying patches to submodules
bash "$SOURCE_ROOT/scripts/fork/apply-patches.sh" || fail "A patch in patches/ no longer applies!"

echo Cleaning output directories
rm -rf "$BUILD_FOLDER"
rm -rf "$INSTALLER_FOLDER"
mkdir -p "$BUILD_FOLDER"
mkdir -p "$INSTALLER_FOLDER"

# Enable LTO like official builds
export CFLAGS=-flto=thin
export CXXFLAGS=-flto=thin
export LDFLAGS=-flto=thin

# A compiler cache, when ccache is installed, through qmake's ccache feature: CI keeps one between
# runs (fork-macos.yml), so a build compiles again only what changed
CACHE_ARGS=()
if command -v ccache > /dev/null; then
  CACHE_ARGS+=(CONFIG+=ccache)
  echo "Compiling through $(ccache --version | head -n1)"
fi

# Over-the-air updates order builds by CI run and only replace master builds by themselves
# (app/fork/forkupdater.cpp). CI sets both; a local build is run 0 on the "local" channel.
UPDATE_ARGS=()
if [[ "$FORK_BUILD_RUN" =~ ^[0-9]+$ ]]; then UPDATE_ARGS+=(FORK_BUILD_RUN="$FORK_BUILD_RUN"); fi
if [[ "$FORK_BUILD_CHANNEL" =~ ^[a-z]+$ ]]; then UPDATE_ARGS+=(FORK_BUILD_CHANNEL="$FORK_BUILD_CHANNEL"); fi

echo Configuring the project for arm64
pushd "$BUILD_FOLDER"
"$QMAKE" "$SOURCE_ROOT/moonlight-qt.pro" QMAKE_APPLE_DEVICE_ARCHS="arm64" FORK_BUILD_ID="$VERSION" "${UPDATE_ARGS[@]}" "${CACHE_ARGS[@]}" || fail "Qmake failed!"
popd

echo Compiling Moonlight in $BUILD_CONFIG configuration
pushd "$BUILD_FOLDER"
make -j$(sysctl -n hw.logicalcpu) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd
if command -v ccache > /dev/null; then
  ccache --show-stats
fi

echo Saving dSYM file
pushd "$BUILD_FOLDER"
dsymutil app/Moonlight.app/Contents/MacOS/Moonlight -o "$APP_NAME-$VERSION.dsym" || fail "dSYM creation failed!"
cp -R "$APP_NAME-$VERSION.dsym" "$INSTALLER_FOLDER" || fail "dSYM copy failed!"
popd

echo Creating app bundle
EXTRA_ARGS=()
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS+=(-use-debug-libs); fi
macdeployqt "$APP" "${EXTRA_ARGS[@]}" -qmldir="$SOURCE_ROOT/app/gui" -appstore-compliant || fail "macdeployqt failed!"

# A multi-display stream's helper processes run Qt offscreen, so they never show a Qt window or
# take the keyboard (app/fork/forkhelper.cpp). macdeployqt only deploys the cocoa platform plugin.
echo Adding the offscreen platform plugin
QT_PLUGINS=$("$QMAKE" -query QT_INSTALL_PLUGINS)
cp "$QT_PLUGINS/platforms/libqoffscreen.dylib" "$APP/Contents/PlugIns/platforms/" || fail "Copying the offscreen platform plugin failed!"

echo Removing dSYM files from app bundle
find "$APP" -name '*.dSYM' -print0 | xargs -0 rm -rf

# The fork ships as LuzLunar. The bundle ID and Moonlight's settings domain stay the same,
# so pairing and settings carry over from the official app.
echo Renaming the app bundle to $APP_NAME
FINAL_APP="$BUILD_FOLDER/app/$APP_NAME.app"
rm -rf "$FINAL_APP"
mv "$APP" "$FINAL_APP" || fail "Renaming the app bundle failed!"
APP="$FINAL_APP"
mv "$APP/Contents/MacOS/Moonlight" "$APP/Contents/MacOS/$APP_NAME" || fail "Renaming the executable failed!"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST" || fail "Updating Info.plist failed!"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$PLIST" || fail "Setting CFBundleName failed!"
# LuzLunar's version for Finder's Get Info and the About panel ("Version 1.16 (202)"), with the CI
# run as the build number: it only goes up, so when copies share the bundle ID, macOS opens the
# newest. A local build is 0. Moonlight's own version stays in app/version.txt for upstream's code.
BUNDLE_BUILD=0
if [[ "$FORK_BUILD_RUN" =~ ^[0-9]+$ ]]; then BUNDLE_BUILD=$FORK_BUILD_RUN; fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUNDLE_BUILD" "$PLIST" ||
  fail "Setting the bundle's version failed!"

# No macOS Game Mode. Upstream's Info.plist opts in (ae1c6580: the games category and the
# Game Mode keys), so a fullscreen stream turned Game Mode on. The game controller keys stay.
echo Opting out of Game Mode
/usr/libexec/PlistBuddy -c "Delete :LSApplicationCategoryType" "$PLIST" 2>/dev/null
for KEY in LSSupportsGameMode GCSupportsGameMode; do
  /usr/libexec/PlistBuddy -c "Set :$KEY false" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$KEY bool false" "$PLIST" || fail "Setting $KEY failed!"
done
[ "$(/usr/libexec/PlistBuddy -c "Print :LSSupportsGameMode" "$PLIST")" == "false" ] || fail "LSSupportsGameMode isn't false!"
/usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" "$PLIST" >/dev/null 2>&1 && fail "The games category is still set!"

# This Mac's microphone on the PC (app/fork/forkmic.*): macOS asks once, with this, the first time
# the PC records
echo Adding the microphone usage string
MIC_USAGE="LuzLunar records only while an app on your PC records, so the PC can hear you."
/usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription $MIC_USAGE" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string $MIC_USAGE" "$PLIST" || fail "Setting NSMicrophoneUsageDescription failed!"
[ "$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$PLIST")" == "$MIC_USAGE" ] || fail "NSMicrophoneUsageDescription isn't set!"

# A layered Icon Composer icon, which macOS 26 renders in Liquid Glass instead of boxing a legacy
# icon. actool also writes LuzLunar.icns, the same icon flattened, for older macOS.
echo Compiling the $APP_NAME app icon
if xcrun actool "$SOURCE_ROOT/scripts/fork/$APP_NAME.icon" --compile "$APP/Contents/Resources" \
     --app-icon $APP_NAME --include-all-app-icons --standalone-icon-behavior all \
     --enable-on-demand-resources NO --development-region en --target-device mac --platform macosx \
     --minimum-deployment-target 13.0 --output-partial-info-plist "$BUILD_FOLDER/icon-info.plist"; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $APP_NAME" "$PLIST" || fail "Setting CFBundleIconName failed!"
  if [ -f "$APP/Contents/Resources/$APP_NAME.icns" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $APP_NAME" "$PLIST" || fail "Setting CFBundleIconFile failed!"
  fi
  ls -la "$APP/Contents/Resources" | grep -E "Assets.car|\.icns"
else
  echo "::warning::actool couldn't compile the app icon; keeping Moonlight's icon"
fi

echo Checking the binary is arm64 only
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
[ "$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")" == "arm64" ] || fail "Expected an arm64-only binary!"

if [ -n "$LUZLUNAR_SIGN_IDENTITY" ]; then
  echo Signing app bundle with certificate $LUZLUNAR_SIGN_IDENTITY
  KEYCHAIN_ARGS=()
  if [ -n "$LUZLUNAR_SIGN_KEYCHAIN" ]; then KEYCHAIN_ARGS+=(--keychain "$LUZLUNAR_SIGN_KEYCHAIN"); fi
  codesign --force --deep --timestamp=none "${KEYCHAIN_ARGS[@]}" --sign "$LUZLUNAR_SIGN_IDENTITY" "$APP" || fail "Signing failed!"
  codesign --verify --deep --strict --verbose=2 "$APP" || fail "Signature verification failed!"
  codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc' && fail "Bundle is still ad-hoc signed!"
  # The designated requirement names the certificate. It must read the same in every build, or
  # macOS treats the update as a different app and drops its permissions, and over-the-air
  # updates refuse it (app/fork/mac/selfupdate_mac.mm checks a new build against it).
  REQUIREMENT=$(codesign -d -r- "$APP" 2>&1 | grep designated)
  echo "$REQUIREMENT"
  echo "$REQUIREMENT" | grep -q 'certificate leaf' || fail "The designated requirement doesn't name the signing certificate!"
else
  echo Signing app bundle ad-hoc
  codesign --force --deep --sign - "$APP" || fail "Ad-hoc signing failed!"
  codesign --verify --deep --strict --verbose=2 "$APP" || fail "Signature verification failed!"
  codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc' || fail "Bundle isn't ad-hoc signed!"
fi

echo Smoke test: launching $APP_NAME --version
perl -e 'alarm 60; exec @ARGV' "$APP/Contents/MacOS/$APP_NAME" --version
STATUS=$?
case $STATUS in
  0) echo "$APP_NAME started and exited cleanly" ;;
  137) fail "$APP_NAME was killed at launch (SIGKILL), which usually means an invalid code signature" ;;
  *) echo "::warning::$APP_NAME --version exited with status $STATUS (not a signature failure)" ;;
esac

# The app as over-the-air updates download it (app/fork/forkupdater.cpp). ditto keeps the signature
# and the bundle's extended attributes, and LuzLunar unpacks it with ditto too.
echo Creating the update zip
rm -f "$INSTALLER_FOLDER/$APP_NAME-macOS-arm64.zip"
ditto -c -k --keepParent "$APP" "$INSTALLER_FOLDER/$APP_NAME-macOS-arm64.zip" || fail "Creating the update zip failed!"

if [ "$LUZLUNAR_SKIP_DMG" == "1" ]; then
  echo Skipping the DMG
else
  echo Creating DMG
  create-dmg "$APP" "$INSTALLER_FOLDER" --no-version-in-filename
  case $? in
    0) ;;
    2) ;;  # no signing identity, expected
    *) fail "create-dmg failed!";;
  esac

  # create-dmg names the image after the app's display name
  DMG=$(ls "$INSTALLER_FOLDER"/*.dmg | head -n1)
  [ -n "$DMG" ] || fail "create-dmg produced no DMG!"
  mv "$DMG" "$INSTALLER_FOLDER/$APP_NAME-$VERSION.dmg"
  echo Build successful: "$INSTALLER_FOLDER/$APP_NAME-$VERSION.dmg"
fi

if [ "$LUZLUNAR_INSTALL" == "1" ]; then
  INSTALL_PATH="/Applications/$APP_NAME.app"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")
  echo Installing to "$INSTALL_PATH"

  # Quit the running copy first. LuzLunar keeps Moonlight's bundle ID, so ask by ID, and only
  # if it's running (telling an app that isn't running would launch it).
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null || break
    [ $i -eq 5 ] && pkill -TERM -f "$INSTALL_PATH/Contents/MacOS/"
    sleep 1
  done
  pgrep -f "$INSTALL_PATH/Contents/MacOS/" >/dev/null && fail "$APP_NAME is still running! Quit it and try again."

  # ditto merges into an existing bundle, and leftover files would break the signature,
  # so the old copy goes to the Trash (recoverable) instead of being overwritten
  if [ -e "$INSTALL_PATH" ]; then
    osascript -e "tell application \"Finder\" to delete POSIX file \"$INSTALL_PATH\"" >/dev/null || \
      fail "Couldn't move the old $APP_NAME.app to the Trash!"
  fi
  ditto "$APP" "$INSTALL_PATH" || fail "Copying $APP_NAME.app to /Applications failed!"
  codesign --verify --deep --strict "$INSTALL_PATH" || fail "The installed app's signature doesn't verify!"
  # LaunchServices caches an app's Info.plist by bundle ID (shared with Moonlight), so refresh it,
  # or macOS may keep treating the app as a game
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_PATH" || \
    echo "::warning::lsregister couldn't refresh $INSTALL_PATH"
  echo Installed "$INSTALL_PATH"
fi
