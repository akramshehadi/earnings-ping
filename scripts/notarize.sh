#!/usr/bin/env bash
#
# Notarize and staple an Earnings Ping .dmg.
#
# BLOCKED UNTIL ENROLLMENT (issue 08): notarization requires an Apple Developer
# Program account ($99/yr). This script is the ready-to-run scaffold.
#
# One-time credential setup (stores an App Store Connect API key or an
# app-specific password in the login keychain under a named profile):
#
#   xcrun notarytool store-credentials "EarningsPing" \
#     --apple-id "you@example.com" --team-id "TEAMID" \
#     --password "app-specific-password"
#
# Then:  scripts/notarize.sh build/dist/EarningsPing-X.Y.Z.dmg
set -euo pipefail

DMG="${1:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-EarningsPing}"

[ -n "$DMG" ]  || { echo "usage: $0 <path-to-dmg>" >&2; exit 2; }
[ -f "$DMG" ]  || { echo "!! Not found: $DMG" >&2; exit 1; }

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "!! No notarytool credentials for profile '$NOTARY_PROFILE'." >&2
  echo "   This step needs Apple Developer Program enrollment (issue 08)." >&2
  echo "   Set up creds with 'xcrun notarytool store-credentials', then retry." >&2
  exit 1
fi

echo "==> Submitting $DMG for notarization (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Notarized & stapled: $DMG"
