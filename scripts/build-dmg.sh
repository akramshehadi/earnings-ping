#!/usr/bin/env bash
#
# Build a distributable Earnings Ping .dmg.
#
# Pipeline: regenerate project -> build Release -> (optionally) Developer ID
# re-sign with hardened runtime -> stage with an /Applications drop link ->
# hdiutil into a compressed .dmg -> (optionally) sign the .dmg.
#
# SIGNING IS OPTIONAL HERE ON PURPOSE. We are not yet enrolled in the Apple
# Developer Program (issue 08), so by default this produces an UNSIGNED, NOT
# notarized .dmg suitable only for local smoke-testing — Gatekeeper will warn on
# other Macs. Once enrolled, export these and re-run to get a signed .app + .dmg
# (then run scripts/notarize.sh):
#
#   export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
#
# Hardened runtime is always applied when signing because notarization requires
# it. No extra entitlements are needed for the current app; the Sparkle work
# (deferred to its own issue) will add the entitlements Sparkle requires.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="EarningsPing"
APP_NAME="EarningsPing"
VOL_NAME="Earnings Ping"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DERIVED="$BUILD_DIR/DerivedData"
DIST="$BUILD_DIR/dist"

MARKETING_VERSION="$(/usr/bin/awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
BUILD_NUMBER="$(/usr/bin/awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)"
DMG="$DIST/${APP_NAME}-${MARKETING_VERSION}.dmg"

echo "==> Earnings Ping ${MARKETING_VERSION} (build ${BUILD_NUMBER})"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Building Release"
rm -rf "$DERIVED"
xcodebuild \
  -project EarningsPing.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' \
  build >/dev/null

APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "!! Build did not produce $APP" >&2; exit 1; }

if [ -n "${DEVELOPER_ID_APP:-}" ]; then
  echo "==> Re-signing with Developer ID + hardened runtime"
  codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APP" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "!! DEVELOPER_ID_APP not set — producing an UNSIGNED .dmg (local testing"
  echo "   only; Gatekeeper will warn elsewhere). See issue 08 / docs/releasing.md."
fi

echo "==> Staging disk image contents"
rm -rf "$DIST"
mkdir -p "$DIST"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

if [ -n "${DEVELOPER_ID_APP:-}" ]; then
  echo "==> Signing .dmg"
  codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG"
fi

echo "==> Done: $DMG"
echo "    Next (requires enrollment): scripts/notarize.sh \"$DMG\""
