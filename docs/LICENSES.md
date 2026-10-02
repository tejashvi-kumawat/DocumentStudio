# Licenses — Document Studio

Document Studio **application code** is **proprietary** (`LicenseRef-proprietary`, All Rights Reserved). See [LICENSE](../LICENSE), [TERMS.md](../TERMS.md), [PRIVACY.md](../PRIVACY.md).

**Third-party** software keeps its **own** licenses. Full texts and notices:
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) → [THIRD_PARTY_LICENSES/](../THIRD_PARTY_LICENSES/).

Bundled engines are **not** relicensed by Document Studio's `LICENSE`.

---

## Bundled desktop engines (version pins)

See **[THIRD_PARTY_LICENSES/BUNDLED_COMPONENTS.md](../THIRD_PARTY_LICENSES/BUNDLED_COMPONENTS.md)** for default versions, distribution mode, and obligations. Build-time pins are also written to `engines/THIRD_PARTY_LICENSES/bundled-versions.json` in shipped artifacts.

| Component | Default license | Distribution |
| --- | --- | --- |
| QPDF | Apache-2.0 | Bundled CLI + libs |
| Tesseract (+ tessdata) | Apache-2.0 | Bundled CLI + data |
| Leptonica | BSD-2-Clause | With Tesseract |
| Poppler (`pdfsig`) | GPL-2.0-or-later | Bundled CLI when present |
| OpenSSL | Apache-2.0 | Bundled CLI |
| NSS tools | MPL-2.0 | Bundled CLI + libs |
| FFmpeg | **Verify per binary** | Bundled CLI |
| LibreOffice | MPL-2.0 (+ upstream set) | Bundled tree, external process |

Copyleft / **corresponding source:** [CORRESPONDING_SOURCE.md](CORRESPONDING_SOURCE.md).

---

## Flutter application dependencies (pub.dev)

| Component | License | Notes |
| --- | --- | --- |
| Flutter SDK | BSD-3-Clause | Google |
| pdfrx / pdfrx_engine / pdfium_flutter | MIT + PDFium NOTICES | PDF rendering |
| PDFium (native) | BSD-3-Clause / Apache-2.0 (composite) | Linked native library |
| document_studio_qpdf | Project license + qpdf Apache-2.0 | FFI/CLI to qpdf |
| document_studio_ocr | Project license + Tesseract Apache-2.0 | OCR |
| printing | Apache-2.0 | |
| flutter_tesseract_ocr | Upstream license | Mobile OCR binding |
| Other pub deps | Mostly MIT/BSD/Apache | See `pubspec.lock` |

Before adding dependencies, update [DEPENDENCIES.md](DEPENDENCIES.md) and this file when the license is outside MIT/BSD/Apache/MPL-2.0 (with review).

---

## Previously excluded from **linked** app binary

These are **not** linked into the Flutter binary. **Poppler** may still appear as a **bundled GPL CLI** (`pdfsig`) — that triggers **distribution** obligations for that binary, not “linking exclusion.”

| Component | Reason |
| --- | --- |
| MuPDF | AGPL |
| Ghostscript | AGPL |
| GPL `pdf_signer` | GPL linked tooling rejected |

---

## Release compliance checklist

- [ ] `engines/THIRD_PARTY_LICENSES/` present in Windows/Linux/macOS release trees  
- [ ] `bundled-versions.json` matches build pins  
- [ ] FFmpeg license line captured from shipped `ffmpeg -version` (if FFmpeg bundled)  
- [ ] Poppler/GPL source offer documented if `pdfsig` shipped  
- [ ] LibreOffice upstream license files in `libreoffice-upstream/` when LO bundled (Windows script)  
- [ ] PDFium / Flutter notices included per store requirements  
- [ ] In-app or installer “Legal / Third-party licenses” surfaces text for store policies (recommended; verify per store)

This checklist does **not** guarantee compliance with every jurisdiction or store policy; it reflects reasonable open-source distribution practice.

---

## Agent rule

Before adding any dependency or bundled binary, append a row to [DEPENDENCIES.md](DEPENDENCIES.md) and update [THIRD_PARTY_LICENSES/BUNDLED_COMPONENTS.md](../THIRD_PARTY_LICENSES/BUNDLED_COMPONENTS.md) when the component is redistributed.
