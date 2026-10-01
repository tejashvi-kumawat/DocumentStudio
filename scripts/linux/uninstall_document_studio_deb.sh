#!/usr/bin/env bash
# Purge the document-studio .deb and known system paths, then print local cleanup.
#
#   sudo bash scripts/linux/uninstall_document_studio_deb.sh
#   bash scripts/linux/uninstall_local.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-run as root:" >&2
  echo "  sudo bash $ROOT/scripts/linux/uninstall_document_studio_deb.sh" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

if dpkg-query -W -f='${Status}' document-studio 2>/dev/null | grep -q 'install ok installed'; then
  apt-get purge -y document-studio || dpkg --purge document-studio
else
  echo "Package document-studio is not installed (dpkg); removing leftover paths only."
fi

rm -rf /usr/lib/document-studio
rm -f /usr/bin/document_studio
rm -f /usr/share/applications/com.documentstudio.document_studio.desktop

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi

echo "System paths cleared."
echo "Also run (no sudo): bash $ROOT/scripts/linux/uninstall_local.sh"
