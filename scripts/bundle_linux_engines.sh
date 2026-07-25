#!/usr/bin/env bash
# Copy qpdf (+ libs), tesseract (+ tessdata), and DSC signing tools
# (pdfsig / certutil / pk12util / openssl) into a Flutter Linux bundle's
# engines/ directory so the running app does not depend on PATH.
#
# Usage:
#   scripts/bundle_linux_engines.sh
#   scripts/bundle_linux_engines.sh <bundle_dir>
#   # no args fills .tools/linux-engines, which the .deb and CMake copy in
#   # bundle_dir is typically build/linux/*/bundle
#
# Sources (first hit wins for qpdf):
#   1. PATH qpdf
#   2. .tools/qpdf (from scripts/setup_portable_qpdf.sh)
#   3. Download portable qpdf via setup_portable_qpdf.sh when network allows
#
# DSC tools: PATH copy + ldd closure into engines/lib, or apt, or .deb extract.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="${1:-}"
if [[ -z "$BUNDLE_DIR" ]]; then
  ENGINES="$ROOT/.tools/linux-engines"
else
  BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"
  ENGINES="$BUNDLE_DIR/engines"
fi
mkdir -p "$ENGINES/bin" "$ENGINES/lib" "$ENGINES/tessdata"

copy_file() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  chmod +x "$dest" 2>/dev/null || true
}

bundle_qpdf_from_portable() {
  local tools="$ROOT/.tools/qpdf"
  local bin="$tools/bin/qpdf"
  if [[ ! -x "$bin" ]]; then
    return 1
  fi
  echo "Bundling portable qpdf from $tools"
  copy_file "$bin" "$ENGINES/bin/qpdf"
  if [[ -d "$tools/lib" ]]; then
    cp -a "$tools/lib/." "$ENGINES/lib/"
  fi
  # Wrapper at engines/qpdf so bare-name lookup also works with correct libs.
  cat > "$ENGINES/qpdf" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$ROOT/lib:${LD_LIBRARY_PATH:-}"
exec "$ROOT/bin/qpdf" "$@"
WRAP
  chmod +x "$ENGINES/qpdf"
  return 0
}

bundle_qpdf_from_path() {
  local src
  src="$(command -v qpdf 2>/dev/null || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    return 1
  fi
  echo "Bundling system qpdf from $src"
  copy_file "$src" "$ENGINES/bin/qpdf"
  if command -v ldd >/dev/null 2>&1; then
    while read -r line; do
      local libpath
      libpath="$(echo "$line" | awk '/=>/ {print $3}')"
      if [[ -n "$libpath" && -f "$libpath" && "$libpath" == *libqpdf* ]]; then
        cp -a "$libpath" "$ENGINES/lib/" || true
      fi
    done < <(ldd "$src" 2>/dev/null || true)
  fi
  cat > "$ENGINES/qpdf" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$ROOT/lib:${LD_LIBRARY_PATH:-}"
exec "$ROOT/bin/qpdf" "$@"
WRAP
  chmod +x "$ENGINES/qpdf"
  return 0
}

if ! bundle_qpdf_from_path; then
  if ! bundle_qpdf_from_portable; then
    echo "Portable qpdf missing; running setup_portable_qpdf.sh ..."
    if bash "$ROOT/scripts/setup_portable_qpdf.sh"; then
      bundle_qpdf_from_portable || true
    else
      echo "WARNING: could not obtain qpdf for the bundle." >&2
    fi
  fi
fi

