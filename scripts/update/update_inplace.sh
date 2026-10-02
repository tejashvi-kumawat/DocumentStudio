#!/usr/bin/env bash
# In-place update for Document Studio (Linux / macOS).
# Prefer the app CLI when installed:
#   document_studio --update
#   document-studio --update
#
# This script is a thin package-manager / GitHub fallback for shells.

set -euo pipefail

REPO="tejashvi-kumawat/DocumentStudio"
APP_BIN=""
for c in document_studio document-studio; do
  if command -v "$c" >/dev/null 2>&1; then
    APP_BIN="$c"
    break
  fi
done

if [[ -n "$APP_BIN" ]]; then
  exec "$APP_BIN" --update
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

latest_tag() {
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1
}

TAG="$(latest_tag)"
VERSION="${TAG#v}"
if [[ -z "$VERSION" ]]; then
  echo "Could not resolve latest release tag." >&2
  exit 1
fi

echo "Latest release: $VERSION"

case "$OS" in
  Darwin)
    if command -v brew >/dev/null 2>&1 && brew list --cask document-studio >/dev/null 2>&1; then
      exec brew upgrade --cask document-studio
    fi
    DMG_URL="https://github.com/${REPO}/releases/download/v${VERSION}/DocumentStudio-${VERSION}-macos.dmg"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    echo "Downloading $DMG_URL"
    curl -fL "$DMG_URL" -o "$TMP/DocumentStudio.dmg"
    hdiutil attach "$TMP/DocumentStudio.dmg" -nobrowse -quiet -mountpoint "$TMP/mnt"
    APP_SRC="$(find "$TMP/mnt" -maxdepth 1 -name '*.app' -type d | head -1)"
    if [[ -z "$APP_SRC" ]]; then
      echo "No .app in DMG" >&2
      hdiutil detach "$TMP/mnt" -quiet || true
      exit 1
    fi
    DEST="/Applications/$(basename "$APP_SRC")"
    echo "Replacing $DEST"
    rm -rf "$DEST"
    cp -R "$APP_SRC" "$DEST"
    hdiutil detach "$TMP/mnt" -quiet
    echo "Updated in place."
    ;;
  Linux)
    if command -v flatpak >/dev/null 2>&1 && flatpak info com.documentstudio.document_studio >/dev/null 2>&1; then
      exec flatpak update -y com.documentstudio.document_studio
    fi
    DEB_URL="https://github.com/${REPO}/releases/download/v${VERSION}/document-studio_${VERSION}_amd64.deb"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    echo "Downloading $DEB_URL"
    curl -fL "$DEB_URL" -o "$TMP/document-studio.deb"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -y "$TMP/document-studio.deb"
    else
      sudo dpkg -i "$TMP/document-studio.deb"
    fi
    echo "Updated in place."
    ;;
  *)
    echo "Unsupported OS: $OS (arch=$ARCH)" >&2
    exit 1
    ;;
esac
