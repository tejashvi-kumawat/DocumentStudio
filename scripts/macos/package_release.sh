#!/usr/bin/env bash
# One-shot macOS release: Flutter build → bundle engines → ad-hoc codesign → DMG/ZIP.
# MUST run on macOS with Xcode + Flutter desktop + Homebrew.
#
#   bash scripts/macos/package_release.sh
#
# Outputs under dist/macos/:
#   DocumentStudio-<version>-macos.dmg
#   DocumentStudio-<version>-macos.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS. A Linux host cannot produce Document Studio.app." >&2
  exit 1
fi

echo "==> flutter build macos --release"
flutter build macos --release

APP="$(find "$ROOT/build/macos" -name 'document_studio.app' -type d 2>/dev/null | head -1 || true)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "document_studio.app not found after build." >&2
  exit 1
fi

echo "==> bundle engines into $APP"
bash "$ROOT/scripts/bundle_macos_engines.sh" "$APP"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP" || {
  echo "WARNING: codesign failed; continuing." >&2
}

echo "==> package DMG / ZIP"
bash "$ROOT/scripts/macos_dmg.sh" "$APP"

VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -1 | sed -E 's/version:[[:space:]]*([^+]+).*/\1/')"
echo
echo "Done."
echo "  dist/macos/DocumentStudio-${VERSION}-macos.dmg"
echo "  dist/macos/DocumentStudio-${VERSION}-macos.zip"
