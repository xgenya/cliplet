#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
BIN_DIR="${1:?Usage: package-app.sh BIN_DIR APP_DIR debug|release}"
APP_DIR="${2:?Missing application path}"
CONFIGURATION="${3:?Missing configuration}"
[[ "$APP_DIR" == *.app ]] || { print -u2 "Output must be an .app path"; exit 2; }
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || exit 2
VERSION="$(<"$ROOT_DIR/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD)}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]] || { print -u2 'Invalid version/build number'; exit 2; }
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
mkdir -p "${APP_DIR:h}"
STAGING_DIR="$(mktemp -d "${APP_DIR:h}/.cliplet-package.XXXXXX")"
STAGED_APP="$STAGING_DIR/${APP_DIR:t}"
cleanup() {
    if [[ -e "$STAGING_DIR/previous.app" && ! -e "$APP_DIR" ]]; then
        mv "$STAGING_DIR/previous.app" "$APP_DIR"
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/Cliplet" "$STAGED_APP/Contents/MacOS/Cliplet"
cp -R "$BIN_DIR/Cliplet_ClipletKit.bundle" "$STAGED_APP/Contents/Resources/"
cp "$ROOT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/"
for LANGUAGE in en zh-Hans; do
    mkdir -p "$STAGED_APP/Contents/Resources/$LANGUAGE.lproj"
    cp "$ROOT_DIR/Resources/$LANGUAGE.lproj/InfoPlist.strings" "$STAGED_APP/Contents/Resources/$LANGUAGE.lproj/"
done
PLIST="$STAGED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
if [[ "$CONFIGURATION" == debug ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.clipboardnative.macos.dev' "$PLIST"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName Cliplet Dev' "$PLIST"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Cliplet Dev' "$PLIST"
    for LANGUAGE in en zh-Hans; do
        printf '"CFBundleDisplayName" = "Cliplet Dev";\n"CFBundleName" = "Cliplet Dev";\n' > "$STAGED_APP/Contents/Resources/$LANGUAGE.lproj/InfoPlist.strings"
    done
fi
ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")
[[ -s "$STAGED_APP/Contents/Resources/${ICON_NAME%.icns}.icns" ]] || { print -u2 'Missing icon'; exit 1; }
SIGN_OPTIONS=()
if [[ "$SIGNING_IDENTITY" != - ]]; then SIGN_OPTIONS=(--options runtime --timestamp); fi
codesign --force --sign "$SIGNING_IDENTITY" "${SIGN_OPTIONS[@]}" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
# Keep the previous, verified package until its replacement has passed validation.
if [[ -e "$APP_DIR" ]]; then mv "$APP_DIR" "$STAGING_DIR/previous.app"; fi
mv "$STAGED_APP" "$APP_DIR"
print "$APP_DIR"
