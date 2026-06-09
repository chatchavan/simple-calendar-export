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
RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"

# ── Preflight ────────────────────────────────────────────────────────────────
if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: $BUNDLE not found. Run build.sh first."
  exit 1
fi

echo "Packaging $APP_NAME.dmg..."

# ── 1. Generate background image (pure Python stdlib — no dependencies) ───────
BG_PNG="$BUILD_DIR/dmg_background.png"

python3 << PYEOF
import struct, zlib

W, H = 540, 320

# Colours
BG   = (245, 245, 247)   # #f5f5f7  Apple light grey
LINE = (220, 220, 222)   # subtle separator below icons
TEXT = (120, 120, 128)   # muted label colour

# ── tiny 5×7 bitmap font (A-Z, a-z, space, arrow →) ─────────────────────────
GLYPHS = {
' ':  0b00000_00000_00000_00000_00000_00000_00000,
'D':  0b11100_10010_10001_10001_10001_10010_11100,
'r':  0b00000_00000_10110_11001_10000_10000_10000,
'a':  0b00000_00000_01110_00001_01111_10001_01111,
'g':  0b00000_00000_01110_10001_10001_01111_00001,
't':  0b01000_01000_11110_01000_01000_01001_00110,
'o':  0b00000_00000_01110_10001_10001_10001_01110,
'h':  0b10000_10000_10110_11001_10001_10001_10001,
'e':  0b00000_00000_01110_10001_11111_10000_01110,
'A':  0b00100_01010_10001_10001_11111_10001_10001,
'p':  0b00000_00000_11110_10001_10001_11110_10000,
'l':  0b01100_00100_00100_00100_00100_00100_01110,
'i':  0b00100_00000_01100_00100_00100_00100_01110,
'c':  0b00000_00000_01110_10000_10000_10000_01110,
'n':  0b00000_00000_10110_11001_10001_10001_10001,
's':  0b00000_00000_01110_10000_01110_00001_11110,
'f':  0b00110_01000_11110_01000_01000_01000_01000,
'd':  0b00001_00001_01101_10011_10001_10011_01101,
'F':  0b11111_10000_11110_10000_10000_10000_10000,
'u':  0b00000_00000_10001_10001_10001_10011_01101,
'y':  0b00000_00000_10001_10001_01111_00001_01110,
'I':  0b01110_00100_00100_00100_00100_00100_01110,
'k':  0b10000_10000_10010_10100_11000_10100_10010,
'→': 0b00000_00100_00010_11111_00010_00100_00000,  # →
}

def glyph_pixels(ch, ox, oy, pixels):
    bits = GLYPHS.get(ch)
    if bits is None:
        return
    for row in range(7):
        for col in range(5):
            if bits & (1 << (34 - row*5 - col)):
                px = ox + col
                py = oy + row
                if 0 <= px < W and 0 <= py < H:
                    pixels[py][px] = TEXT

def draw_text(text, x, y, pixels):
    cx = x
    for ch in text:
        glyph_pixels(ch, cx, y, pixels)
        cx += 6  # 5px glyph + 1px spacing

# ── Build pixel buffer ───────────────────────────────────────────────────────
pixels = [[BG] * W for _ in range(H)]

# Thin separator line at y=245 (below the icons at y≈150+100px)
for x in range(W):
    pixels[245][x] = LINE

# Centred instruction text at y=260
label = "Drag to the Applications folder  →"
text_w = len(label) * 6 - 1
draw_text(label, (W - text_w) // 2, 260, pixels)

# ── Write PNG ────────────────────────────────────────────────────────────────
def png_chunk(name, data):
    c = name + data
    return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

rows = b''
for row in pixels:
    rows += b'\x00' + b''.join(bytes(p) for p in row)

with open('$BG_PNG', 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n')
    f.write(png_chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)))
    f.write(png_chunk(b'IDAT', zlib.compress(rows, 9)))
    f.write(png_chunk(b'IEND', b''))

print("Background image written.")
PYEOF

if [[ ! -f "$BG_PNG" ]]; then
  echo "WARNING: background image generation failed — DMG will have no background."
fi

# ── 2. Create a read-write DMG ───────────────────────────────────────────────
rm -f "$RW_DMG" "$DMG_OUT"
hdiutil create \
  -volname "$APP_NAME" \
  -size 30m \
  -fs "HFS+" \
  -ov \
  "$RW_DMG"

# ── 3. Mount, populate, set Finder layout ────────────────────────────────────
MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -noautoopen -quiet

# Copy app and Applications symlink
cp -r "$BUNDLE" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Copy background image and hide the folder from Finder
if [[ -f "$BG_PNG" ]]; then
  mkdir -p "$MOUNT_DIR/.background"
  cp "$BG_PNG" "$MOUNT_DIR/.background/background.png"
  chflags hidden "$MOUNT_DIR/.background"   # invisible in Finder
fi

# ── Apply saved layout template, or do first-time manual setup ───────────────
TEMPLATE="$SCRIPT_DIR/Resources/dmg_template.ds_store"

if [[ -f "$TEMPLATE" ]]; then
  cp "$TEMPLATE" "$MOUNT_DIR/.DS_Store"
  echo "Finder layout applied from template ✓"
else
  echo ""
  echo "First-time layout setup — opening DMG in Finder..."
  open "$MOUNT_DIR"
  echo ""
  echo "Set up the window layout in Finder, then come back here:"
  echo "  1. Resize the window to the size you want"
  echo "  2. Press Cmd+J (View Options)"
  echo "       • Icon size: 100"
  echo "       • Background: Picture"
  echo "         → click the picture box → navigate to .background/background.png"
  echo "         (press Cmd+Shift+. to show hidden files in the picker)"
  echo "  3. Drag '$APP_NAME.app' to the left, 'Applications' to the right"
  echo "  4. Close View Options"
  echo ""
  read -rp "Press Enter when done to save the template and build the DMG... "
  echo ""
  if [[ -f "$MOUNT_DIR/.DS_Store" ]]; then
    cp "$MOUNT_DIR/.DS_Store" "$TEMPLATE"
    echo "Template saved → Resources/dmg_template.ds_store"
    echo "(future runs will skip this step)"
  else
    echo "WARNING: .DS_Store not found — background may not appear in the DMG."
    echo "  If Finder didn't write it, try closing and re-opening the window first."
  fi
fi

DEV_NODE=$(diskutil info "$MOUNT_DIR" 2>/dev/null | awk '/Device Node/{print $3}' | head -1)
if [[ -n "$DEV_NODE" ]]; then
  hdiutil detach "$DEV_NODE" -quiet
else
  hdiutil detach "$MOUNT_DIR" -quiet
fi

# ── 4. Convert to compressed read-only DMG ───────────────────────────────────
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_OUT"
rm -f "$RW_DMG"

echo ""
echo "Done: $DMG_OUT ($(du -sh "$DMG_OUT" | cut -f1))"
echo ""
echo "To install: open the DMG, drag '$APP_NAME' to Applications."
echo "Recipient must right-click → Open on first launch (no Developer ID)."
