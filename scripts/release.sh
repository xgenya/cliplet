#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
VERSION="$(<VERSION)"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { print -u2 'Release requires a clean checkout'; exit 2; }
[[ "$(git describe --tags --exact-match HEAD)" == "v$VERSION" ]] || { print -u2 'HEAD tag must match VERSION'; exit 2; }
: "${SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
[[ "$SIGNING_IDENTITY" != - ]] || { print -u2 'Release requires Developer ID signing'; exit 2; }
: "${NOTARY_KEYCHAIN_PROFILE:?Set a notarytool keychain profile}"
NOTARY_OPTIONS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then NOTARY_OPTIONS+=(--keychain "$SIGNING_KEYCHAIN"); fi
make check
UNIVERSAL=1 ./scripts/build-app.sh release
python3 scripts/smoke-app.py build/Cliplet.app
python3 scripts/check-binary.py build/Cliplet.app/Contents/MacOS/ClipboardNative build/symbols/ClipboardNative.dSYM
ARCHITECTURES="$(lipo -archs build/Cliplet.app/Contents/MacOS/ClipboardNative)"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]] || { print -u2 'Missing release architecture'; exit 1; }
OUTPUT_DIR="$ROOT_DIR/build/releases/$VERSION"
[[ ! -e "$OUTPUT_DIR" ]] || { print -u2 'Release output already exists; preserve or move it first'; exit 2; }
mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/Cliplet-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent build/Cliplet.app "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" "${NOTARY_OPTIONS[@]}" --wait
xcrun stapler staple build/Cliplet.app
xcrun stapler validate build/Cliplet.app
spctl --assess --type execute --verbose build/Cliplet.app
rm "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent build/Cliplet.app "$ARCHIVE"
ditto -c -k --keepParent build/symbols/ClipboardNative.dSYM "$OUTPUT_DIR/Cliplet-$VERSION.dSYM.zip"
{
    print "version=$VERSION"
    print "build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/Cliplet.app/Contents/Info.plist)"
    print "commit=$(git rev-parse HEAD)"
    print "architectures=$ARCHITECTURES"
    xcodebuild -version
    xcrun dwarfdump --uuid build/Cliplet.app/Contents/MacOS/ClipboardNative
    xcrun dwarfdump --uuid build/symbols/ClipboardNative.dSYM
} > "$OUTPUT_DIR/build-info.txt"
(cd "$OUTPUT_DIR" && shasum -a 256 ./*.zip > SHA256SUMS)
print "Signed, notarized release artifacts: $OUTPUT_DIR"
