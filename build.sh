#!/bin/bash
# build.sh — compile Simple Calendar Export.app into build/
# Usage: bash build.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
BUNDLE="$BUILD_DIR/Simple Calendar Export.app"
BINARY="$BUNDLE/Contents/MacOS/CalendarExportGUI"
RESOURCES_DST="$BUNDLE/Contents/Resources"

echo "Building Simple Calendar Export.app..."

# Clean up old ~/Applications install if it exists
for old in \
  ~/Applications/"Simple Calendar Export.app" \
  ~/Applications/CalendarExportGUI.app; do
  if [[ -d "$old" ]]; then
    rm -rf "$old"
    echo "Removed old $(basename "$old")"
  fi
done

mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$RESOURCES_DST"

# Info.plist
cat > "$BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>local.calendar-export-gui</string>
  <key>CFBundleName</key>
  <string>Simple Calendar Export</string>
  <key>CFBundleDisplayName</key>
  <string>Simple Calendar Export</string>
  <key>CFBundleExecutable</key>
  <string>CalendarExportGUI</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Simple Calendar Export reads your calendar events for export.</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <false/>
</dict>
</plist>
EOF

# Hash Swift sources; skip compile+re-sign if nothing changed.
# Re-signing invalidates the TCC permission entry, so we avoid it when possible.
HASH_FILE="$BUILD_DIR/.source_hash"
CURRENT_HASH=$(cat "$SCRIPT_DIR/Sources/"*.swift | md5)
PREV_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")

if [[ "$CURRENT_HASH" == "$PREV_HASH" && -f "$BINARY" ]]; then
  echo "Sources unchanged — skipping compile + re-sign (TCC permission preserved)"
else
  swiftc "$SCRIPT_DIR/Sources/"*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework WebKit \
    -framework EventKit \
    -target arm64-apple-macosx15.0 \
    -o "$BINARY.arm64" \
    -O
  swiftc "$SCRIPT_DIR/Sources/"*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework WebKit \
    -framework EventKit \
    -target x86_64-apple-macosx15.0 \
    -o "$BINARY.x86_64" \
    -O
  lipo -create "$BINARY.arm64" "$BINARY.x86_64" -output "$BINARY"
  rm "$BINARY.arm64" "$BINARY.x86_64"
  echo "Compiled: $BINARY ($(du -sh "$BINARY" | cut -f1), universal)"
  codesign --sign - --force "$BUNDLE"
  echo "Signed:   $(codesign -dv "$BUNDLE" 2>&1 | grep Identifier)"
  echo "$CURRENT_HASH" > "$HASH_FILE"
  echo ""
  echo "NOTE: Re-signed. If calendar access breaks, re-grant in:"
  echo "  System Settings → Privacy & Security → Calendars → Simple Calendar Export → Full Access"
fi

# Always sync resources (HTML/CSS changes don't require re-sign)
cp "$SCRIPT_DIR/Resources/"* "$RESOURCES_DST/" 2>/dev/null || true

# App icon — convert Design/1x/Artboard 1.png → AppIcon.icns if source exists
ICON_SRC="$SCRIPT_DIR/Design/1x/Artboard 1.png"
ICON_DST="$RESOURCES_DST/AppIcon.icns"
if [[ -f "$ICON_SRC" && ! -f "$ICON_DST" ]]; then
  echo "Building AppIcon.icns..."
  ICONSET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON_DST"
  rm -rf "$(dirname "$ICONSET")"
  echo "Icon:     $ICON_DST"
fi

echo ""
echo "Done. Run: open \"$BUNDLE\""
echo "Or CLI:    \"$BINARY\" --list"
echo ""
echo "First launch will prompt for Calendar access."
echo "If denied: System Settings → Privacy & Security → Calendars → Simple Calendar Export → Full Access"
