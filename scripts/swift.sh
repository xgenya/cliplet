#!/bin/zsh
# Runs a SwiftPM subcommand with the project's shared build settings.
# Usage: swift.sh build|test|run [SwiftPM arguments...]
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/cliplet-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/cliplet-swiftpm-cache}"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SUBCOMMAND="${1:?Usage: swift.sh build|test|run [arguments...]}"
shift
# Preserve the actual SDK for AppKit's Liquid Glass behavior while keeping
# the macOS 14 deployment target. Native SwiftPM can otherwise conflate them.
exec swift "$SUBCOMMAND" --arch arm64 --disable-sandbox --scratch-path .build --sdk "$MACOS_SDK_PATH" \
    -Xswiftc -warnings-as-errors -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$MACOS_SDK_VERSION" \
    "$@"
