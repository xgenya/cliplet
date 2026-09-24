#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || { print -u2 'Use debug or release'; exit 2; }
cd "$ROOT_DIR"
"$ROOT_DIR/scripts/swift.sh" build -c "$CONFIGURATION"
BIN_DIR="$("$ROOT_DIR/scripts/swift.sh" build -c "$CONFIGURATION" --show-bin-path)"
if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" || "$ROOT_DIR/Sources/ClipletKit/Resources/AppIcon.png" -nt "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    "$ROOT_DIR/scripts/build-icon.sh"
fi
APP_NAME=Cliplet
if [[ "$CONFIGURATION" == debug ]]; then APP_NAME='Cliplet Dev'; fi
"$ROOT_DIR/scripts/package-app.sh" "$BIN_DIR" "$ROOT_DIR/build/$APP_NAME.app" "$CONFIGURATION"
if [[ "$CONFIGURATION" == release ]]; then
    mkdir -p "$ROOT_DIR/build/symbols"
    xcrun dsymutil "$BIN_DIR/Cliplet" -o "$ROOT_DIR/build/symbols/Cliplet.dSYM"
fi
