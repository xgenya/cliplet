#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
APP_DIR="${1:-$ROOT_DIR/build/Cliplet.app}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp/}cliplet-package-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/output"
cp "$APP_DIR/Contents/MacOS/Cliplet" "$TEST_ROOT/bin/Cliplet"
cp -R "$APP_DIR/Contents/Resources/Cliplet_Cliplet.bundle" "$TEST_ROOT/bin/"
SOURCE_BUNDLE="$TEST_ROOT/bin/Cliplet_Cliplet.bundle"
print 'synthetic obsolete resource' > "$SOURCE_BUNDLE/obsolete.txt"
TARGET_APP="$TEST_ROOT/output/Cliplet.app"
"$ROOT_DIR/scripts/package-app.sh" "$TEST_ROOT/bin" "$TARGET_APP" release
[[ -f "$TARGET_APP/Contents/Resources/Cliplet_Cliplet.bundle/obsolete.txt" ]]
rm "$SOURCE_BUNDLE/obsolete.txt"
"$ROOT_DIR/scripts/package-app.sh" "$TEST_ROOT/bin" "$TARGET_APP" release
[[ ! -e "$TARGET_APP/Contents/Resources/Cliplet_Cliplet.bundle/obsolete.txt" ]]
# A failed package must not replace the previous valid application.
BEFORE="$(shasum -a 256 "$TARGET_APP/Contents/MacOS/Cliplet")"
if "$ROOT_DIR/scripts/package-app.sh" "$TEST_ROOT/missing" "$TARGET_APP" release > "$TEST_ROOT/expected-failure.log" 2>&1; then
    print -u2 'Packaging unexpectedly accepted missing input'; exit 1
fi
[[ "$BEFORE" == "$(shasum -a 256 "$TARGET_APP/Contents/MacOS/Cliplet")" ]]
codesign --verify --deep --strict "$TARGET_APP"
# The executable explicitly requires its packaged resource bundle. This check cannot
# pass by falling back to a resource bundle at its original build path.
python3 "$ROOT_DIR/scripts/smoke-app.py" "$TARGET_APP"
print 'Clean packaging and relocation checks passed'
