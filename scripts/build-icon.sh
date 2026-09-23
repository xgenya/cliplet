#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
ICONSET_DIR="$ROOT_DIR/build/Cliplet.iconset"
mkdir -p "$ICONSET_DIR"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT_DIR/Sources/Cliplet/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ROOT_DIR/Sources/Cliplet/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Resources/AppIcon.icns"
