# Build an AppImage from the Flutter Linux Release bundle.
# Prefers appimagetool when available; otherwise writes an AppDir tarball.
#
# Usage:
#   scripts/linux/package_appimage.sh
#   scripts/linux/package_appimage.sh /path/to/bundle
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"