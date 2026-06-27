#!/usr/bin/env bash
# Generates AppIcon.appiconset PNGs from the vinyl record asset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Vinyl/Assets.xcassets/Pixel/pixel_record.imageset/vinyl.png"
ICONSET="$ROOT/Vinyl/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE" ]]; then
  echo "Source image not found: $SOURCE" >&2
  exit 1
fi

mkdir -p "$ICONSET"

generate() {
  local filename="$1"
  local size="$2"
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$filename" >/dev/null
  echo "Generated $filename (${size}x${size})"
}

generate icon_16x16.png 16
generate icon_16x16@2x.png 32
generate icon_32x32.png 32
generate icon_32x32@2x.png 64
generate icon_128x128.png 128
generate icon_128x128@2x.png 256
generate icon_256x256.png 256
generate icon_256x256@2x.png 512
generate icon_512x512.png 512
generate icon_512x512@2x.png 1024

cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

echo "App icon set updated at $ICONSET"
