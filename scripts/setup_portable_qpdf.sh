#!/usr/bin/env bash
# Bootstrap a portable qpdf under .tools/qpdf (gitignored) for corpus generators.
# Usage: bash scripts/setup_portable_qpdf.sh
# Then: export PATH="$PWD/.tools/qpdf/bin:$PATH"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools/qpdf"
BIN="$TOOLS/bin/qpdf"

if [[ -x "$BIN" ]]; then
  echo "Portable qpdf already present: $BIN"
  "$BIN" --version
  exit 0
fi

if command -v qpdf >/dev/null 2>&1; then
  echo "System qpdf on PATH ($(command -v qpdf)); no portable install needed."
  qpdf --version
  exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ZIP_ARCH="x86_64" ;;
  aarch64|arm64) ZIP_ARCH="aarch64" ;;
  *)
    echo "Unsupported CPU $ARCH; install qpdf via your package manager." >&2
    exit 1
    ;;
esac

OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  echo "Portable bootstrap is Linux-only; install qpdf for $OS manually." >&2
  exit 1
fi

QPDF_VERSION="${QPDF_VERSION:-12.2.0}"
ZIP="qpdf-${QPDF_VERSION}-bin-linux-${ZIP_ARCH}.zip"
URL="https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/${ZIP}"
CACHE="$ROOT/.tools/cache"
mkdir -p "$CACHE"
ZIP_PATH="$CACHE/$ZIP"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Downloading $URL ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$ZIP_PATH" "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$ZIP_PATH" "$URL"
  else
    echo "Need curl or wget to download qpdf." >&2
    exit 1
  fi
fi

rm -rf "$TOOLS"
mkdir -p "$TOOLS"
unzip -q "$ZIP_PATH" -d "$TOOLS"
# Release zips unpack to qpdf-VERSION-bin-linux-ARCH/
EXTRACTED="$(find "$TOOLS" -maxdepth 1 -type d -name 'qpdf-*-bin-linux-*' | head -1)"
if [[ -z "$EXTRACTED" || ! -x "$EXTRACTED/bin/qpdf" ]]; then
  echo "Unexpected qpdf zip layout under $TOOLS" >&2
  exit 1
fi
mv "$EXTRACTED"/* "$TOOLS/"
rmdir "$EXTRACTED" 2>/dev/null || true

echo "Installed portable qpdf: $BIN"
"$BIN" --version
echo "Add to PATH: export PATH=\"$TOOLS/bin:\$PATH\""
