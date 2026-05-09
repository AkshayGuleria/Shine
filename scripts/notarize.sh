#!/usr/bin/env bash
# Usage: ./scripts/notarize.sh <path-to-Shine.app>
# Prerequisites:
#   1. Developer ID Application certificate in Keychain
#   2. App-specific password stored:
#        xcrun notarytool store-credentials "shine-notary" \
#          --apple-id "your@apple.id" \
#          --team-id "XXXXXXXXXX" \
#          --password "xxxx-xxxx-xxxx-xxxx"
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
