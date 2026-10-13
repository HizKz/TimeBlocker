#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="$OUTPUT_DIR/TimeBlocker.xcarchive"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"
APP_PATH="$ARCHIVE_PATH/Products/Applications/TimeBlocker.app"
DMG_PATH="$OUTPUT_DIR/TimeBlocker.dmg"
TEMP_DMG_PATH="$OUTPUT_DIR/TimeBlocker-rw.dmg"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR" "$DMG_PATH" "$TEMP_DMG_PATH"

xcodebuild \
  -project "$ROOT_DIR/TimeBlocker.xcodeproj" \
  -scheme TimeBlocker \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$OUTPUT_DIR/DerivedData" \
  -clonedSourcePackagesDirPath "$OUTPUT_DIR/SourcePackages" \
  -archivePath "$ARCHIVE_PATH" \
  ARCHS='arm64 x86_64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGNING_REQUIRED=YES \
  ENABLE_HARDENED_RUNTIME=YES \
  archive

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive did not contain TimeBlocker.app" >&2
  exit 1
fi

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ZIP_PATH="$OUTPUT_DIR/TimeBlocker-notarization.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$ZIP_PATH"
    xcrun stapler staple "$APP_PATH"
  fi
else
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "NOTARY_PROFILE requires DEVELOPER_ID_APPLICATION to be set." >&2
    exit 1
  fi
  echo "Packaging with an ad hoc signature. macOS may block this app on other Macs." >&2
fi

mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/TimeBlocker.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$STAGING_DIR/.background"
cp "$ROOT_DIR/assets/dmg-background.png" "$STAGING_DIR/.background/background.png"
hdiutil create \
  -volname "TimeBlocker Installer" \
  -fs HFS+ \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TEMP_DMG_PATH"

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG_PATH")"
printf '%s\n' "$ATTACH_OUTPUT"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | sed -n 's#^/dev/disk[0-9][0-9]*s[0-9][0-9]*[[:space:]][[:space:]]*Apple_HFS[[:space:]][[:space:]]*##p' | head -n 1)"
if [[ -z "$MOUNT_DIR" ]]; then
  echo "Could not find the mounted TimeBlocker Installer volume." >&2
  exit 1
fi
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "TimeBlocker Installer"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 780, 588}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set label position of viewOptions to bottom
    set background picture of viewOptions to file ".background:background.png"
    set position of item "TimeBlocker.app" of container window to {165, 270}
    set position of item "Applications" of container window to {495, 270}
    update without registering applications
    delay 4
    close container window
  end tell
end tell
APPLESCRIPT
hdiutil detach "$MOUNT_DIR"
hdiutil convert "$TEMP_DMG_PATH" -ov -format UDZO -o "$DMG_PATH"
rm -f "$TEMP_DMG_PATH"
rm -rf "$STAGING_DIR"

echo "Created: $DMG_PATH"
