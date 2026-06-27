# Third-party notices — Document Studio

Document Studio's own application code is proprietary
(`LicenseRef-proprietary`; see `LICENSE`). That grant does **not** relicense
bundled or linked engines and libraries.

## Where to find license details

| Topic | Location |
| --- | --- |
| Engine and dependency license table | [docs/LICENSES.md](docs/LICENSES.md) |
| Dependency inventory | [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) (if present) |
| Liberation fonts | [assets/fonts/text/LICENSE-Liberation.txt](assets/fonts/text/LICENSE-Liberation.txt) |

## Engines commonly shipped with desktop builds

These components remain under **their** licenses when bundled or invoked:

- **Flutter / Dart SDK** — BSD-style licenses from Google / Dart project
- **PDFium** (via pdfrx / pdfium) — PDFium and its embedded library notices
- **qpdf** — Apache-2.0
- **Tesseract** / Leptonica — Apache-2.0 / BSD-2-Clause as applicable; optional
  tessdata language files under their upstream terms
- **LibreOffice** (desktop conversion, when packaged) — MPL-2.0 and related
  LibreOffice notices

Ship the notices that accompany each binary release (for example PDFium
`licenses/` folders and Apache NOTICE files) with the corresponding artifact.
Do not treat Document Studio's proprietary `LICENSE` as covering those works.
