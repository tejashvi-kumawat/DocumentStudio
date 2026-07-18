#!/usr/bin/env bash
# Build a .deb that already contains engines/qpdf and engines/tesseract.
# Does not delete other artifacts in dist/linux (AppImage, AppDir).
#
#   bash scripts/linux/package_deb.sh
#   bash scripts/linux/package_deb.sh /path/to/bundle
#
# To install for the current user without root, use:
#   bash scripts/linux/install_local.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec bash "$ROOT/scripts/package_linux_deb.sh" "$@"
