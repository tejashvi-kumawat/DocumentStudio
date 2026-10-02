#!/usr/bin/env bash
# Copy / download desktop engines into a Flutter macOS .app bundle.
# Non-interactive: Homebrew installs use NONINTERACTIVE=1; LibreOffice is
# taken from the official Document Foundation DMG and copied into
# engines/LibreOffice.app (same idea as Linux's official tarball), not a
# thin wrapper to /Applications.
#
# Usage (on a Mac):
#   flutter build macos --release
#   bash scripts/bundle_macos_engines.sh [path/to/document_studio.app]
#
# Layout: Contents/MacOS/engines/{bin,lib,tessdata,LibreOffice.app} + wrappers.
# Arch: host arch only (arm64 / x86_64). See docs/ENGINES.md for universal notes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="${1:-}"
if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$(find "$ROOT/build/macos" -name 'document_studio.app' -type d 2>/dev/null | head -1 || true)"
fi
if [[ -z "${BUNDLE_DIR:-}" || ! -d "$BUNDLE_DIR" ]]; then
  echo "usage: $0 <document_studio.app>" >&2
  echo "Run on macOS after: flutter build macos --release" >&2
  exit 2
fi
BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "bundle_macos_engines.sh must run on macOS (Homebrew / hdiutil / Mach-O)." >&2
  exit 1
fi

if [[ -d "$BUNDLE_DIR/Contents/MacOS" ]]; then
  ENGINES="$BUNDLE_DIR/Contents/MacOS/engines"
  RESOURCES_ENGINES="$BUNDLE_DIR/Contents/Resources/engines"
else
  ENGINES="$BUNDLE_DIR/engines"
  RESOURCES_ENGINES=""
fi
mkdir -p "$ENGINES/bin" "$ENGINES/lib" "$ENGINES/tessdata"

HOST_ARCH="$(uname -m)"
CACHE="$ROOT/.tools/macos"
mkdir -p "$CACHE"
LO_VER="${DS_LIBREOFFICE_VERSION:-26.8.1}"
# Prefer university mirrors — download.documentfoundation.org often 504s in CI.
LO_MIRRORS=(
  "https://ftp.osuosl.org/pub/tdf/libreoffice/stable"
  "https://mirror.csclub.uwaterloo.ca/tdf/libreoffice/stable"
  "https://download.documentfoundation.org/libreoffice/stable"
)
# If preferred version fails, try these (still/fresh).
LO_VERSION_FALLBACKS=(
  "$LO_VER"
  "26.8.1"
  "26.8.0"
  "26.2.6"
  "25.8.7"
)

export NONINTERACTIVE=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

echo "Bundling macOS engines for host arch: $HOST_ARCH"

copy_file() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  chmod +x "$dest" 2>/dev/null || true
}

write_wrapper() {
  local name="$1"
  cat > "$ENGINES/$name" <<WRAP
#!/usr/bin/env bash
ROOT="\$(cd "\$(dirname "\$0")" && pwd)"
export DYLD_LIBRARY_PATH="\$ROOT/lib:\${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="\$ROOT/lib:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
if [[ -d "\$ROOT/tessdata" ]]; then
  export TESSDATA_PREFIX="\$ROOT/tessdata"
fi
exec "\$ROOT/bin/$name" "\$@"
WRAP
  chmod +x "$ENGINES/$name"
}

