#!/usr/bin/env bash
# Install desktop CLI engines used by Document Studio (Linux apt).
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "install_desktop_engines.sh: apt-get not found. On Debian/Ubuntu run:" >&2
  echo "  sudo apt-get update && sudo apt-get install -y qpdf tesseract-ocr" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-running with sudo…" >&2
  exec sudo bash "$0" "$@"
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y qpdf tesseract-ocr
echo "Installed: qpdf $(qpdf --version 2>&1 | head -1)"
echo "Installed: $(tesseract --version 2>&1 | head -1)"
