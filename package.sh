#!/bin/bash
# package.sh — create a distributable DMG for Simple Calendar Export
# Run build.sh first, then run this script.
# Output: build/Simple Calendar Export.dmg

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="Simple Calendar Export"
BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_OUT="$BUILD_DIR/$APP_NAME.dmg"

# Verify the app exists
if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: $BUNDLE not found. Run build.sh first."
  exit 1
fi

echo "Packaging $APP_NAME.dmg..."

# Stage: app + shortcut to /Applications for drag-to-install
STAGING=$(mktemp -d)
cp -r "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Remove existing DMG
rm -f "$DMG_OUT"

# Create compressed DMG
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

rm -rf "$STAGING"

echo ""
echo "Done: $DMG_OUT ($(du -sh "$DMG_OUT" | cut -f1))"
echo ""
echo "To install: open the DMG, drag '$APP_NAME' to Applications."
echo "Recipient must right-click → Open on first launch (no Developer ID)."
