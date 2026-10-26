#!/bin/bash
# Builds a release TidyDesk.app into build/. Usage: scripts/build-app.sh [--run]
# Signing: by default an Apple Development certificate matching your git email is used if present, else ad-hoc.
# Override: SIGN_IDENTITY="Apple Development: Name (TEAMID)" keeps Accessibility permission stable
# across rebuilds. Default is ad-hoc ("-"); macOS may ask you to re-grant access after each rebuild.
# For distribution use SIGN_IDENTITY="Developer ID Application: ..." DIST=1 (see docs/RELEASE.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../Config/branding.env
source "$ROOT/Config/branding.env"
# Optional per-machine settings (git-ignored), e.g. SIGN_IDENTITY="Apple Development: Name (TEAMID)".
# A stable identity keeps the Accessibility grant valid across rebuilds.
if [[ -f "$ROOT/Config/local.env" ]]; then source "$ROOT/Config/local.env"; fi
# Without an explicit identity, use the Apple Development certificate whose name contains your git email, so
# the Accessibility grant survives rebuilds. Set SIGN_IDENTITY="-" to force ad-hoc signing.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    EMAIL="$(git -C "$ROOT" config user.email 2>/dev/null || true)"
    if [[ -n "$EMAIL" ]]; then
        SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -F "Apple Development: $EMAIL" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
        if [[ -n "$SIGN_IDENTITY" ]]; then echo "Signing with: $SIGN_IDENTITY (matched your git email)"; fi
    fi
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

ARCHS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release --package-path "$ROOT" ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c release --package-path "$ROOT" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TidyDesk" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

sed -e "s|@APP_NAME@|$APP_NAME|g" -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" -e "s|@EXECUTABLE_NAME@|$EXECUTABLE_NAME|g" \
    -e "s|@VERSION@|$VERSION|g" -e "s|@BUILD@|$BUILD|g" -e "s|@MIN_MACOS@|$MIN_MACOS|g" \
    -e "s|@DEVELOPER_NAME@|$DEVELOPER_NAME|g" "$ROOT/Config/Info.plist.template" > "$APP/Contents/Info.plist"

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

SIGN_ARGS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "${DIST:-0}" == "1" ]]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then open "$APP"; fi
