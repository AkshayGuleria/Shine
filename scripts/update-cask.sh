#!/usr/bin/env bash
# Updates Casks/shine.rb in homebrew-tap with new version and sha256.
# Called from the release workflow after the zip is created.
# Requires HOMEBREW_TAP_TOKEN env var with repo write access to homebrew-tap.
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <sha256>}"
SHA256="${2:?Usage: $0 <version> <sha256>}"
TAP_REPO="AkshayGuleria/homebrew-tap"
CASK_PATH="Casks/shine.rb"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

git clone \
  "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git" \
  "$TMP/tap"

cd "$TMP/tap"

sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "$CASK_PATH"
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$CASK_PATH"

git config user.email "github-actions[bot]@users.noreply.github.com"
git config user.name "github-actions[bot]"
git add "$CASK_PATH"
git commit -m "chore: bump shine to ${VERSION}"
git push
