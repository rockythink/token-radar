#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_SVG="$ROOT_DIR/source/token-radar-app-icon.svg"
SYMBOL_SVG="$ROOT_DIR/source/token-radar-symbol-template.svg"
TMP_WHITE_SYMBOL="$ROOT_DIR/.tmp-token-radar-symbol-white.svg"
PNG_DIR="$ROOT_DIR/png"
ICONSET_DIR="$ROOT_DIR/macOS/TokenRadar.iconset"
APPICONSET_DIR="$ROOT_DIR/macOS/TokenRadar.appiconset"
ICNS_PATH="$ROOT_DIR/macOS/TokenRadar.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required. Install librsvg first." >&2
  exit 1
fi

mkdir -p "$PNG_DIR" "$ICONSET_DIR" "$APPICONSET_DIR"

sed 's/#000000/#FFFFFF/g' "$SYMBOL_SVG" >"$TMP_WHITE_SYMBOL"
trap 'rm -f "$TMP_WHITE_SYMBOL"' EXIT

for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$ICON_SVG" -o "$PNG_DIR/token-radar-logo-${size}.png"
  rsvg-convert -w "$size" -h "$size" "$SYMBOL_SVG" -o "$PNG_DIR/token-radar-symbol-${size}.png"
  rsvg-convert -w "$size" -h "$size" "$TMP_WHITE_SYMBOL" -o "$PNG_DIR/token-radar-symbol-white-${size}.png"
done

rsvg-convert -w 16 -h 16 "$ICON_SVG" -o "$ICONSET_DIR/icon_16x16.png"
rsvg-convert -w 32 -h 32 "$ICON_SVG" -o "$ICONSET_DIR/icon_16x16@2x.png"
rsvg-convert -w 32 -h 32 "$ICON_SVG" -o "$ICONSET_DIR/icon_32x32.png"
rsvg-convert -w 64 -h 64 "$ICON_SVG" -o "$ICONSET_DIR/icon_32x32@2x.png"
rsvg-convert -w 128 -h 128 "$ICON_SVG" -o "$ICONSET_DIR/icon_128x128.png"
rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$ICONSET_DIR/icon_128x128@2x.png"
rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$ICONSET_DIR/icon_256x256.png"
rsvg-convert -w 512 -h 512 "$ICON_SVG" -o "$ICONSET_DIR/icon_256x256@2x.png"
rsvg-convert -w 512 -h 512 "$ICON_SVG" -o "$ICONSET_DIR/icon_512x512.png"
rsvg-convert -w 1024 -h 1024 "$ICON_SVG" -o "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

cp "$ICONSET_DIR/icon_16x16.png" "$APPICONSET_DIR/AppIcon-16.png"
cp "$ICONSET_DIR/icon_16x16@2x.png" "$APPICONSET_DIR/AppIcon-16@2x.png"
cp "$ICONSET_DIR/icon_32x32.png" "$APPICONSET_DIR/AppIcon-32.png"
cp "$ICONSET_DIR/icon_32x32@2x.png" "$APPICONSET_DIR/AppIcon-32@2x.png"
cp "$ICONSET_DIR/icon_128x128.png" "$APPICONSET_DIR/AppIcon-128.png"
cp "$ICONSET_DIR/icon_128x128@2x.png" "$APPICONSET_DIR/AppIcon-128@2x.png"
cp "$ICONSET_DIR/icon_256x256.png" "$APPICONSET_DIR/AppIcon-256.png"
cp "$ICONSET_DIR/icon_256x256@2x.png" "$APPICONSET_DIR/AppIcon-256@2x.png"
cp "$ICONSET_DIR/icon_512x512.png" "$APPICONSET_DIR/AppIcon-512.png"
cp "$ICONSET_DIR/icon_512x512@2x.png" "$APPICONSET_DIR/AppIcon-512@2x.png"

echo "Token Radar brand assets exported."
