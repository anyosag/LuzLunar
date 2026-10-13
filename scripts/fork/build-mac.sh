#!/bin/bash
# LuzLunar build for Apple Silicon: scripts/generate-dmg.sh, but arm64 only, renamed and ad-hoc signed.
# Requires create-dmg from https://github.com/sindresorhus/create-dmg and Qt's tools on PATH.
#
# An unsigned arm64 app doesn't launch on Apple Silicon (macdeployqt invalidates the linker's
# ad-hoc signature), so the bundle is re-signed ad-hoc. Hardened runtime (--options runtime)
# is left off: with an ad-hoc signature it makes library validation reject the bundled Qt frameworks.
BUILD_CONFIG=$1

fail()
{
	echo "$1" 1>&2
	exit 1
}

if [ "$BUILD_CONFIG" != "Debug" ] && [ "$BUILD_CONFIG" != "Release" ]; then
  fail "Invalid build configuration - expected 'Debug' or 'Release'"
fi

BUILD_ROOT=$PWD/build
SOURCE_ROOT=$PWD
BUILD_FOLDER=$BUILD_ROOT/build-$BUILD_CONFIG
INSTALLER_FOLDER=$BUILD_ROOT/installer-$BUILD_CONFIG
APP=$BUILD_FOLDER/app/Moonlight.app
APP_NAME=LuzLunar

if [ -n "$CI_VERSION" ]; then
  VERSION=$CI_VERSION
else
  VERSION=`cat $SOURCE_ROOT/app/version.txt`
fi

echo Updating dependencies
python3 $SOURCE_ROOT/setup-deps.py || fail "Dependency download failed!"

echo Cleaning output directories
rm -rf $BUILD_FOLDER
rm -rf $INSTALLER_FOLDER
mkdir -p $BUILD_FOLDER
mkdir -p $INSTALLER_FOLDER

# Enable LTO like official builds
export CFLAGS=-flto=thin
export CXXFLAGS=-flto=thin
export LDFLAGS=-flto=thin

echo Configuring the project for arm64
pushd $BUILD_FOLDER
qmake $SOURCE_ROOT/moonlight-qt.pro QMAKE_APPLE_DEVICE_ARCHS="arm64" || fail "Qmake failed!"
popd

echo Compiling Moonlight in $BUILD_CONFIG configuration
pushd $BUILD_FOLDER
make -j$(sysctl -n hw.logicalcpu) $(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]') || fail "Make failed!"
popd

echo Saving dSYM file
pushd $BUILD_FOLDER
dsymutil app/Moonlight.app/Contents/MacOS/Moonlight -o $APP_NAME-$VERSION.dsym || fail "dSYM creation failed!"
cp -R $APP_NAME-$VERSION.dsym $INSTALLER_FOLDER || fail "dSYM copy failed!"
popd

echo Creating app bundle
EXTRA_ARGS=
if [ "$BUILD_CONFIG" == "Debug" ]; then EXTRA_ARGS="$EXTRA_ARGS -use-debug-libs"; fi
macdeployqt $APP $EXTRA_ARGS -qmldir=$SOURCE_ROOT/app/gui -appstore-compliant || fail "macdeployqt failed!"

echo Removing dSYM files from app bundle
find $APP -name '*.dSYM' | xargs rm -rf

# The fork ships as LuzLunar. The bundle ID and Moonlight's settings domain stay the same,
# so pairing and settings carry over from the official app.
echo Renaming the app bundle to $APP_NAME
FINAL_APP=$BUILD_FOLDER/app/$APP_NAME.app
rm -rf $FINAL_APP
mv $APP $FINAL_APP || fail "Renaming the app bundle failed!"
APP=$FINAL_APP
mv $APP/Contents/MacOS/Moonlight $APP/Contents/MacOS/$APP_NAME || fail "Renaming the executable failed!"
PLIST=$APP/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" -c "Set :CFBundleDisplayName $APP_NAME" $PLIST || fail "Updating Info.plist failed!"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" $PLIST 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" $PLIST || fail "Setting CFBundleName failed!"

# A layered Icon Composer icon, which macOS 26 renders in Liquid Glass instead of boxing a legacy
# icon. actool also writes LuzLunar.icns, the same icon flattened, for older macOS.
echo Compiling the $APP_NAME app icon
if xcrun actool "$SOURCE_ROOT/scripts/fork/$APP_NAME.icon" --compile $APP/Contents/Resources \
     --app-icon $APP_NAME --include-all-app-icons --standalone-icon-behavior all \
     --enable-on-demand-resources NO --development-region en --target-device mac --platform macosx \
     --minimum-deployment-target 13.0 --output-partial-info-plist $BUILD_FOLDER/icon-info.plist; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $APP_NAME" $PLIST || fail "Setting CFBundleIconName failed!"
  if [ -f $APP/Contents/Resources/$APP_NAME.icns ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $APP_NAME" $PLIST || fail "Setting CFBundleIconFile failed!"
  fi
  ls -la $APP/Contents/Resources | grep -E "Assets.car|\.icns"
else
  echo "::warning::actool couldn't compile the app icon; keeping Moonlight's icon"
fi

echo Checking the binary is arm64 only
lipo -archs $APP/Contents/MacOS/$APP_NAME
[ "$(lipo -archs $APP/Contents/MacOS/$APP_NAME)" == "arm64" ] || fail "Expected an arm64-only binary!"

echo Signing app bundle ad-hoc
codesign --force --deep --sign - $APP || fail "Ad-hoc signing failed!"
codesign --verify --deep --strict --verbose=2 $APP || fail "Signature verification failed!"
codesign -dv $APP 2>&1 | grep -q 'Signature=adhoc' || fail "Bundle isn't ad-hoc signed!"

echo Smoke test: launching $APP_NAME --version
perl -e 'alarm 60; exec @ARGV' $APP/Contents/MacOS/$APP_NAME --version
STATUS=$?
case $STATUS in
  0) echo "$APP_NAME started and exited cleanly" ;;
  137) fail "$APP_NAME was killed at launch (SIGKILL), which usually means an invalid code signature" ;;
  *) echo "::warning::$APP_NAME --version exited with status $STATUS (not a signature failure)" ;;
esac

echo Creating DMG
create-dmg $APP $INSTALLER_FOLDER --no-version-in-filename
case $? in
  0) ;;
  2) ;;  # no signing identity, expected
  *) fail "create-dmg failed!";;
esac

# create-dmg names the image after the app's display name
DMG=$(ls $INSTALLER_FOLDER/*.dmg | head -n1)
[ -n "$DMG" ] || fail "create-dmg produced no DMG!"
mv "$DMG" $INSTALLER_FOLDER/$APP_NAME-$VERSION.dmg
echo Build successful: $INSTALLER_FOLDER/$APP_NAME-$VERSION.dmg
