#!/usr/bin/env bash
# Refresh packaging/homebrew/Formula/document-studio.rb from a GitHub Release .deb
#
#   bash scripts/release/update_homebrew_formula.sh 1.0.3
#   bash scripts/release/update_homebrew_formula.sh 1.0.3 /path/to/document-studio_1.0.3_amd64.deb

set -euo pipefail

VERSION="${1:?version e.g. 1.0.3}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${DS_GITHUB_REPO:-tejashvi-kumawat/DocumentStudio}"
FORMULA="$ROOT/packaging/homebrew/Formula/document-studio.rb"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/document-studio_${VERSION}_amd64.deb"
DEB="${2:-}"

TMP=""
cleanup() {
  if [[ -n "$TMP" && -d "$TMP" ]]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

if [[ -z "$DEB" ]]; then
  TMP="$(mktemp -d)"
  DEB="$TMP/document-studio_${VERSION}_amd64.deb"
  echo "Downloading $URL"
  curl -fL --retry 3 -o "$DEB" "$URL"
fi

SHA="$(sha256sum "$DEB" | awk '{print $1}')"

mkdir -p "$(dirname "$FORMULA")"
if [[ ! -f "$FORMULA" ]]; then
  echo "Missing template: $FORMULA" >&2
  exit 1
fi

# Update version, url, sha256 (url may use #{version} or a literal).
sed -i "s|^  version \".*\"|  version \"${VERSION}\"|" "$FORMULA"
sed -i "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" "$FORMULA"
sed -i "s|^  url \".*document-studio_.*_amd64\\.deb\"|  url \"${URL}\"|" "$FORMULA"

echo "Updated $FORMULA"
echo "  version $VERSION"
echo "  sha256  $SHA"
echo "  url     $URL"
