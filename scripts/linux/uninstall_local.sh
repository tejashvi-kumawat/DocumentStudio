#!/usr/bin/env bash
# Remove the per-user install created by scripts/linux/install_local.sh.
# Does not touch the system .deb (use uninstall_document_studio_deb.sh for that).
set -euo pipefail

APPS="${HOME}/.local/share/applications"
rm -f \
  "$APPS/com.documentstudio.document_studio.desktop" \
  "$APPS/document-studio.desktop"
rm -rf "${HOME}/.local/lib/document-studio"
rm -f "${HOME}/.local/bin/document-studio"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

echo "Removed ~/.local Document Studio install (if any)."
