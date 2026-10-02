#!/usr/bin/env bash
# After CI uploads a macOS DMG to GitHub Releases, refresh the Homebrew cask.
#
#   bash scripts/release/sync_homebrew_cask_from_release.sh 1.0.3
#   bash scripts/release/sync_homebrew_cask_from_release.sh 1.0.3 /tmp/out.dmg
#
# Downloads DocumentStudio-<ver>-macos.dmg (unless path given), updates
# packaging/homebrew/Casks/document-studio.rb version/url/sha256.

set -euo pipefail

VERSION="${1:?version e.g. 1.0.3}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${DS_GITHUB_REPO:-tejashvi-kumawat/DocumentStudio}"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/DocumentStudio-${VERSION}-macos.dmg"
DMG="${2:-}"

TMP=""
cleanup() {
  if [[ -n "$TMP" && -d "$TMP" ]]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

if [[ -z "$DMG" ]]; then
  TMP="$(mktemp -d)"
  DMG="$TMP/DocumentStudio-${VERSION}-macos.dmg"
  echo "Downloading $URL"
  curl -fL --retry 3 -o "$DMG" "$URL"
fi

bash "$ROOT/scripts/release/update_homebrew_cask.sh" "$VERSION" "$DMG"
echo
echo "Next for Homebrew tap:"
echo "  1. Copy packaging/homebrew/Casks/document-studio.rb → homebrew-tap/Casks/"
echo "  2. git commit && git push in the tap repo"
echo "  3. brew update && brew upgrade --cask document-studio"
