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

if [[ ! -d "$ROOT/macos/Runner.xcodeproj" ]]; then
  echo "macos/ platform missing. Scaffolding with flutter create…" >&2
  flutter create --platforms=macos "$ROOT"
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

# Developer ID + notarization when configured, ad-hoc otherwise
# (see scripts/macos/sign_and_notarize.sh).
# shellcheck source=sign_and_notarize.sh
source "$ROOT/scripts/macos/sign_and_notarize.sh"
ds_sign_app "$APP"

VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -1 | sed -E 's/version:[[:space:]]*([^+]+).*/\1/')"

if ds_has_identity && ds_has_notary; then
  # Notarize the app itself first so the copy inside the DMG/ZIP is stapled
  # and opens offline without a warning.
  NOTARY_ZIP="$(mktemp -d)/DocumentStudio-notarize.zip"
  ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
  ds_notarize "$NOTARY_ZIP" "$APP"
  rm -f "$NOTARY_ZIP"
fi

echo "==> package DMG / ZIP"
bash "$ROOT/scripts/macos_dmg.sh" "$APP"

DMG="$ROOT/dist/macos/DocumentStudio-${VERSION}-macos.dmg"
if [[ -f "$DMG" ]]; then
  ds_sign_file "$DMG"
  ds_notarize "$DMG" "$DMG"
fi
echo
echo "Done."
echo "  dist/macos/DocumentStudio-${VERSION}-macos.dmg"
echo "  dist/macos/DocumentStudio-${VERSION}-macos.zip"
