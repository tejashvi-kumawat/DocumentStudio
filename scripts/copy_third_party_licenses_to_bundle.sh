#!/usr/bin/env bash
# Copy THIRD_PARTY_LICENSES into a desktop engines/ directory and write bundled-versions.json.
# Called from bundle_linux_engines.sh, bundle_macos_engines.sh, etc.
#
# Usage: bash scripts/copy_third_party_licenses_to_bundle.sh /path/to/engines

set -euo pipefail
ENGINES="${1:?engines directory}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/THIRD_PARTY_LICENSES"
DEST="$ENGINES/THIRD_PARTY_LICENSES"

if [[ ! -d "$SRC" ]]; then
  echo "WARNING: $SRC missing; skipping legal copy." >&2
  exit 0
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC/." "$DEST/"

# Remove README duplicate path confusion — keep all license texts.
GENERATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "$DEST/bundled-versions.json" <<EOF
{
  "generatedUtc": "$GENERATED",
  "platform": "$(uname -s 2>/dev/null || echo unknown)",
  "qpdf": "${DS_QPDF_VERSION:-12.2.0}",
  "tesseract_linux_debs": "5.3.4-1build5 (Ubuntu pool when used)",
  "poppler_linux": "poppler-utils 24.02.0-1ubuntu9 (when used)",
  "libreoffice": "${DS_LIBREOFFICE_VERSION:-26.2.6}",
  "ffmpeg": "distro or DS_FFMPEG_URL build — verify license via ffmpeg -version",
  "nss": "${DS_NSS_PKG:-system libnss3-tools}",
  "notes": "See BUNDLED_COMPONENTS.md and bundled-versions.json in Windows build for Windows-specific pins."
}
EOF

echo "Copied third-party licenses to $DEST"