# Copy dylibs referenced by a Mach-O binary into engines/lib (best-effort).
copy_dylib_closure() {
  local bin="$1"
  command -v otool >/dev/null 2>&1 || return 0
  local line lib
  while IFS= read -r line; do
    lib="$(echo "$line" | awk '{print $1}')"
    case "$lib" in
      /usr/lib/*|/System/*|@*) continue ;;
    esac
    if [[ -f "$lib" ]]; then
      cp -a "$lib" "$ENGINES/lib/" 2>/dev/null || true
    fi
  done < <(otool -L "$bin" 2>/dev/null | tail -n +2 || true)
}

ensure_brew_formula() {
  local formula="$1"
  command -v brew >/dev/null 2>&1 || return 1
  if brew list --formula "$formula" >/dev/null 2>&1; then
    return 0
  fi
  echo "brew install $formula (non-interactive)…"
  brew install "$formula" || return 1
}

bundle_one() {
  local name="$1"
  local brew_formula="${2:-}"
  local src
  src="$(command -v "$name" 2>/dev/null || true)"
  if [[ -z "$src" || ! -x "$src" ]]; then
    if [[ -n "$brew_formula" ]]; then
      ensure_brew_formula "$brew_formula" || true
      src="$(command -v "$name" 2>/dev/null || true)"
      if [[ -z "$src" ]]; then
        local brew_prefix
        brew_prefix="$(brew --prefix "$brew_formula" 2>/dev/null || true)"
        if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/$name" ]]; then
          src="$brew_prefix/bin/$name"
        fi
        # Homebrew nss tools often live under libexec / bin after keg-only link.
        if [[ -z "$src" && "$brew_formula" == "nss" && -n "$brew_prefix" ]]; then
          if [[ -x "$brew_prefix/bin/$name" ]]; then
            src="$brew_prefix/bin/$name"
          elif [[ -x "/opt/homebrew/opt/nss/bin/$name" ]]; then
            src="/opt/homebrew/opt/nss/bin/$name"
          elif [[ -x "/usr/local/opt/nss/bin/$name" ]]; then
            src="/usr/local/opt/nss/bin/$name"
          fi
        fi
        if [[ -z "$src" && "$brew_formula" == "openssl" ]]; then
          for cand in \
            "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" \
            "$(brew --prefix openssl 2>/dev/null)/bin/openssl" \
            /opt/homebrew/opt/openssl/bin/openssl \
            /usr/local/opt/openssl/bin/openssl
          do
            if [[ -n "$cand" && -x "$cand" ]]; then src="$cand"; break; fi
          done
        fi
      fi
    fi
  fi
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "WARNING: $name not available for macOS bundle (brew install ${brew_formula:-$name})." >&2
    return 1
  fi
  echo "Bundling macOS $name from $src"
  copy_file "$src" "$ENGINES/bin/$name"
  copy_dylib_closure "$ENGINES/bin/$name"
  write_wrapper "$name"
}

bundle_tessdata() {
  local cache="$ROOT/.tools/tessdata"
  mkdir -p "$cache" "$ENGINES/tessdata"
  local code
  for code in eng osd; do
    local dest="$ENGINES/tessdata/$code.traineddata"
    [[ -s "$dest" ]] && continue
    local src=""
    for dir in \
      "$(brew --prefix tesseract 2>/dev/null)/share/tessdata" \
      /opt/homebrew/share/tessdata \
      /usr/local/share/tessdata \
      "$cache"
    do
      [[ -n "$dir" && -s "$dir/$code.traineddata" ]] || continue
      src="$dir/$code.traineddata"
      break
    done
    if [[ -z "$src" ]]; then
      echo "Fetching $code.traineddata…"
      local url="https://github.com/tesseract-ocr/tessdata_fast/raw/main/$code.traineddata"
      if curl -fsSL --retry 3 -o "$cache/$code.traineddata" "$url"; then
        src="$cache/$code.traineddata"
      fi
    fi
    [[ -n "$src" ]] && cp -a "$src" "$dest"
  done
}

bundle_soffice_from_dmg() {
  # Official Document Foundation DMG → engines/LibreOffice.app (self-contained).
  if [[ "${DS_SKIP_LIBREOFFICE:-}" == "1" ]]; then
    echo "Skipping LibreOffice (DS_SKIP_LIBREOFFICE=1)."
    return 1
  fi
  local dmg_arch dmg_name_for_ver url dmg mount ver tried name
  case "$HOST_ARCH" in
    arm64|aarch64) dmg_arch="aarch64" ;;
    x86_64|amd64)  dmg_arch="x86_64" ;;
    *)
      echo "WARNING: unsupported macOS arch $HOST_ARCH for LibreOffice DMG." >&2
      return 1
      ;;
  esac

  lo_dmg_filename() {
    local v="$1"
    if [[ "$dmg_arch" == "aarch64" ]]; then
      echo "LibreOffice_${v}_MacOS_aarch64.dmg"
    else
      echo "LibreOffice_${v}_MacOS_x86-64.dmg"
    fi
  }

  download_lo_dmg() {
    local dest="$1" src_url="$2"
    rm -f "$dest.partial"
    # --retry-all-errors catches 502/504; long connect helps flaky CDNs.
    if curl -fL \
      --retry 5 \
      --retry-all-errors \
      --retry-delay 3 \
      --connect-timeout 30 \
      --max-time 1800 \
      -o "$dest.partial" \
      "$src_url"
    then
      mv -f "$dest.partial" "$dest"
      return 0
    fi
    rm -f "$dest.partial"
    return 1
  }

  # Explicit override wins.
  if [[ -n "${DS_LIBREOFFICE_DMG_URL:-}" ]]; then
    name="$(basename "${DS_LIBREOFFICE_DMG_URL%%\?*}")"
    dmg="$CACHE/$name"
    if [[ ! -s "$dmg" ]]; then
      echo "Downloading LibreOffice DMG from DS_LIBREOFFICE_DMG_URL…"
      download_lo_dmg "$dmg" "$DS_LIBREOFFICE_DMG_URL" || {
        echo "WARNING: LibreOffice DMG download failed: $DS_LIBREOFFICE_DMG_URL" >&2
        return 1
      }
    fi
  else
    dmg=""
    # Reuse any cached official DMG first.
    for ver in "${LO_VERSION_FALLBACKS[@]}"; do
      [[ -z "$ver" ]] && continue
      name="$(lo_dmg_filename "$ver")"
      if [[ -s "$CACHE/$name" ]]; then
        dmg="$CACHE/$name"
        echo "Using cached LibreOffice DMG: $dmg"
        break
      fi
    done

    if [[ -z "$dmg" ]]; then
      tried=()
      # Unique versions preserving order.
      local -a versions=()
      local v seen
      for v in "${LO_VERSION_FALLBACKS[@]}"; do
        [[ -z "$v" ]] && continue
        seen=0
        for x in "${versions[@]:-}"; do [[ "$x" == "$v" ]] && seen=1 && break; done
        [[ $seen -eq 0 ]] && versions+=("$v")
      done

      for ver in "${versions[@]}"; do
        name="$(lo_dmg_filename "$ver")"
        dmg="$CACHE/$name"
        for mirror in "${LO_MIRRORS[@]}"; do
          url="${mirror}/${ver}/mac/${dmg_arch}/${name}"
          tried+=("$url")
          echo "Downloading LibreOffice DMG ($ver / $dmg_arch)…"
          echo "  $url"
          if download_lo_dmg "$dmg" "$url"; then
            echo "Downloaded LibreOffice $ver from $mirror"
            break 2
          fi
          echo "WARNING: download failed: $url" >&2
          rm -f "$dmg"
        done
      done
      if [[ ! -s "${dmg:-}" ]]; then
        echo "WARNING: all LibreOffice DMG mirrors failed:" >&2
        printf '  %s\n' "${tried[@]}" >&2
        return 1
      fi
    fi
  fi

  mount="$(mktemp -d "$CACHE/lo-mount.XXXXXX")"
  echo "Attaching $dmg …"
  if ! hdiutil attach "$dmg" -mountpoint "$mount" -nobrowse -readonly -quiet; then
    echo "WARNING: hdiutil attach failed for LibreOffice DMG." >&2
    rm -rf "$mount"
    # Corrupt cache — force re-download next time.
    rm -f "$dmg"
    return 1
  fi
  local app_src=""
  app_src="$(find "$mount" -maxdepth 2 -name 'LibreOffice.app' -type d 2>/dev/null | head -1 || true)"
  if [[ -z "$app_src" || ! -d "$app_src" ]]; then
    echo "WARNING: LibreOffice.app not found inside DMG." >&2
    hdiutil detach "$mount" -quiet || true
    rm -rf "$mount"
    return 1
  fi
  echo "Copying LibreOffice.app into engines/ (large)…"
  rm -rf "$ENGINES/LibreOffice.app"
  cp -a "$app_src" "$ENGINES/LibreOffice.app"
  hdiutil detach "$mount" -quiet || true
  rm -rf "$mount"

  cat > "$ENGINES/soffice" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
SOFFICE="$ROOT/LibreOffice.app/Contents/MacOS/soffice"
if [[ ! -x "$SOFFICE" ]]; then
  echo "bundled LibreOffice soffice not found at $SOFFICE" >&2
  exit 127
fi
exec "$SOFFICE" "$@"
WRAP
  chmod +x "$ENGINES/soffice"

  if "$ENGINES/soffice" --version >/dev/null 2>&1 || \
     "$ENGINES/soffice" --headless --version >/dev/null 2>&1; then
    echo "Bundled soffice OK: $("$ENGINES/soffice" --version 2>&1 | head -1)"
    return 0
  fi
  echo "WARNING: bundled soffice --version failed" >&2
  return 0
}

bundle_soffice_from_brew_cask() {
  # When TDF CDN is down, Homebrew cask may still resolve (or reuse cache).
  command -v brew >/dev/null 2>&1 || return 1
  echo "Trying LibreOffice via Homebrew cask…"
  NONINTERACTIVE=1 brew install --cask libreoffice || \
    NONINTERACTIVE=1 brew reinstall --cask libreoffice || return 1
  local app=""
  local cand
  for cand in \
    "/Applications/LibreOffice.app" \
    "$HOME/Applications/LibreOffice.app"
  do
    if [[ -d "$cand" && -x "$cand/Contents/MacOS/soffice" ]]; then
      app="$cand"
      break
    fi
  done
  if [[ -z "$app" ]]; then
    # Caskroom layout: …/Caskroom/libreoffice/<ver>/LibreOffice.app
    cand="$(find "$(brew --prefix)/Caskroom/libreoffice" -maxdepth 2 -type d -name 'LibreOffice.app' 2>/dev/null | head -1 || true)"
    if [[ -n "$cand" && -x "$cand/Contents/MacOS/soffice" ]]; then
      app="$cand"
    fi
  fi
  if [[ -z "$app" ]]; then
    echo "WARNING: LibreOffice.app not found after brew cask install." >&2
    return 1
  fi
  echo "Copying LibreOffice.app from $app into engines/…"
  rm -rf "$ENGINES/LibreOffice.app"
  cp -a "$app" "$ENGINES/LibreOffice.app"
  cat > "$ENGINES/soffice" <<'WRAP'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
exec "$ROOT/LibreOffice.app/Contents/MacOS/soffice" "$@"
WRAP
  chmod +x "$ENGINES/soffice"
  echo "Bundled soffice from brew cask OK"
  return 0
}

bundle_soffice_fallback() {
  # Last resort: wrap a system /Applications install (not preferred for shipping).
  local src=""
  src="$(command -v soffice 2>/dev/null || true)"
  if [[ -z "$src" ]]; then
    for cand in \
      /Applications/LibreOffice.app/Contents/MacOS/soffice \
      "$HOME/Applications/LibreOffice.app/Contents/MacOS/soffice"
    do
      if [[ -x "$cand" ]]; then src="$cand"; break; fi
    done
  fi
  if [[ -z "$src" || ! -x "$src" ]]; then
    echo "WARNING: LibreOffice (soffice) not bundled." >&2
    return 1
  fi
  cat > "$ENGINES/soffice" <<WRAP
#!/usr/bin/env bash
exec "$src" "\$@"
WRAP
  chmod +x "$ENGINES/soffice"
  echo "Bundled soffice wrapper → $src (system install; prefer official DMG for releases)"
}

# Core PDF / OCR / media / signing tools via Homebrew formulas.
bundle_one qpdf qpdf || true
bundle_one tesseract tesseract || true
bundle_tessdata
bundle_one pdfsig poppler || true
# NSS is keg-only; force formula then resolve bin/
ensure_brew_formula nss || true
bundle_one certutil nss || true
bundle_one pk12util nss || true
bundle_one openssl openssl || true
bundle_one ffmpeg ffmpeg || true

if ! bundle_soffice_from_dmg; then
  if ! bundle_soffice_from_brew_cask; then
    bundle_soffice_fallback || true
  fi
fi

if [[ ! -x "$ENGINES/soffice" && -x "$ENGINES/libreoffice" ]]; then
  ln -sfn libreoffice "$ENGINES/soffice" 2>/dev/null || cp -a "$ENGINES/libreoffice" "$ENGINES/soffice"
fi

# Mirror into Resources for completeness (same tree).
if [[ -n "${RESOURCES_ENGINES:-}" ]]; then
  mkdir -p "$(dirname "$RESOURCES_ENGINES")"
  rm -rf "$RESOURCES_ENGINES"
  cp -a "$ENGINES" "$RESOURCES_ENGINES"
fi

echo
echo "macOS engines directory: $ENGINES ($HOST_ARCH)"
missing=()
for name in qpdf tesseract ffmpeg openssl pdfsig certutil pk12util soffice; do
  if [[ ! -x "$ENGINES/$name" && ! -x "$ENGINES/bin/$name" ]]; then
    missing+=("$name")
  fi
done
if [[ ! -s "$ENGINES/tessdata/eng.traineddata" || ! -s "$ENGINES/tessdata/osd.traineddata" ]]; then
  missing+=("tessdata(eng/osd)")
fi
if ((${#missing[@]})); then
  echo "ERROR: the .dmg is missing engines: ${missing[*]}" >&2
  echo "qpdf, tesseract, and LibreOffice must be inside the app." >&2
  exit 1
fi
echo "All expected engines present."
bash "$ROOT/scripts/copy_third_party_licenses_to_bundle.sh" "$ENGINES" || true
ls -la "$ENGINES" "$ENGINES/bin" 2>/dev/null || true
echo
echo "Codesign (ad-hoc, no Apple ID):"
echo "  codesign --force --deep --sign - \"$BUNDLE_DIR\""
echo "Universal binary note: this script copies host-arch brew binaries only."
echo "  For Intel+Apple Silicon, run on each arch (or use Rosetta brew) and lipo."
