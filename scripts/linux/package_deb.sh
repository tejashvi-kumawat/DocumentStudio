# Build a simple .deb from the Flutter Linux Release bundle.
# Run on Linux after: flutter build linux --release
#
# Usage:
#   scripts/linux/package_deb.sh
#   scripts/linux/package_deb.sh /path/to/bundle
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"