#!/usr/bin/env bash
# Updates packaging/homebrew/Casks/document-studio.rb version, url, sha256.
#
#   bash scripts/release/update_homebrew_cask.sh 1.0.3 dist/macos/DocumentStudio-1.0.3-macos.dmg

set -euo pipefail
VERSION="${1:?version e.g. 1.0.3}"
DMG="${2:?path to .dmg}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CASK="$ROOT/packaging/homebrew/Casks/document-studio.rb"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
URL="https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v${VERSION}/DocumentStudio-${VERSION}-macos.dmg"

sed -i "s/^  version \".*\"/  version \"${VERSION}\"/" "$CASK"
sed -i "s|^  url \".*\"|  url \"${URL}\"|" "$CASK"
sed -i "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "$CASK"

echo "Updated $CASK"
echo "  version $VERSION"
echo "  sha256  $SHA"
