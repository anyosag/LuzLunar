#!/bin/bash
# LuzLunar build for Apple Silicon: scripts/generate-dmg.sh, but arm64 only, renamed and ad-hoc signed.
# Requires create-dmg from https://github.com/sindresorhus/create-dmg and Qt's tools on PATH.
#
# An unsigned arm64 app doesn't launch on Apple Silicon (macdeployqt invalidates the linker's
# ad-hoc signature), so the bundle is re-signed ad-hoc. Hardened runtime (--options runtime)
# is left off: with an ad-hoc signature it makes library validation reject the bundled Qt frameworks.
#
# Paths are quoted throughout, so the checkout may live in a folder whose name has spaces.
# Optional switches for local builds (CI sets neither):
#   LUZLUNAR_SKIP_DMG=1  skip the DMG, e.g. when create-dmg isn't installed
#   LUZLUNAR_INSTALL=1   replace /Applications/LuzLunar.app with this build; the old copy goes to the Trash
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

# The build ID, like 6.2.0-fork.ee5b3ba: the version plus the commit. CI sets it; local builds make
# the same. The app shows it in Settings and as the bundle version, so copies can be told apart.
if [ -n "$CI_VERSION" ]; then
  VERSION=$CI_VERSION
else
  VERSION="$(cat "$SOURCE_ROOT/app/version.txt")-fork.$(git -C "$SOURCE_ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo local)"
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

echo Configuring the project for arm64
pushd "$BUILD_FOLDER"
"$QMAKE" "$SOURCE_ROOT/moonlight-qt.pro" QMAKE_APPLE_DEVICE_ARCHS="arm64" FORK_BUILD_ID="$VERSION" || fail "Qmake failed!"
popd

echo Compiling Moonlight in $BUILD_CONFIG configuration
pushd "$BUILD_FOLDER"
make -j$(sysctl -n hw.logicalcpu) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd

echo Saving dSYM file
pushd "$BUILD_FOLDER"
dsymutil app/Moonlight.app/Contents/MacOS/Moonlight -o "$APP_NAME-$VERSION.dsym" || fail "dSYM creation failed!"
cp -R "$APP_NAME-$VERSION.dsym" "$INSTALLER_FOLDER" || fail "dSYM copy failed!"
popd

echo Creating app bundle
EXTRA_ARGS=()
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS+=(-use-debug-libs); fi
macdeployqt "$APP" "${EXTRA_ARGS[@]}" -qmldir="$SOURCE_ROOT/app/gui" -appstore-compliant || fail "macdeployqt failed!"

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
# The build ID as the bundle version, shown by Finder's Get Info and the About panel
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST" || fail "Setting CFBundleVersion failed!"

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

echo Signing app bundle ad-hoc
codesign --force --deep --sign - "$APP" || fail "Ad-hoc signing failed!"
codesign --verify --deep --strict --verbose=2 "$APP" || fail "Signature verification failed!"
codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc' || fail "Bundle isn't ad-hoc signed!"

echo Smoke test: launching $APP_NAME --version
perl -e 'alarm 60; exec @ARGV' "$APP/Contents/MacOS/$APP_NAME" --version
STATUS=$?
case $STATUS in
  0) echo "$APP_NAME started and exited cleanly" ;;
  137) fail "$APP_NAME was killed at launch (SIGKILL), which usually means an invalid code signature" ;;
  *) echo "::warning::$APP_NAME --version exited with status $STATUS (not a signature failure)" ;;
esac

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
  echo Installed "$INSTALL_PATH"
fi
