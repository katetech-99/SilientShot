#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DIR="$BUILD_DIR/DerivedData"
STAGING_DIR="$BUILD_DIR/dmg-root"
APP_PATH="$DERIVED_DIR/Build/Products/Release/SilentShot.app"
DMG_PATH="$BUILD_DIR/SilentShot-1.0.0.dmg"

ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/SilentShot/AppIcon.icns"

xcodebuild \
  -project "$ROOT_DIR/SilentShot.xcodeproj" \
  -scheme SilentShot \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

codesign --force --deep --sign - "$APP_PATH"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname SilentShot \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
