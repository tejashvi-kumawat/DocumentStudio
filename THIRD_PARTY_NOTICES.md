# Third-party notices — Document Studio

Document Studio's own application code is proprietary
(`LicenseRef-proprietary`; see [LICENSE](LICENSE)). That grant does **not** relicense
bundled or linked third-party software.

## Shipped with desktop installers

Release builds copy this repository's **[THIRD_PARTY_LICENSES/](THIRD_PARTY_LICENSES/)**
tree into the installed application at:

```text
engines/THIRD_PARTY_LICENSES/
```

That folder includes **full license texts** (Apache-2.0, GPL-2.0, MPL-2.0, BSD, etc.),
per-component NOTICE files, and **`bundled-versions.json`** (exact version pins for that build).

| Reference | Content |
| --- | --- |
| Component table | [THIRD_PARTY_LICENSES/BUNDLED_COMPONENTS.md](THIRD_PARTY_LICENSES/BUNDLED_COMPONENTS.md) |
| Copyleft / source offers | [docs/CORRESPONDING_SOURCE.md](docs/CORRESPONDING_SOURCE.md) |
| Dependency inventory | [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) |
| Summary table | [docs/LICENSES.md](docs/LICENSES.md) |

## Bundled CLI engines (external processes)

When present under `engines/`, these run as **separate executables** (not linked into
`document_studio.exe` / the Flutter binary):

- **QPDF** — Apache-2.0  
- **Tesseract OCR** (+ Leptonica, tessdata) — Apache-2.0 / BSD-2-Clause  
- **Poppler** (`pdfsig`) — GPL-2.0-or-later when bundled  
- **OpenSSL** — Apache-2.0 (OpenSSL 3.x)  
- **NSS** (`certutil`, `pk12util`) — MPL-2.0  
- **FFmpeg** — license depends on upstream build (**verify** — see `components/FFMPEG-NOTICE.md`)  
- **LibreOffice** — MPL-2.0 and upstream collective licenses  

## Linked in the application binary

- **PDFium** (via pdfrx / pdfium_flutter) — BSD / Apache composite notices from the engine package  
- **Flutter / Dart SDK** — BSD-style licenses  

## Fonts

- **Liberation** — [assets/fonts/text/LICENSE-Liberation.txt](assets/fonts/text/LICENSE-Liberation.txt)

Preserve all upstream copyright and license notices when redistributing installers or
store packages. Do not replace third-party licenses with Document Studio's proprietary license.
