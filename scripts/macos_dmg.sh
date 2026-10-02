#!/usr/bin/env bash
# Build a macOS .dmg (or .zip fallback) from a Release .app.
# MUST run on macOS after: flutter build macos --release
#
# Usage:
#   scripts/macos_dmg.sh
#   scripts/macos_dmg.sh /path/to/document_studio.app
#
# Optional notarization (Apple ID + app-specific password; paid Developer
# Program typically required for notarization — skip if you don't have it).
# Unsigned / ad-hoc builds: users can right-click the app → Open the first time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS (hdiutil / create-dmg)." >&2
  echo "On this Linux machine you cannot produce a signed macOS build." >&2
  exit 1
fi

VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -1 | sed -E 's/version:[[:space:]]*([^+]+).*/\1/')"
APP="${1:-}"
if [[ -z "$APP" ]]; then
  APP="$(find "$ROOT/build/macos" -name 'document_studio.app' -type d 2>/dev/null | head -1 || true)"
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "document_studio.app not found. Run on a Mac:" >&2
  echo "  bash scripts/macos/package_release.sh" >&2
  echo "  # or: flutter build macos --release && bash scripts/bundle_macos_engines.sh && bash scripts/macos_dmg.sh" >&2
  exit 1
fi
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

OUT_DIR="$ROOT/dist/macos"
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/DocumentStudio-${VERSION}-macos.dmg"
ZIP="$OUT_DIR/DocumentStudio-${VERSION}-macos.zip"
STAGE="$OUT_DIR/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
# Homebrew / Finder-friendly name (Flutter build is document_studio.app).
cp -R "$APP" "$STAGE/Document Studio.app"
ln -sf /Applications "$STAGE/Applications"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Document Studio" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 400 180 \
    "$DMG" \
    "$STAGE" || true
fi

if [[ ! -f "$DMG" ]]; then
  # Built-in fallback — no create-dmg required
  hdiutil create -volname "Document Studio" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

# Always also emit a zip for users who prefer it / CI without hdiutil quirks
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Wrote $DMG"
echo "Wrote $ZIP"
echo
echo "Notarization (optional): requires Apple Developer Program + notarytool."
echo "Without notarization, first launch: right-click app → Open → Open."
