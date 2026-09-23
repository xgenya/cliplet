#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || { print -u2 'Use debug or release'; exit 2; }
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/cliplet-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/cliplet-swiftpm-cache}"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# Preserve the actual SDK for AppKit's Liquid Glass behavior while keeping
# the macOS 14 deployment target. Native SwiftPM can otherwise conflate them.
BUILD_ARGS=(-c "$CONFIGURATION" --arch arm64 --disable-sandbox --scratch-path .build --sdk "$MACOS_SDK_PATH"
    -Xswiftc -warnings-as-errors -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$MACOS_SDK_VERSION")
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" || "$ROOT_DIR/Sources/Cliplet/Resources/AppIcon.png" -nt "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    "$ROOT_DIR/scripts/build-icon.sh"
fi
APP_NAME=Cliplet
if [[ "$CONFIGURATION" == debug ]]; then APP_NAME='Cliplet Dev'; fi
"$ROOT_DIR/scripts/package-app.sh" "$BIN_DIR" "$ROOT_DIR/build/$APP_NAME.app" "$CONFIGURATION"
if [[ "$CONFIGURATION" == release ]]; then
    mkdir -p "$ROOT_DIR/build/symbols"
    xcrun dsymutil "$BIN_DIR/Cliplet" -o "$ROOT_DIR/build/symbols/Cliplet.dSYM"
fi
