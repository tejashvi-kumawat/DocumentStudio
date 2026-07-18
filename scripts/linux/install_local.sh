#!/usr/bin/env bash
# Install Document Studio for this user, with qpdf and tesseract already inside
# the app. Does not rebuild dist/linux and does not download LibreOffice.
#
#   bash scripts/linux/install_local.sh
#
# qpdf lands at:
#   ~/.local/lib/document-studio/engines/qpdf
# The launcher puts that directory on PATH before /usr/bin.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=copy_app_tree.sh
source "$ROOT/scripts/linux/copy_app_tree.sh"

pick_source() {
  local c
  for c in \
    "$ROOT/dist/linux/DocumentStudio.AppDir/usr/lib/document-studio" \
    "$ROOT/build/linux/x64/release/bundle" \
    "$ROOT/build/linux/arm64/release/bundle" \
    "$ROOT/build/linux/x64/debug/bundle" \
    "$ROOT/build/linux/arm64/debug/bundle" \
    /usr/lib/document-studio
  do
    if [[ -x "$c/document_studio" && -e "$c/engines" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

SRC="$(pick_source || true)"
if [[ -z "${SRC:-}" ]]; then
  echo "No Document Studio bundle with an engines/ directory was found." >&2
  echo "Build Linux first, or keep dist/linux/DocumentStudio.AppDir." >&2
  exit 1
fi

DEST="${HOME}/.local/lib/document-studio"
LAUNCHER="${HOME}/.local/bin/document-studio"
echo "Installing from $SRC"
echo "         into $DEST"
copy_app_tree "$SRC" "$DEST"
require_bundled_engines "$DEST"
write_engine_launcher "$DEST" "$LAUNCHER"

# Menu entry uses the absolute launcher so it does not depend on PATH.
APPS="${HOME}/.local/share/applications"
mkdir -p "$APPS"
DESKTOP_BODY="[Desktop Entry]
Name=Document Studio
Comment=Offline PDF workspace
Exec=${LAUNCHER} %U
Icon=document-studio
Terminal=false
Type=Application
Categories=Office;Graphics;
MimeType=application/pdf;
StartupWMClass=com.documentstudio.document_studio
"
printf '%s\n' "$DESKTOP_BODY" > "$APPS/com.documentstudio.document_studio.desktop"
printf '%s\n' "$DESKTOP_BODY" > "$APPS/document-studio.desktop"

if [[ -d "$SRC/../share/icons/hicolor" ]]; then
  mkdir -p "${HOME}/.local/share/icons"
  cp -a "$SRC/../share/icons/hicolor" "${HOME}/.local/share/icons/"
elif [[ -d "$ROOT/dist/linux/DocumentStudio.AppDir/usr/share/icons/hicolor" ]]; then
  mkdir -p "${HOME}/.local/share/icons"
  cp -a "$ROOT/dist/linux/DocumentStudio.AppDir/usr/share/icons/hicolor" \
    "${HOME}/.local/share/icons/"
fi

# Already-installed .deb: point its wrapper at the bundled engines too.
# Do not recopy that tree (it may contain a previously downloaded LibreOffice).
SYS_APP="/usr/lib/document-studio"
SYS_BIN="/usr/bin/document_studio"
if [[ -x "$SYS_APP/engines/qpdf" || -x "$SYS_APP/engines/bin/qpdf" ]]; then
  if [[ -w "$SYS_BIN" || ! -e "$SYS_BIN" ]]; then
    write_engine_launcher "$SYS_APP" "$SYS_BIN"
    echo "Updated $SYS_BIN to prefer $SYS_APP/engines"
  fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

QPDF_PATH="$(PATH="$DEST/engines:$DEST/engines/bin:/usr/bin:/bin" command -v qpdf)"
echo "qpdf: $QPDF_PATH"
"$DEST/engines/qpdf" --version | head -1
"$DEST/engines/tesseract" --version 2>&1 | head -1
if [[ "$QPDF_PATH" != "$DEST/engines/qpdf" && "$QPDF_PATH" != "$DEST/engines/bin/qpdf" ]]; then
  echo "PATH probe did not find the bundled qpdf before /usr/bin (got $QPDF_PATH)" >&2
  exit 1
fi
echo "Installed. Launch: $LAUNCHER"
echo "LibreOffice is not bundled. Office conversion uses system soffice when it is installed."
