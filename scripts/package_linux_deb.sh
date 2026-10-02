#!/usr/bin/env bash
# Build a .deb that contains qpdf, tesseract, and LibreOffice inside the app.
# Run on Linux after: flutter build linux --release
#
# Usage:
#   scripts/package_linux_deb.sh
#   scripts/package_linux_deb.sh /path/to/bundle
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=linux/copy_app_tree.sh
source "$ROOT/scripts/linux/copy_app_tree.sh"
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

echo "Filling engines (qpdf, tesseract, LibreOffice) before the .deb is built..."
bash "$ROOT/scripts/bundle_linux_engines.sh"
if [[ -d "$ROOT/.tools/linux-engines" ]]; then
  rm -rf "$BUNDLE/engines"
  mkdir -p "$BUNDLE/engines"
  cp -a "$ROOT/.tools/linux-engines"/. "$BUNDLE/engines"/
fi

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

copy_app_tree "$BUNDLE" "$PKG_ROOT/usr/lib/document-studio"
require_bundled_engines "$PKG_ROOT/usr/lib/document-studio"

# Wrapper prefers bundled engines over /usr/bin.
write_engine_launcher \
  "/usr/lib/document-studio" \
  "$PKG_ROOT/usr/bin/document_studio"
# Hyphenated name matches package id and user/docs; underscore kept for compatibility.
ln -sf document_studio "$PKG_ROOT/usr/bin/document-studio"

if [[ -f "$ROOT/linux/packaging/com.documentstudio.document_studio.desktop" ]]; then
  install -m644 "$ROOT/linux/packaging/com.documentstudio.document_studio.desktop" \
    "$PKG_ROOT/usr/share/applications/com.documentstudio.document_studio.desktop"
  # Absolute Exec so app menus find it even when PATH is minimal.
  sed -i 's|^Exec=.*|Exec=/usr/bin/document-studio %U|' \
    "$PKG_ROOT/usr/share/applications/com.documentstudio.document_studio.desktop"
  sed -i 's|^TryExec=.*|TryExec=/usr/bin/document-studio|' \
    "$PKG_ROOT/usr/share/applications/com.documentstudio.document_studio.desktop"
fi
METAINFO_SRC="$ROOT/linux/packaging/metainfo/com.documentstudio.document_studio.metainfo.xml"
if [[ -f "$METAINFO_SRC" ]]; then
  mkdir -p "$PKG_ROOT/usr/share/metainfo"
  install -m644 "$METAINFO_SRC" \
    "$PKG_ROOT/usr/share/metainfo/com.documentstudio.document_studio.metainfo.xml"
fi
ICON_TREE="$ROOT/linux/packaging/icons/hicolor"
if [[ ! -d "$ICON_TREE" ]]; then
  echo "Missing menu icons: $ICON_TREE (copy from AppDir or add PNGs under linux/packaging/icons/)." >&2
  exit 1
fi
cp -a "$ICON_TREE" "$PKG_ROOT/usr/share/icons/"

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

for maint in preinst postinst postrm; do
  src="$ROOT/linux/packaging/deb/$maint"
  if [[ ! -f "$src" ]]; then
    echo "Missing maintainer script: $src" >&2
    exit 1
  fi
  install -m755 "$src" "$PKG_ROOT/DEBIAN/$maint"
done

mkdir -p "$OUT_DIR"
DEB_OUT="$OUT_DIR/document-studio_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --build --root-owner-group "$PKG_ROOT" "$DEB_OUT"
echo "Wrote $DEB_OUT"
