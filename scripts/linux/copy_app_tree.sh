#!/usr/bin/env bash
# Copy a Flutter Linux bundle into an install prefix.
# engines/ symlinks are materialized. LibreOffice is left out: the app uses
# the system soffice when it is installed.
#
#   source scripts/linux/copy_app_tree.sh
#   copy_app_tree "$SRC" "$DEST"
#   require_bundled_engines "$DEST"
#   write_engine_launcher "$DEST" "$DEST/../bin/document-studio"

copy_app_tree() {
  local src="$1" dest="$2"
  if [[ ! -d "$src" ]]; then
    echo "copy_app_tree: source missing: $src" >&2
    return 1
  fi
  mkdir -p "$dest"
  local item base
  shopt -s nullglob
  for item in "$src"/*; do
    base="$(basename "$item")"
    if [[ "$base" == "engines" ]]; then
      continue
    fi
    rm -rf "$dest/$base"
    cp -a "$item" "$dest/$base"
  done
  shopt -u nullglob
  _copy_engines_without_libreoffice "$src/engines" "$dest/engines"
}

# Follow a symlink (debug builds point engines/ at .tools/linux-engines).
_copy_engines_without_libreoffice() {
  local src="$1" dest="$2"
  if [[ -L "$src" ]]; then
    src="$(readlink -f "$src")"
  fi
  if [[ ! -d "$src" ]]; then
    echo "engines directory missing: $1" >&2
    return 1
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  local item base
  shopt -s nullglob
  for item in "$src"/*; do
    base="$(basename "$item")"
    case "$base" in
      libreoffice|soffice) continue ;;
    esac
    cp -a "$item" "$dest/$base"
  done
  shopt -u nullglob
}

require_bundled_engines() {
  local app="$1"
  if [[ ! -x "$app/engines/qpdf" && ! -x "$app/engines/bin/qpdf" ]]; then
    echo "qpdf was not copied into $app/engines." >&2
    echo "Fill .tools/linux-engines (scripts/bundle_linux_engines.sh) and retry." >&2
    return 1
  fi
  if [[ ! -x "$app/engines/tesseract" && ! -x "$app/engines/bin/tesseract" ]]; then
    echo "tesseract was not copied into $app/engines." >&2
    echo "Desktop OCR needs that binary inside the app, not a separate install." >&2
    return 1
  fi
  if [[ -e "$app/engines/libreoffice" || -e "$app/engines/soffice" ]]; then
    echo "LibreOffice was copied into $app/engines; the install should use system soffice." >&2
    return 1
  fi
}

# Launcher puts the app engines directory ahead of /usr/bin.
write_engine_launcher() {
  local app="$1" launcher="$2"
  mkdir -p "$(dirname "$launcher")"
  local qapp
  qapp="$(printf '%q' "$app")"
  cat > "$launcher" <<EOF
#!/usr/bin/env bash
APP=$qapp
# Bundled engines before any system copy on PATH.
export PATH="\$APP/engines:\$APP/engines/bin\${PATH:+:\$PATH}"
if [[ -d "\$APP/engines/tessdata" ]]; then
  export TESSDATA_PREFIX="\$APP/engines/tessdata"
fi
exec "\$APP/document_studio" "\$@"
EOF
  chmod 755 "$launcher"
}
