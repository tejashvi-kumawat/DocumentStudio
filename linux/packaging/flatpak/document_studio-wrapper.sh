#!/bin/bash
# Launch the Flutter Linux binary with Flutter libs on LD_LIBRARY_PATH.
# Do NOT prepend engines/lib here — those host-bundled libs shadow the Flatpak
# runtime (glib/cairo/etc.) and segfault. Engine wrappers under engines/ set
# their own LD_LIBRARY_PATH when invoked.
set -euo pipefail
APP="/app/lib/document-studio"
export LD_LIBRARY_PATH="${APP}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="${APP}/engines:${APP}/engines/bin${PATH:+:$PATH}"
if [[ -d "${APP}/engines/tessdata" ]]; then
  export TESSDATA_PREFIX="${APP}/engines/tessdata"
fi
exec "${APP}/document_studio" "$@"
