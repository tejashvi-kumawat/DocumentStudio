# Desktop engine bundling — Document Studio

External CLIs the app may shell out to. **Installers must ship these** (or a documented first-run path into app storage). Never rely on the end user’s system PATH alone.

## Tool × feature

| Tool | Features |
| --- | --- |
| **qpdf** | Encrypt/unlock, metadata, crop/resize boxes, compress (preferred), searchable-PDF overlay, some markup/signing helpers |
| **tesseract** (+ `eng`/`osd` tessdata) | Image OCR, searchable PDF, Find-in-scan |
| **soffice** (LibreOffice) | Office → PDF conversion |
| **pdfsig** / **certutil** / **pk12util** / **openssl** | Certificate PDF signing & validation |
| **ffmpeg** | Desktop camera capture insert |
| **pdfrx / PDFium** (Dart) | View, merge/split/rotate/delete pages, images↔PDF (all platforms including Android) |

Not used by the app: `pdftotext`, `pdfinfo`, `pdftoppm`, `mutool`, `gs`, ImageMagick.

## Runtime resolver

`lib/core/desktop/desktop_engine_resolver.dart` looks in bundled `engines/` **before** PATH. Wrappers under `engines/<name>` set `LD_LIBRARY_PATH` / `TESSDATA_PREFIX` / `DYLD_*`. Bootstrap seeds qpdf via the same resolver.

Missing tools must surface a clear UI message (feature + why), not fail silently.

## Platform matrix

| Tool | Linux (.deb / AppImage) | Windows (.exe / zip) | macOS (.dmg) | Android (Play) |
| --- | --- | --- | --- | --- |
| qpdf | **Bundled** (`scripts/bundle_linux_engines.sh`) | **Bundled** (mingw64 zip at build) | **Bundled** (Homebrew copy) | **N/A** — use pdfrx where possible; protect/metadata UI explains desktop-only |
| tesseract + eng/osd | **Bundled** | **Bundled** (NSIS silent install + tessdata_fast) | **Bundled** (brew + tessdata_fast) | **N/A** — `BlockedOcrPort` message |
| LibreOffice | **Bundled** (Document Foundation tarball / debs) | **Bundled** (official MSI → `engines/libreoffice`) | **Bundled** (official DMG → `engines/LibreOffice.app`) | **N/A** — convert on desktop |
| pdfsig / NSS / openssl | **Bundled** (PATH or portable debs) | **Bundled** (poppler zip + OpenSSL Light + MSYS2 NSS) | **Bundled** via brew | **N/A** |
| ffmpeg | **Bundled** | **Bundled** (gyan essentials zip or PATH) | **Bundled** via brew | Mobile uses platform camera APIs |

## Linux build machine

CMake `install(CODE)` runs `scripts/bundle_linux_engines.sh`. Packaging scripts call it again before `.deb` / AppImage.

```bash
flutter build linux --release
bash scripts/linux/package_deb.sh
bash scripts/linux/package_appimage.sh
```

Caches under `.tools/` (qpdf zip, tesseract debs, LibreOffice, ffmpeg, tessdata).

## Windows build machine

**One command:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\package_release.ps1
```

Or step by step:

```bat
flutter build windows --release
powershell -File scripts\bundle_windows_engines.ps1 -BundleDir build\windows\x64\runner\Release
powershell -File scripts\windows\package_portable.ps1
ISCC.exe scripts\windows\document_studio.iss
```

Outputs: `dist/windows/DocumentStudio-<ver>-Setup.exe`, `DocumentStudio-<ver>-portable-windows.zip`.

### Exact download URLs (cached in `.tools\windows\`)

| Artifact | URL |
| --- | --- |
| qpdf | `https://github.com/qpdf/qpdf/releases/download/v12.4.2/qpdf-12.4.2-mingw64.zip` (`DS_QPDF_VERSION`) |
| tesseract setup | `https://github.com/tesseract-ocr/tesseract/releases/download/5.5.3/tesseract-ocr-w64-setup-5.5.3.20260724.exe` (`DS_TESSERACT_SETUP_URL`) |
| tessdata eng/osd | `https://github.com/tesseract-ocr/tessdata_fast/raw/main/{eng,osd}.traineddata` |
| poppler | `https://github.com/oschwartz10612/poppler-windows/releases/download/v24.08.0-0/Release-24.08.0-0.zip` (`DS_POPPLER_VERSION`) |
| ffmpeg | `https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip` |
| OpenSSL Light | `https://slproweb.com/download/Win64OpenSSL_Light-4_0_2.exe` (`DS_OPENSSL_URL`) |
| zstd (extract helper) | `https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-v1.5.7-win64.zip` |
| NSS / NSPR / sqlite / zlib | MSYS2 mingw64 `.pkg.tar.zst` under `https://repo.msys2.org/mingw/mingw64/` (pinned filenames in script) |
| LibreOffice MSI | `https://download.documentfoundation.org/libreoffice/stable/26.2.6/win/x86_64/LibreOffice_26.2.6_Win_x86-64.msi` (`DS_LIBREOFFICE_VERSION` / `DS_LIBREOFFICE_MSI_URL`) |

Optional overrides: `DS_TESSERACT_ROOT`, `DS_LIBREOFFICE_ROOT`, `DS_SKIP_LIBREOFFICE=1`.

Windows still keeps an in-app LibreOffice downloader as a **fallback** when an older installer was built without LO; new packages ship it inside `engines/`.

## macOS build machine

**One command:**

```bash
bash scripts/macos/package_release.sh
```

Or step by step:

```bash
flutter build macos --release   # host arch only
bash scripts/bundle_macos_engines.sh
bash scripts/macos_dmg.sh
codesign --force --deep --sign - dist/macos/.../document_studio.app   # ad-hoc (package_release already does this)
```

Outputs: `dist/macos/DocumentStudio-<ver>-macos.dmg`, `DocumentStudio-<ver>-macos.zip`.

Homebrew formulas (non-interactive): `qpdf`, `tesseract`, `poppler`, `nss`, `openssl`, `ffmpeg`.

LibreOffice: official DMG for host arch → copied to `engines/LibreOffice.app`
(`DS_LIBREOFFICE_VERSION`, default `26.2.6`; `DS_LIBREOFFICE_DMG_URL` to override).

**Universal vs arm64:** script copies **host arch** binaries. For universal, build on each arch (or Rosetta brew) and `lipo` the engine binaries, then re-sign. Without Apple Developer Program, skip notarization; users right-click → Open once.

## Android

No desktop CLI download after install (Play policy). Features that need qpdf/tesseract/soffice show an in-app “desktop-only / not available” message. Page assembly uses **pdfrx**. Do not add a post-install native binary downloader on Android.
