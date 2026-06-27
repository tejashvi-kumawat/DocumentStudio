#!/usr/bin/env bash
# Build a simple .deb from the Flutter Linux Release bundle.
# Run on Linux after: flutter build linux --release
#
# Usage:
#   scripts/package_linux_deb.sh
#   scripts/package_linux_deb.sh /path/to/bundle
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
  for cand in \
    "$ROOT/build/linux/x64/release/bundle" \
    "$ROOT/build/linux/arm64/release/bundle"; do
    if [[ -d "$cand" ]]; then BUNDLE="$cand"; break; fi
  done
fi
if [[ -z "${BUNDLE:-}" || ! -d "$BUNDLE" ]]; then
  echo "Flutter Linux bundle not found. Run: flutter build linux --release" >&2
  exit 1
fi
BUNDLE="$(cd "$BUNDLE" && pwd)"

VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -1 | sed -E 's/version:[[:space:]]*([^+]+).*/\1/')"
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) DEB_ARCH=amd64 ;;
  aarch64|arm64) DEB_ARCH=arm64 ;;
  *) DEB_ARCH="$ARCH_RAW" ;;
esac

OUT_DIR="$ROOT/dist/linux"
STAGE="$OUT_DIR/deb-staging"
PKG_ROOT="$STAGE/document-studio_${VERSION}_${DEB_ARCH}"
rm -rf "$STAGE"
mkdir -p "$PKG_ROOT/DEBIAN" \
  "$PKG_ROOT/usr/lib/document-studio" \
  "$PKG_ROOT/usr/bin" \
  "$PKG_ROOT/usr/share/applications" \
  "$PKG_ROOT/usr/share/icons"

cp -a "$BUNDLE"/. "$PKG_ROOT/usr/lib/document-studio/"

# Wrapper so PATH finds the app and RPATH-relative libs stay under /usr/lib/...
cat > "$PKG_ROOT/usr/bin/document_studio" <<'WRAP'
#!/usr/bin/env bash
exec /usr/lib/document-studio/document_studio "$@"
WRAP
chmod 755 "$PKG_ROOT/usr/bin/document_studio"

if [[ -f "$ROOT/linux/packaging/com.documentstudio.document_studio.desktop" ]]; then
  install -m644 "$ROOT/linux/packaging/com.documentstudio.document_studio.desktop" \
    "$PKG_ROOT/usr/share/applications/com.documentstudio.document_studio.desktop"
  # Point Icon at hicolor name already used by packaging.
  sed -i 's|^Exec=.*|Exec=document_studio|' \
    "$PKG_ROOT/usr/share/applications/com.documentstudio.document_studio.desktop"
fi
if [[ -d "$ROOT/linux/packaging/icons/hicolor" ]]; then
  cp -a "$ROOT/linux/packaging/icons/hicolor" "$PKG_ROOT/usr/share/icons/"
fi

INSTALLED_SIZE="$(du -sk "$PKG_ROOT/usr" | cut -f1)"
cat > "$PKG_ROOT/DEBIAN/control" <<CTRL
Package: document-studio
Version: ${VERSION}
Section: graphics
Priority: optional
Architecture: ${DEB_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Document Studio <noreply@documentstudio.local>
Depends: libgtk-3-0, libblkid1, liblzma5
Homepage: https://github.com/documentstudio/document_studio
Description: Offline, privacy-first PDF and document workspace
 Document Studio processes PDFs and images on-device: merge, split, compress,
 OCR, sign, and more — no account required.
CTRL

mkdir -p "$OUT_DIR"
DEB_OUT="$OUT_DIR/document-studio_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --build --root-owner-group "$PKG_ROOT" "$DEB_OUT"
echo "Wrote $DEB_OUT"
