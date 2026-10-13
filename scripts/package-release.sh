#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
ARCHIVE_PATH="$OUTPUT_DIR/TimeBlocker.xcarchive"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"
APP_PATH="$ARCHIVE_PATH/Products/Applications/TimeBlocker.app"
DMG_PATH="$OUTPUT_DIR/TimeBlocker.dmg"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH" "$STAGING_DIR" "$DMG_PATH"

xcodebuild \
  -project "$ROOT_DIR/TimeBlocker.xcodeproj" \
  -scheme TimeBlocker \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$OUTPUT_DIR/DerivedData" \
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
hdiutil create \
  -volname TimeBlocker \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo "Created: $DMG_PATH"
