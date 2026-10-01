#!/usr/bin/env bash
# Create a portable Windows zip from a Release runner folder.
# Intended to run on Windows (Git Bash / CI windows-latest) after:
#   flutter build windows --release
#   powershell -File scripts/bundle_windows_engines.ps1   # if available
#
# Usage:
#   scripts/package_windows_portable.sh [release_dir] [out_zip]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="${1:-$ROOT/build/windows/x64/runner/Release}"
VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -1 | sed -E 's/version:[[:space:]]*([^+]+).*/\1/')"
OUT_ZIP="${2:-$ROOT/dist/windows/DocumentStudio-${VERSION}-portable-windows.zip}"

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Release directory not found: $RELEASE_DIR" >&2
  echo "Run: flutter build windows --release" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_ZIP")"
rm -f "$OUT_ZIP"

# Prefer PowerShell Compress-Archive on Windows; fall back to zip.
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command \
    "Compress-Archive -Path '$(cygpath -w "$RELEASE_DIR" 2>/dev/null || echo "$RELEASE_DIR")\\*' -DestinationPath '$(cygpath -w "$OUT_ZIP" 2>/dev/null || echo "$OUT_ZIP")' -Force"
elif command -v zip >/dev/null 2>&1; then
  (cd "$RELEASE_DIR" && zip -r -9 "$OUT_ZIP" .)
else
  echo "Need powershell.exe or zip to create the archive" >&2
  exit 1
fi

echo "Wrote $OUT_ZIP"
