#!/usr/bin/env bash
# Notarizes and staples Shine.app for Developer ID distribution.
#
# When to use:
#   Run this after archiving a release build signed with a Developer ID
#   Application certificate. Notarization is required for Gatekeeper to
#   allow the app to run on other Macs without the right-click → Open
#   workaround. The current CI workflow uses ad-hoc signing (no notarization),
#   so this script must be run manually before distributing a signed release.
#
# Usage: ./scripts/notarize.sh <path-to-Shine.app>
#
# Prerequisites:
#   1. Apple Developer Program membership ($99/yr)
#   2. Developer ID Application certificate installed in Keychain
#   3. App-specific password stored in Keychain:
#        xcrun notarytool store-credentials "shine-notary" \
#          --apple-id "your@apple.id" \
#          --team-id "XXXXXXXXXX" \
#          --password "xxxx-xxxx-xxxx-xxxx"
#   4. Build settings: Hardened Runtime ON, Code Sign = Developer ID Application
#
# After stapling, verify with: spctl --assess --verbose Shine.app
# Distribute as .zip or wrap in a .dmg.
set -euo pipefail

APP="${1:?Usage: $0 <Shine.app>}"
BUNDLE_ID="com.akshayguleria.shine"
PROFILE="shine-notary"
ZIP="${APP%.app}.zip"

echo "==> Zipping $APP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to notarytool"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$PROFILE" \
  --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP"

echo "==> Verifying Gatekeeper"
spctl --assess --verbose "$APP"

echo "==> Done. Distribute $APP or wrap in a DMG."
