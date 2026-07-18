#!/usr/bin/env bash
# Build an AppImage (or AppDir tarball) from the Linux bundle.
# Does not delete unrelated files already in dist/linux.
#
#   bash scripts/linux/package_appimage.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec bash "$ROOT/scripts/package_linux_appimage.sh" "$@"
