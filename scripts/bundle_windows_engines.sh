#!/usr/bin/env bash
# Copy DSC signing tools into a Flutter Windows build output engines/ folder
# when the host PATH (or Chocolatey) can supply them.
#
# Usage (Git Bash / MSYS / WSL calling Windows paths):
#   scripts/bundle_windows_engines.sh <dir_containing_document_studio.exe>
#
# Native PowerShell alternative: scripts/bundle_windows_engines.ps1
set -euo pipefail

BUNDLE_DIR="${1:-}"
if [[ -z "$BUNDLE_DIR" ]]; then
  echo "usage: $0 <flutter_windows_output_dir>" >&2
  exit 2
fi
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"
ENGINES="$BUNDLE_DIR/engines"
mkdir -p "$ENGINES/bin"

copy_exe() {
  local name="$1"
  local src
  src="$(command -v "$name" 2>/dev/null || command -v "$name.exe" 2>/dev/null || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "WARNING: $name not on PATH for Windows bundle (choco install openssl / poppler / nss-tools if available)." >&2
    return 1
  fi
  echo "Bundling Windows $name from $src"
  cp -a "$src" "$ENGINES/bin/" 2>/dev/null || cp -a "$src" "$ENGINES/bin/${name}.exe"
  # Thin wrapper for resolver engines/<name>
  if [[ "$src" == *.exe ]]; then
    cat > "$ENGINES/$name.cmd" <<WRAP
@echo off
"%~dp0bin\\$(basename "$src")" %*
WRAP
    # Also copy as engines/bin name without extension lookup
    cp -a "$src" "$ENGINES/bin/${name}.exe" 2>/dev/null || true
  else
    cp -a "$src" "$ENGINES/$name" 2>/dev/null || true
  fi
}

for name in pdfsig certutil pk12util openssl ffmpeg soffice libreoffice; do
  copy_exe "$name" || true
done

echo "Windows engines directory: $ENGINES"
ls -la "$ENGINES" "$ENGINES/bin" 2>/dev/null || true