bundle_tesseract_from_debs() {
  # Portable fallback when apt install needs sudo / is unavailable:
  # download Ubuntu packages and extract tesseract + eng.traineddata + libs.
  local work="$ROOT/.tools/tesseract_extract"
  mkdir -p "$work"
  echo "Downloading portable tesseract packages into $work …"
  (
    cd "$work"
    # Prefer jammy/noble amd64 packages from Ubuntu archive.
    local base="http://archive.ubuntu.com/ubuntu/pool/universe/t/tesseract"
    local lept="http://mirrors.kernel.org/ubuntu/pool/universe/l/leptonlib"
    local pkgs=(
      "tesseract-ocr_5.3.4-1build5_amd64.deb"
      "libtesseract5_5.3.4-1build5_amd64.deb"
      "tesseract-ocr-eng_1%3a4.1.0-2_all.deb"
    )
    # Try apt-get download first (no install / may not need sudo).
    if command -v apt-get >/dev/null 2>&1; then
      apt-get download tesseract-ocr libtesseract5 liblept5 tesseract-ocr-eng >/dev/null 2>&1 || true
    fi
    if ! ls ./*.deb >/dev/null 2>&1; then
      for pkg in "${pkgs[@]}"; do
        curl -fsSL -O "$base/$pkg" 2>/dev/null || wget -q "$base/$pkg" 2>/dev/null || true
      done
    fi
    # Always try leptonica (often missing from PATH-less hosts).
    if ! ls ./liblept5*.deb >/dev/null 2>&1; then
      curl -fsSL -O "$lept/liblept5_1.82.0-3build4_amd64.deb" 2>/dev/null \
        || wget -q "$lept/liblept5_1.82.0-3build4_amd64.deb" 2>/dev/null || true
    fi
    if ! ls ./tesseract-ocr_*.deb >/dev/null 2>&1 && ! ls ./libtesseract5_*.deb >/dev/null 2>&1; then
      echo "WARNING: could not download tesseract debs." >&2
      return 1
    fi
    mkdir -p extracted
    for deb in ./*.deb; do
      dpkg-deb -x "$deb" extracted/ 2>/dev/null || true
    done
  )
  local bin=""
  bin="$(find "$work/extracted" -type f -name tesseract 2>/dev/null | head -1 || true)"
  if [[ -z "$bin" || ! -x "$bin" ]]; then
    echo "WARNING: extracted tesseract binary not found." >&2
    return 1
  fi
  echo "Bundling portable tesseract from $bin"
  mkdir -p "$ENGINES/bin" "$ENGINES/lib" "$ENGINES/tessdata"
  copy_file "$bin" "$ENGINES/bin/tesseract"
  # Shared libs (real .so files + soname symlinks)
  find "$work/extracted" -type f \( -name 'libtesseract.so*' -o -name 'liblept.so*' \) \
    -exec cp -a {} "$ENGINES/lib/" \; 2>/dev/null || true
  find "$work/extracted" -type l \( -name 'libtesseract.so*' -o -name 'liblept.so*' \) \
    -exec cp -a {} "$ENGINES/lib/" \; 2>/dev/null || true
  # Ensure soname links exist even if dpkg stored versioned files only.
  (
    cd "$ENGINES/lib"
    if [[ -f libtesseract.so.5.0.3 && ! -e libtesseract.so.5 ]]; then
      ln -sfn libtesseract.so.5.0.3 libtesseract.so.5
    fi
    if [[ -f liblept.so.5.0.4 && ! -e liblept.so.5 ]]; then
      ln -sfn liblept.so.5.0.4 liblept.so.5
    fi
  )
  if command -v ldd >/dev/null 2>&1; then
    while read -r line; do
      local libpath
      libpath="$(echo "$line" | awk '/=>/ {print $3}')"
      if [[ -n "$libpath" && -f "$libpath" ]]; then
        case "$libpath" in
          *tesseract*|*lept*|*gif*|*tiff*|*webp*|*openjp2*|*png*|*jpeg*)
            cp -a "$libpath" "$ENGINES/lib/" || true
            ;;
        esac
      fi
    done < <(LD_LIBRARY_PATH="$ENGINES/lib:${LD_LIBRARY_PATH:-}" ldd "$ENGINES/bin/tesseract" 2>/dev/null || true)
  fi
  local engdata
  engdata="$(find "$work/extracted" -name eng.traineddata 2>/dev/null | head -1 || true)"
  if [[ -n "$engdata" ]]; then
    cp -a "$engdata" "$ENGINES/tessdata/" || true
  fi
  # Also try GitHub tessdata_fast if still missing.
  if [[ ! -f "$ENGINES/tessdata/eng.traineddata" ]]; then
    echo "Fetching eng.traineddata from tessdata_fast…"
    curl -fsSL -o "$ENGINES/tessdata/eng.traineddata" \
      "https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata" \
      || wget -q -O "$ENGINES/tessdata/eng.traineddata" \
      "https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata" || true
  fi
  cat > "$ENGINES/tesseract" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$ROOT/lib:${LD_LIBRARY_PATH:-}"
# Bundled tesseract expects TESSDATA_PREFIX to be the tessdata directory itself.
if [[ -d "$ROOT/tessdata" ]]; then
  export TESSDATA_PREFIX="$ROOT/tessdata"
fi
exec "$ROOT/bin/tesseract" "$@"
WRAP
  chmod +x "$ENGINES/tesseract"
  if ! LD_LIBRARY_PATH="$ENGINES/lib" "$ENGINES/tesseract" --version >/dev/null 2>&1; then
    echo "WARNING: bundled tesseract failed --version smoke test." >&2
    return 1
  fi
  echo "Bundled tesseract OK: $("$ENGINES/tesseract" --version 2>&1 | head -1)"
  return 0
}

bundle_tesseract() {
  local src
  src="$(command -v tesseract 2>/dev/null || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "tesseract not on PATH — attempting apt install (non-interactive)…"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y tesseract-ocr tesseract-ocr-eng >/dev/null 2>&1 || true
    fi
    src="$(command -v tesseract 2>/dev/null || true)"
  fi
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "tesseract not on PATH / apt failed — trying portable deb extract…"
    if bundle_tesseract_from_debs; then
      return 0
    fi
    echo "tesseract not available — OCR search will report engine missing."
    return 0
  fi
  echo "Bundling tesseract from $src"
  mkdir -p "$ENGINES/bin" "$ENGINES/lib" "$ENGINES/tessdata"
  copy_file "$src" "$ENGINES/bin/tesseract"
  # Language data: prefer TESSDATA_PREFIX, then common distro paths
  local tessdata=""
  if [[ -n "${TESSDATA_PREFIX:-}" && -d "${TESSDATA_PREFIX}" ]]; then
    # Accept either .../tessdata or the parent that contains tessdata/
    if [[ -f "${TESSDATA_PREFIX}/eng.traineddata" ]]; then
      tessdata="$TESSDATA_PREFIX"
    elif [[ -f "${TESSDATA_PREFIX}/tessdata/eng.traineddata" ]]; then
      tessdata="${TESSDATA_PREFIX}/tessdata"
    else
      tessdata="$TESSDATA_PREFIX"
    fi
  elif [[ -d /usr/share/tesseract-ocr/5/tessdata ]]; then
    tessdata=/usr/share/tesseract-ocr/5/tessdata
  elif [[ -d /usr/share/tesseract-ocr/4.00/tessdata ]]; then
    tessdata=/usr/share/tesseract-ocr/4.00/tessdata
  elif [[ -d /usr/share/tessdata ]]; then
    tessdata=/usr/share/tessdata
  fi
  if [[ -n "$tessdata" && -f "$tessdata/eng.traineddata" ]]; then
    echo "Bundling tessdata eng from $tessdata"
    cp -a "$tessdata/eng.traineddata" "$ENGINES/tessdata/" || true
    for f in osd.traineddata eng.user-words eng.user-patterns; do
      [[ -f "$tessdata/$f" ]] && cp -a "$tessdata/$f" "$ENGINES/tessdata/" || true
    done
  else
    echo "WARNING: eng.traineddata not found; attempting apt install…" >&2
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y tesseract-ocr-eng >/dev/null 2>&1 || true
      if [[ -f /usr/share/tesseract-ocr/5/tessdata/eng.traineddata ]]; then
        cp -a /usr/share/tesseract-ocr/5/tessdata/eng.traineddata "$ENGINES/tessdata/" || true
      fi
    fi
    if [[ ! -f "$ENGINES/tessdata/eng.traineddata" ]]; then
      echo "Fetching eng.traineddata from tessdata_fast…"
      curl -fsSL -o "$ENGINES/tessdata/eng.traineddata" \
        "https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata" \
        || wget -q -O "$ENGINES/tessdata/eng.traineddata" \
        "https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata" || true
    fi
    if [[ ! -f "$ENGINES/tessdata/eng.traineddata" ]]; then
      echo "WARNING: eng.traineddata still missing; set TESSDATA_PREFIX at runtime if OCR fails." >&2
    fi
  fi
  # Bundle common shared libs beside the binary (same approach as qpdf).
  if command -v ldd >/dev/null 2>&1; then
    while read -r line; do
      local libpath
      libpath="$(echo "$line" | awk '/=>/ {print $3}')"
      if [[ -n "$libpath" && -f "$libpath" && ( "$libpath" == *tesseract* || "$libpath" == *lept* ) ]]; then
        cp -a "$libpath" "$ENGINES/lib/" || true
      fi
    done < <(ldd "$ENGINES/bin/tesseract" 2>/dev/null || true)
  fi
  cat > "$ENGINES/tesseract" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$ROOT/lib:${LD_LIBRARY_PATH:-}"
# Bundled tesseract expects TESSDATA_PREFIX to be the tessdata directory itself.
if [[ -d "$ROOT/tessdata" ]]; then
  export TESSDATA_PREFIX="$ROOT/tessdata"
fi
exec "$ROOT/bin/tesseract" "$@"
WRAP
  chmod +x "$ENGINES/tesseract"
}

write_soffice_wrapper() {
  cat > "$ENGINES/soffice" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROG=""
while IFS= read -r d; do
  if [[ -f "$d/soffice.bin" ]]; then
    PROG="$d"
    break
  fi
done < <(find "$ROOT/libreoffice" -path '*/program' -type d 2>/dev/null)
# Fallback: system-style engines/libreoffice/lib/libreoffice/program
if [[ -z "$PROG" ]]; then
  while IFS= read -r d; do
    if [[ -f "$d/soffice.bin" ]]; then
      PROG="$d"
      break
    fi
  done < <(find "$ROOT" -path '*/program' -type d 2>/dev/null)
fi
if [[ -z "$PROG" ]]; then
  echo "bundled LibreOffice program/ not found under $ROOT/libreoffice" >&2
  exit 127
fi
export PATH="$PROG:${PATH:-}"
export LD_LIBRARY_PATH="$PROG:$ROOT/lib:${LD_LIBRARY_PATH:-}"
# Required so UNO loads program/services/*.rdb (UniversalContentBroker, etc.).
if [[ -f "$PROG/fundamentalrc" ]]; then
  export URE_BOOTSTRAP="vnd.sun.star.pathname:$PROG/fundamentalrc"
fi
cd "$PROG" || exit 127
if [[ -x ./soffice ]]; then
  exec ./soffice "$@"
fi
exec ./soffice.bin "$@"
WRAP
  chmod +x "$ENGINES/soffice"
}

bundle_soffice_from_official() {
  # Self-contained Document Foundation "deb" tarball → opt/libreofficeXX under engines/.
  local work="$ROOT/.tools/libreoffice_official"
  mkdir -p "$work"
  local tarball=""
  # Reuse any previously downloaded official tarball.
  tarball="$(ls -1 "$work"/LibreOffice_*_Linux_x86-64_deb.tar.gz 2>/dev/null | head -1 || true)"
  local url_base="https://download.documentfoundation.org/libreoffice/stable"
  local ver=""
  if [[ -z "$tarball" ]] || ! gzip -t "$tarball" >/dev/null 2>&1; then
    echo "Downloading official LibreOffice portable suite into $work …"
    ver="$(curl -fsSL "$url_base/" 2>/dev/null | grep -oE 'href="[0-9]+\.[0-9]+\.[0-9]+/' | head -1 | tr -d 'href="/' || true)"
    if [[ -z "$ver" ]]; then
      ver="26.2.6"
    fi
    tarball="$work/LibreOffice_${ver}_Linux_x86-64_deb.tar.gz"
    local url="$url_base/$ver/deb/x86_64/LibreOffice_${ver}_Linux_x86-64_deb.tar.gz"
    if ! curl -fL --retry 3 -o "$tarball" "$url" 2>/dev/null; then
      echo "WARNING: could not download official LibreOffice tarball from $url" >&2
      return 1
    fi
  fi
  if ! gzip -t "$tarball" >/dev/null 2>&1; then
    echo "WARNING: LibreOffice tarball corrupt." >&2
    rm -f "$tarball"
    return 1
  fi
  rm -rf "$work/extracted" "$work/unpacked"
  mkdir -p "$work/extracted" "$work/unpacked"
  tar -xzf "$tarball" -C "$work/unpacked"
  local debdir=""
  debdir="$(find "$work/unpacked" -type d -name DEBS 2>/dev/null | head -1 || true)"
  if [[ -z "$debdir" ]]; then
    echo "WARNING: official LibreOffice DEBS/ not found after extract." >&2
    return 1
  fi
  local deb
  for deb in "$debdir"/*.deb; do
    local base
    base="$(basename "$deb")"
    case "$base" in
      *helppack*|*dict-*|*debian-menus*|*test*) continue ;;
    esac
    dpkg-deb -x "$deb" "$work/extracted/" 2>/dev/null || true
  done
  if [[ ! -d "$work/extracted/opt" ]]; then
    echo "WARNING: official LibreOffice opt/ tree missing." >&2
    return 1
  fi
  local lo_home="$ENGINES/libreoffice"
  rm -rf "$lo_home"
  mkdir -p "$lo_home"
  cp -a "$work/extracted/opt/." "$lo_home/"
  write_soffice_wrapper
  local ver_out=""
  ver_out="$("$ENGINES/soffice" --version 2>&1 || true)"
  if [[ -z "$ver_out" ]] || echo "$ver_out" | grep -qi 'DeploymentException\|not found\|error'; then
    echo "WARNING: bundled official soffice failed --version smoke test: $ver_out" >&2
    return 1
  fi
  echo "Bundled soffice OK: $(echo "$ver_out" | head -1)"
  return 0
}

bundle_soffice_from_debs() {
  # Ubuntu package extract fallback (needs URE_BOOTSTRAP + careful lib copy).
  local work="$ROOT/.tools/libreoffice_extract"
  mkdir -p "$work"
  echo "Downloading Ubuntu LibreOffice packages into $work …"
  (
    cd "$work"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get download libreoffice-core-nogui libreoffice-common \
        libreoffice-writer-nogui libreoffice-calc-nogui libreoffice-impress-nogui \
        ure uno-libs-private \
        libuno-sal3t64 libuno-salhelpergcc3-3t64 \
        libuno-cppu3t64 libuno-cppuhelpergcc3-3t64 \
        libuno-purpenvhelpergcc3-3t64 \
        >/dev/null 2>&1 || true
    fi
    if ! ls ./libreoffice-core*.deb >/dev/null 2>&1 && ! ls ./ure*.deb >/dev/null 2>&1; then
      echo "WARNING: could not download LibreOffice debs." >&2
      return 1
    fi
    rm -rf extracted
    mkdir -p extracted
    for deb in ./*.deb; do
      dpkg-deb -x "$deb" extracted/ 2>/dev/null || true
    done
  )

  local bin=""
  bin="$(find "$work/extracted" -path '*/program/soffice.bin' 2>/dev/null | head -1 || true)"
  if [[ -z "$bin" ]]; then
    echo "WARNING: extracted LibreOffice soffice not found." >&2
    return 1
  fi

  local lo_home="$ENGINES/libreoffice"
  rm -rf "$lo_home"
  mkdir -p "$lo_home"
  if [[ -d "$work/extracted/usr" ]]; then
    cp -a "$work/extracted/usr/." "$lo_home/" 2>/dev/null || true
  else
    cp -a "$work/extracted/." "$lo_home/" 2>/dev/null || true
  fi
  # Avoid dangling multiarch uno symlinks: copy real files only.
  local program_dir=""
  program_dir="$(find "$lo_home" -path '*/lib/libreoffice/program' -type d 2>/dev/null | head -1 || true)"
  if [[ -n "$program_dir" && -d "$work/extracted/usr/lib/libreoffice/program" ]]; then
    for f in libuno_sal.so.3 libuno_cppu.so.3 libuno_cppuhelpergcc3.so.3 \
             libuno_salhelpergcc3.so.3 libuno_purpenvhelpergcc3.so.3; do
      if [[ -f "$work/extracted/usr/lib/libreoffice/program/$f" ]]; then
        rm -f "$program_dir/$f"
        cp -a "$work/extracted/usr/lib/libreoffice/program/$f" "$program_dir/$f"
      fi
    done
  fi
  # Multiarch deps into engines/lib (dereferenced).
  if [[ -d "$work/extracted/usr/lib/x86_64-linux-gnu" ]]; then
    find "$work/extracted/usr/lib/x86_64-linux-gnu" -maxdepth 1 \( -type f -o -type l \) \
      -name '*.so*' ! -name 'libuno_*' -exec cp -aL {} "$ENGINES/lib/" \; 2>/dev/null || true
  fi
  if [[ -n "$program_dir" && -x "$program_dir/soffice.bin" ]]; then
    copy_ldd_closure "$program_dir/soffice.bin"
  fi

  write_soffice_wrapper
  local ver_out=""
  ver_out="$("$ENGINES/soffice" --version 2>&1 || true)"
  if [[ -z "$ver_out" ]] || echo "$ver_out" | grep -qi 'DeploymentException\|not found'; then
    echo "WARNING: Ubuntu-extracted soffice failed --version: $ver_out" >&2
    return 1
  fi
  echo "Bundled soffice OK: $(echo "$ver_out" | head -1)"
  return 0
}

bundle_soffice() {
  # Prefer a self-contained Document Foundation tree so convert works offline.
  if bundle_soffice_from_official; then
    return 0
  fi

  local src
  src="$(command -v soffice 2>/dev/null || true)"
  if [[ -z "$src" ]]; then
    src="$(command -v libreoffice 2>/dev/null || true)"
  fi
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "LibreOffice not on PATH — attempting apt install (non-interactive)…"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y libreoffice-writer-nogui libreoffice-calc-nogui \
        libreoffice-impress-nogui >/dev/null 2>&1 || true
      apt-get install -y libreoffice-writer libreoffice-calc libreoffice-impress \
        >/dev/null 2>&1 || true
    fi
    src="$(command -v soffice 2>/dev/null || command -v libreoffice 2>/dev/null || true)"
  fi
  if [[ -n "$src" && -x "$src" ]]; then
    echo "Bundling LibreOffice from $src (thin wrapper)"
    cat > "$ENGINES/soffice" <<WRAP
#!/usr/bin/env bash
exec "$src" "\$@"
WRAP
    chmod +x "$ENGINES/soffice"
    if "$ENGINES/soffice" --version >/dev/null 2>&1 || \
       "$ENGINES/soffice" --headless --version >/dev/null 2>&1; then
      echo "Bundled soffice OK: $("$ENGINES/soffice" --version 2>&1 | head -1)"
      return 0
    fi
  fi

  echo "LibreOffice PATH/apt incomplete — trying Ubuntu deb extract…"
  if bundle_soffice_from_debs; then
    return 0
  fi
  echo "LibreOffice (soffice) not available — the .deb/.exe/.dmg cannot ship without it." >&2
  return 1
}

bundle_ffmpeg_from_debs() {
  local work="$ROOT/.tools/ffmpeg_extract"
  mkdir -p "$work"
  echo "Downloading portable ffmpeg packages into $work …"
  (
    cd "$work"
    if command -v apt-get >/dev/null 2>&1; then
      # Package SONAMEs vary by Ubuntu release; download what apt knows.
      apt-get download ffmpeg \
        libavcodec62 libavcodec61 \
        libavformat62 libavformat61 \
        libavutil60 libavutil59 \
        libswscale9 libswscale8 \
        libswresample6 libswresample5 \
        libavfilter11 libavfilter10 \
        libavdevice62 libavdevice61 \
        >/dev/null 2>&1 || true
      apt-get download ffmpeg libavdevice62 libavcodec62 libavformat62 \
        libavutil60 libswscale9 libswresample6 libavfilter11 \
        >/dev/null 2>&1 || true
    fi
    if ! ls ./ffmpeg*.deb >/dev/null 2>&1; then
      echo "WARNING: could not download ffmpeg debs." >&2
      return 1
    fi
    rm -rf extracted
    mkdir -p extracted
    for deb in ./*.deb; do
      dpkg-deb -x "$deb" extracted/ 2>/dev/null || true
    done
  )

  local bin=""
  # Prefer the real ELF under usr/bin — avoid lintian override files named "ffmpeg".
  bin="$(find "$work/extracted" -path '*/usr/bin/ffmpeg' -type f 2>/dev/null | head -1 || true)"
  if [[ -z "$bin" ]]; then
    bin="$(find "$work/extracted" -path '*/bin/ffmpeg' -type f 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "$bin" || ! -f "$bin" ]]; then
    echo "WARNING: extracted ffmpeg binary not found." >&2
    return 1
  fi
  echo "Bundling portable ffmpeg from $bin"
  mkdir -p "$ENGINES/bin" "$ENGINES/lib"
  copy_file "$bin" "$ENGINES/bin/ffmpeg"
  chmod +x "$ENGINES/bin/ffmpeg"
  find "$work/extracted" -type f \( \
      -name 'libav*.so*' -o -name 'libsw*.so*' -o -name 'libpostproc.so*' \
    \) -exec cp -a {} "$ENGINES/lib/" \; 2>/dev/null || true
  find "$work/extracted" -type l \( \
      -name 'libav*.so*' -o -name 'libsw*.so*' -o -name 'libpostproc.so*' \
    \) -exec cp -a {} "$ENGINES/lib/" \; 2>/dev/null || true
  copy_ldd_closure "$ENGINES/bin/ffmpeg"
  write_ld_wrapper "ffmpeg"
  if ! "$ENGINES/ffmpeg" -version >/dev/null 2>&1; then
    echo "WARNING: bundled ffmpeg failed -version smoke test." >&2
    return 1
  fi
  echo "Bundled ffmpeg OK: $("$ENGINES/ffmpeg" -version 2>&1 | head -1)"
  return 0
}

bundle_ffmpeg() {
  local src
  src="$(command -v ffmpeg 2>/dev/null || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "ffmpeg not on PATH — attempting apt install (non-interactive)…"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y ffmpeg >/dev/null 2>&1 || true
    fi
    src="$(command -v ffmpeg 2>/dev/null || true)"
  fi
  if [[ -n "$src" && -x "$src" ]]; then
    echo "Bundling ffmpeg from $src"
    mkdir -p "$ENGINES/bin" "$ENGINES/lib"
    copy_file "$src" "$ENGINES/bin/ffmpeg"
    copy_ldd_closure "$ENGINES/bin/ffmpeg"
    write_ld_wrapper "ffmpeg"
    if "$ENGINES/ffmpeg" -version >/dev/null 2>&1; then
      echo "Bundled ffmpeg OK: $("$ENGINES/ffmpeg" -version 2>&1 | head -1)"
      return 0
    fi
  fi
  echo "ffmpeg PATH/apt incomplete — trying portable deb extract…"
  if bundle_ffmpeg_from_debs; then
    return 0
  fi
  echo "ffmpeg not available — camera capture will report engine missing."
  return 0
}

write_ld_wrapper() {
  local name="$1"
  cat > "$ENGINES/$name" <<WRAP
#!/usr/bin/env bash
ROOT="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$ROOT/lib:\${LD_LIBRARY_PATH:-}"
exec "\$ROOT/bin/$name" "\$@"
WRAP
  chmod +x "$ENGINES/$name"
}

# Copy direct + transitive shared libs needed to run [bin] with only engines/lib.
copy_ldd_closure() {
  local bin="$1"
  local pass
  for pass in 1 2 3 4; do
    if ! command -v ldd >/dev/null 2>&1; then
      return 0
    fi
    while read -r line; do
      local libpath
      libpath="$(echo "$line" | awk '/=>/ {print $3}')"
      if [[ -n "$libpath" && -f "$libpath" ]]; then
        case "$libpath" in
          /lib/*|/lib64/*|/usr/lib/*)
            copy_lib_safe "$libpath"
            ;;
        esac
      fi
    done < <(LD_LIBRARY_PATH="$ENGINES/lib:${LD_LIBRARY_PATH:-}" ldd "$bin" 2>/dev/null || true)
  done
}

bundle_cli_from_path() {
  local name="$1"
  local src
  src="$(command -v "$name" 2>/dev/null || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    return 1
  fi
  echo "Bundling $name from $src"
  mkdir -p "$ENGINES/bin" "$ENGINES/lib"
  copy_file "$src" "$ENGINES/bin/$name"
  copy_ldd_closure "$ENGINES/bin/$name"
  write_ld_wrapper "$name"
  return 0
}

bundle_dsc_tools_from_debs() {
  # Portable fallback when apt install needs sudo / tools missing from PATH:
  # download Ubuntu packages and extract pdfsig + NSS tools + shared libs.
  local work="$ROOT/.tools/dsc_extract"
  mkdir -p "$work"
  echo "Downloading portable DSC (pdfsig/NSS) packages into $work …"
  (
    cd "$work"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get download poppler-utils libpoppler156 libnss3-tools libnss3 libnspr4 \
        libnssutil3 libplc4 libplds4 openssl libssl3t64 libssl3 >/dev/null 2>&1 || true
      # Older package names on some Ubuntu releases.
      apt-get download libssl3 >/dev/null 2>&1 || true
    fi
    if ! ls ./poppler-utils*.deb >/dev/null 2>&1; then
      local poppler_base="http://archive.ubuntu.com/ubuntu/pool/main/p/poppler"
      local nss_base="http://archive.ubuntu.com/ubuntu/pool/main/n/nss"
      local nspr_base="http://archive.ubuntu.com/ubuntu/pool/main/n/nspr"
      local ssl_base="http://archive.ubuntu.com/ubuntu/pool/main/o/openssl"
      for url in \
        "$poppler_base/poppler-utils_24.02.0-1ubuntu9_amd64.deb" \
        "$poppler_base/libpoppler134_24.02.0-1ubuntu9_amd64.deb" \
        "$nss_base/libnss3-tools_3.98-1build1_amd64.deb" \
        "$nss_base/libnss3_3.98-1build1_amd64.deb" \
        "$nspr_base/libnspr4_4.35-1.1build1_amd64.deb" \
        "$ssl_base/openssl_3.0.13-0ubuntu3_amd64.deb"
      do
        curl -fsSL -O "$url" 2>/dev/null || wget -q "$url" 2>/dev/null || true
      done
    fi
    if ! ls ./*.deb >/dev/null 2>&1; then
      echo "WARNING: could not download DSC/poppler/NSS debs." >&2
      return 1
    fi
    mkdir -p extracted
    for deb in ./*.deb; do
      dpkg-deb -x "$deb" extracted/ 2>/dev/null || true
    done
  )

  mkdir -p "$ENGINES/bin" "$ENGINES/lib"
  local ok=0
  for name in pdfsig certutil pk12util openssl; do
    local bin=""
    bin="$(find "$work/extracted" -type f -name "$name" 2>/dev/null | head -1 || true)"
    if [[ -n "$bin" && -x "$bin" ]]; then
      echo "Bundling portable $name from $bin"
      copy_file "$bin" "$ENGINES/bin/$name"
      write_ld_wrapper "$name"
      ok=1
    fi
  done
  # Shared libs from extracted packages (poppler + NSS + NSPR + OpenSSL).
  find "$work/extracted" -type f \( \
      -name 'libpoppler.so*' -o -name 'libnss3.so*' -o -name 'libnssutil3.so*' \
      -o -name 'libsmime3.so*' -o -name 'libssl3.so*' -o -name 'libnspr4.so*' \
      -o -name 'libplc4.so*' -o -name 'libplds4.so*' -o -name 'libcrypto.so*' \
      -o -name 'libssl.so*' \
    \) -exec cp -a {} "$ENGINES/lib/" \; 2>/dev/null || true
  find "$work/extracted" -type l \( \
      -name 'libpoppler.so*' -o -name 'libnss*.so*' -o -name 'libsmime3.so*' \
      -o -name 'libssl3.so*' -o -name 'libnspr4.so*' -o -name 'libplc4.so*' \
      -o -name 'libplds4.so*' -o -name 'libcrypto.so*' -o -name 'libssl.so*' \
    \) -exec cp -a {} "$ENGINES/lib/" \; 2>/dev/null || true

  for name in pdfsig certutil pk12util openssl; do
    if [[ -x "$ENGINES/bin/$name" ]]; then
      copy_ldd_closure "$ENGINES/bin/$name"
    fi
  done

  if [[ "$ok" -eq 0 ]]; then
    echo "WARNING: extracted DSC binaries not found." >&2
    return 1
  fi
  return 0
}

bundle_dsc_tools() {
  # Certificate signing stack: pdfsig (poppler), certutil+pk12util (NSS), openssl.
  local need_debs=0
  for name in pdfsig certutil pk12util openssl; do
    if ! bundle_cli_from_path "$name"; then
      need_debs=1
    fi
  done
  if [[ "$need_debs" -eq 1 ]]; then
    echo "Some DSC tools missing on PATH — attempting apt install (non-interactive)…"
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y poppler-utils libnss3-tools openssl >/dev/null 2>&1 || true
    fi
    for name in pdfsig certutil pk12util openssl; do
      if [[ ! -x "$ENGINES/bin/$name" ]]; then
        bundle_cli_from_path "$name" || true
      fi
    done
  fi
  if [[ ! -x "$ENGINES/bin/pdfsig" || ! -x "$ENGINES/bin/certutil" || ! -x "$ENGINES/bin/pk12util" ]]; then
    echo "DSC tools still incomplete — trying portable deb extract…"
    bundle_dsc_tools_from_debs || true
  fi

  # Smoke-test wrappers so a machine without system poppler can still run them.
  for name in pdfsig certutil pk12util openssl; do
    if [[ -x "$ENGINES/$name" ]]; then
      case "$name" in
        pdfsig)
          if ! "$ENGINES/pdfsig" -v >/dev/null 2>&1 && ! "$ENGINES/pdfsig" --help >/dev/null 2>&1; then
            echo "WARNING: bundled pdfsig failed version/help smoke test." >&2
          else
            echo "Bundled pdfsig OK: $("$ENGINES/pdfsig" -v 2>&1 | head -1)"
          fi
          ;;
        openssl)
          if "$ENGINES/openssl" version >/dev/null 2>&1; then
            echo "Bundled openssl OK: $("$ENGINES/openssl" version 2>&1 | head -1)"
          fi
          ;;
        certutil|pk12util)
          if "$ENGINES/$name" -H >/dev/null 2>&1 || "$ENGINES/$name" --help >/dev/null 2>&1; then
            echo "Bundled $name OK"
          else
            # Help exits non-zero on some NSS builds; binary presence is enough.
            echo "Bundled $name present at $ENGINES/$name"
          fi
          ;;
      esac
    else
      echo "WARNING: $name was not bundled into $ENGINES" >&2
    fi
  done
}

# osd.traineddata (page orientation for OCR auto-rotate) plus any extra
# languages in DS_TESSDATA_LANGS (space/comma separated, e.g. "hin deu").
# Downloads are cached under .tools/tessdata so rebuilds stay offline.
bundle_tessdata_extras() {
  local cache="$ROOT/.tools/tessdata"
  mkdir -p "$cache" "$ENGINES/tessdata"
  local code extra="${DS_TESSDATA_LANGS:-}"
  for code in osd ${extra//,/ }; do
    [[ "$code" =~ ^[a-z][a-z_]+$ ]] || continue
    local dest="$ENGINES/tessdata/$code.traineddata"
    [[ -s "$dest" ]] && continue
    local src=""
    for dir in /usr/share/tesseract-ocr/5/tessdata /usr/share/tesseract-ocr/4.00/tessdata \
               /usr/share/tessdata "$cache"; do
      if [[ -s "$dir/$code.traineddata" ]]; then
        src="$dir/$code.traineddata"
        break
      fi
    done
    if [[ -z "$src" ]]; then
      echo "Fetching $code.traineddata from tessdata_fast…"
      local url="https://github.com/tesseract-ocr/tessdata_fast/raw/main/$code.traineddata"
      if curl -fsSL --retry 2 -o "$cache/$code.traineddata.part" "$url" 2>/dev/null \
         || wget -q -O "$cache/$code.traineddata.part" "$url" 2>/dev/null; then
        mv -f "$cache/$code.traineddata.part" "$cache/$code.traineddata"
        src="$cache/$code.traineddata"
      else
        rm -f "$cache/$code.traineddata.part"
        echo "WARNING: could not fetch $code.traineddata (OCR still works; users can download it in the app)." >&2
        continue
      fi
    fi
    cp -a "$src" "$dest" || true
  done
}

bundle_tesseract
bundle_tessdata_extras
if ! bundle_soffice; then
  echo "ERROR: LibreOffice was not bundled into $ENGINES" >&2
  exit 1
fi
bundle_ffmpeg
bundle_dsc_tools

if [[ -x "$ENGINES/qpdf" || -x "$ENGINES/bin/qpdf" ]]; then
  echo "Engines ready under $ENGINES"
  "$ENGINES/bin/qpdf" --version 2>/dev/null || "$ENGINES/qpdf" --version 2>/dev/null || true
else
  echo "WARNING: qpdf was not bundled into $ENGINES" >&2
fi
