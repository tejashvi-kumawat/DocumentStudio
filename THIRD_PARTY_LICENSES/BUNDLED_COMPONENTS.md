# Bundled third-party components (version pins)

Pins below match **default** values in `scripts/bundle_windows_engines.ps1`,
`scripts/bundle_linux_engines.sh`, and `scripts/bundle_macos_engines.sh` unless
overridden by environment variables at build time. Installed apps also ship
`engines/THIRD_PARTY_LICENSES/bundled-versions.json` generated at bundle time.

**Distribution modes**

- **Bundled executable** — copied into `engines/bin/` (or `engines/libreoffice/`) and run via wrapper `.cmd`/shell script; **not linked** into `document_studio.exe`.
- **Flutter linked** — native code inside the Flutter app binary (PDFium via pdfrx).
- **External process** — same as bundled executable; app spawns CLI with arguments.

| Component | Default version (platform) | License (summary) | How distributed | Required notices | Source obligations |
| --- | --- | --- | --- | --- | --- |
| **QPDF** | Win **12.4.2** mingw zip; Linux **12.2.0** bin zip; macOS via Homebrew/portable | **Apache-2.0** | Bundled executable + DLLs | `Apache-2.0.txt`, `components/qpdf-NOTICE.txt` | None for unmodified binary; source at https://github.com/qpdf/qpdf |
| **Tesseract OCR** | Win **5.5.3** (UB Mannheim `5.5.3.20260724`); Linux **5.3.4-1build5** debs; macOS brew | **Apache-2.0** | Bundled executable + libs | `Apache-2.0.txt`, `components/tesseract-NOTICE.txt` | tessdata: https://github.com/tesseract-ocr/tessdata (Apache-2.0) |
| **Leptonica** (with Tesseract) | Transitive from Tesseract build | **BSD-2-Clause** | Shared libs next to Tesseract | `BSD-2-Clause.txt` | Upstream bundled with Tesseract |
| **Poppler** (`pdfsig`) | Win **24.08.0-0** [poppler-windows](https://github.com/oschwartz10612/poppler-windows) (optional); Linux **poppler-utils 24.02.0-1ubuntu9** | **GPL-2.0-or-later** (Poppler) | Bundled executable when present | `GPL-2.0-or-later.txt`, `components/poppler-NOTICE.txt` | **Corresponding source** — see [docs/CORRESPONDING_SOURCE.md](../docs/CORRESPONDING_SOURCE.md) |
| **OpenSSL** (`openssl.exe`) | Win: **Win64 OpenSSL Light 4.0.2** or Git `usr/bin/openssl.exe`; Linux: system/`apt` copy | **Apache-2.0** (OpenSSL 3.x) | Bundled executable + DLLs | `Apache-2.0.txt`, `components/openssl-NOTICE.txt` | https://github.com/openssl/openssl |
| **NSS** (`certutil`, `pk12util`) | MSYS2 **nss 3.129**, **nspr 4.40** (Win); Linux **libnss3-tools** debs | **MPL-2.0** | Bundled executable + DLLs/so | `MPL-2.0.txt`, `components/nss-NOTICE.txt` | https://firefox-source-docs.mozilla.org/security/nss/ |
| **FFmpeg** | Win: **gyan.dev ffmpeg-release-essentials** zip; Linux: Ubuntu **ffmpeg** debs | **Uncertain** — often **GPL-3.0** or **LGPL** depending on build; **not verified in-repo** | Bundled executable + DLLs | `components/FFMPEG-NOTICE.md` | See CORRESPONDING_SOURCE; confirm with `ffmpeg -version` |
| **LibreOffice** (`soffice`) | **26.8.1** official MSI/DMG/Linux tarball | **MPL-2.0** + many third-party licenses | Bundled tree under `engines/libreoffice/` | `MPL-2.0.txt`, `components/libreoffice-NOTICE.txt`, upstream files in `libreoffice-upstream/` when copied | https://www.libreoffice.org/about-us/licenses/ |
| **PDFium** (pdfrx) | Transitive from **pdfrx** / **pdfium_flutter** pub version | **BSD-3-Clause** / Apache-2.0 (composite) | **Dynamically linked** into Flutter app | PDFium `NOTICES` / `licenses/` from engine package | PDFium source via Chromium/PDFium project |
| **Flutter / Dart** | SDK pinned by project | **BSD-3-Clause** (Flutter) | Linked / runtime | Flutter license files in SDK | flutter.dev |

## Environment overrides

Build scripts honor variables such as `DS_QPDF_VERSION`, `DS_POPPLER_VERSION`,
`DS_LIBREOFFICE_VERSION`, `DS_FFMPEG_URL`, `DS_NSS_PKG`, etc. Release
`bundled-versions.json` records the effective pins for that artifact.

## Compliance gaps to review before store submission

- Confirm **FFmpeg** license line from the **exact** binary shipped (`ffmpeg -version`).
- Confirm **Poppler** is absent vs present per platform build; if present, GPL notices and source offer must remain in the installer.
- **Microsoft Store / Play** have additional policy and attribution requirements beyond this folder.
- **Code signing** does not replace license compliance.
