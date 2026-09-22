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
# Preserve the actual SDK for AppKit's Liquid Glass behavior while keeping
# the macOS 14 deployment target. Native SwiftPM can otherwise conflate them.
BUILD_ARGS=(-c "$CONFIGURATION" --disable-sandbox --scratch-path .build --sdk "$MACOS_SDK_PATH"
    -Xswiftc -warnings-as-errors -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$MACOS_SDK_VERSION")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    # Build one architecture at a time so SwiftPM does not switch linker drivers
    # and reinterpret -Xlinker flags. Preserve each slice before the next build.
    mkdir -p "$ROOT_DIR/.build"
    UNIVERSAL_DIR="$(mktemp -d "$ROOT_DIR/.build/cliplet-universal.XXXXXX")"
    trap 'rm -rf "$UNIVERSAL_DIR"' EXIT
    for ARCHITECTURE in arm64 x86_64; do
        swift build "${BUILD_ARGS[@]}" --arch "$ARCHITECTURE"
        ARCH_BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --arch "$ARCHITECTURE" --show-bin-path)"
        cp "$ARCH_BIN_DIR/ClipboardNative" "$UNIVERSAL_DIR/ClipboardNative-$ARCHITECTURE"
    done
    xcrun lipo -create "$UNIVERSAL_DIR/ClipboardNative-arm64" "$UNIVERSAL_DIR/ClipboardNative-x86_64" \
        -output "$UNIVERSAL_DIR/ClipboardNative"
    cp -R "$ARCH_BIN_DIR/ClipboardNative_ClipboardNative.bundle" "$UNIVERSAL_DIR/"
    BIN_DIR="$UNIVERSAL_DIR"
else
    swift build "${BUILD_ARGS[@]}"
    BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
fi
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
