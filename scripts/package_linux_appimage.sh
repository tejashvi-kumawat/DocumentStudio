#!/usr/bin/env bash
# Build an AppImage from the Flutter Linux Release bundle.
# Prefers linuxdeploy when available; otherwise produces a minimal Type-2
# AppDir + appimagetool if present.
#
# Usage:
#   scripts/package_linux_appimage.sh
#   scripts/package_linux_appimage.sh /path/to/bundle
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

VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -1 | sed -E 's/version:[[:space:]]*([^+]+).*/\1/')"
OUT_DIR="$ROOT/dist/linux"
APPDIR="$OUT_DIR/DocumentStudio.AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor"

copy_app_tree "$BUNDLE" "$APPDIR/usr/lib/document-studio"
require_bundled_engines "$APPDIR/usr/lib/document-studio"
ln -sfr "$APPDIR/usr/lib/document-studio/document_studio" "$APPDIR/usr/bin/document_studio"

install -m644 "$ROOT/linux/packaging/com.documentstudio.document_studio.desktop" \
  "$APPDIR/usr/share/applications/com.documentstudio.document_studio.desktop"
sed -i 's|^Exec=.*|Exec=document_studio %U|' \
  "$APPDIR/usr/share/applications/com.documentstudio.document_studio.desktop"
cp -a "$ROOT/linux/packaging/icons/hicolor/." "$APPDIR/usr/share/icons/hicolor/"

# AppImage root desktop + icon symlinks
cp "$APPDIR/usr/share/applications/com.documentstudio.document_studio.desktop" \
  "$APPDIR/document-studio.desktop"
if [[ -f "$ROOT/linux/packaging/icons/hicolor/256x256/apps/document-studio.png" ]]; then
  cp "$ROOT/linux/packaging/icons/hicolor/256x256/apps/document-studio.png" "$APPDIR/document-studio.png"
  ln -sf document-studio.png "$APPDIR/.DirIcon"
fi

cat > "$APPDIR/AppRun" <<'RUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib/document-studio/lib:${LD_LIBRARY_PATH:-}"
# Prefer bundled engines over host PATH.
export PATH="$HERE/usr/lib/document-studio/engines/bin:$HERE/usr/lib/document-studio/engines:$PATH"
exec "$HERE/usr/lib/document-studio/document_studio" "$@"
RUN
chmod 755 "$APPDIR/AppRun"

mkdir -p "$OUT_DIR"
OUT_AI="$OUT_DIR/DocumentStudio-${VERSION}-$(uname -m).AppImage"

if command -v appimagetool >/dev/null 2>&1; then
  ARCH="$(uname -m)" appimagetool "$APPDIR" "$OUT_AI"
  echo "Wrote $OUT_AI"
elif [[ -x "$ROOT/.tools/appimagetool" ]]; then
  ARCH="$(uname -m)" "$ROOT/.tools/appimagetool" "$APPDIR" "$OUT_AI"
  echo "Wrote $OUT_AI"
else
  # Fallback: zip the AppDir so CI still produces an artifact; convert later.
  FALLBACK="$OUT_DIR/DocumentStudio-${VERSION}-$(uname -m)-AppDir.tar.gz"
  tar -C "$OUT_DIR" -czf "$FALLBACK" "$(basename "$APPDIR")"
  echo "appimagetool not found — wrote AppDir archive: $FALLBACK" >&2
  echo "Install appimagetool (https://github.com/AppImage/appimagetool) and re-run." >&2
  echo "AppDir ready at: $APPDIR"
fi
