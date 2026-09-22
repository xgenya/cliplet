#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || { print -u2 'Use debug or release'; exit 2; }
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clipboard-native-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/clipboard-native-swiftpm-cache}"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# Some SwiftPM toolchains record the deployment target as the linked SDK.
# AppKit uses this SDK field to select Liquid Glass; preserve the real SDK
# while keeping the macOS 14 runtime floor. Set it at link time, before signing.
BUILD_ARGS=(-c "$CONFIGURATION" --disable-sandbox --scratch-path .build --sdk "$MACOS_SDK_PATH"
    -Xswiftc -warnings-as-errors -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$MACOS_SDK_VERSION")
# Distribution builds explicitly include both supported CPU architectures.
if [[ "${UNIVERSAL:-0}" == 1 ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" || "$ROOT_DIR/Sources/ClipboardNative/Resources/AppIcon.png" -nt "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    "$ROOT_DIR/scripts/build-icon.sh"
fi
APP_NAME=Cliplet
if [[ "$CONFIGURATION" == debug ]]; then APP_NAME='Cliplet Dev'; fi
"$ROOT_DIR/scripts/package-app.sh" "$BIN_DIR" "$ROOT_DIR/build/$APP_NAME.app" "$CONFIGURATION"
if [[ "$CONFIGURATION" == release ]]; then
    mkdir -p "$ROOT_DIR/build/symbols"
    xcrun dsymutil "$BIN_DIR/ClipboardNative" -o "$ROOT_DIR/build/symbols/ClipboardNative.dSYM"
fi
