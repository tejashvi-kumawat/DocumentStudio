# Licenses — Document Studio

Document Studio application code: **proprietary** (`LicenseRef-proprietary`, All Rights Reserved). See:

| Document | Path |
| --- | --- |
| End-user / distribution license | [LICENSE](../LICENSE) |
| Privacy policy | [PRIVACY.md](../PRIVACY.md) |
| Terms and Conditions | [TERMS.md](../TERMS.md) |
| Third-party notices pointer | [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) |

This document tracks **third-party** obligations for the recommended engine stack. Bundled engines are **not** relicensed by Document Studio's proprietary `LICENSE`.

## Application dependencies (planned)

| Component | License | Attribution |
| --- | --- | --- |
| Flutter SDK | BSD-3 | Google |
| pdfrx / pdfrx_engine / pdfium_flutter | MIT | Plugin author + PDFium NOTICES |
| PDFium (binary) | BSD-3-Clause / Apache-2.0 (composite) | Ship `licenses/` from pdfium bundle |
| qpdf | Apache-2.0 | NOTICE in app legal screen |
| Tesseract | Apache-2.0 | Include NOTICE |
| Leptonica (via Tesseract) | BSD-2-clause | Bundled with Tesseract |
| `image` | MIT | |
| `file_picker` | MIT | |
| `printing` | Apache-2.0 | |
| tessdata language files | Apache-2.0 (tessdata repo) | Per-language if required |

## PDFium bundled libraries (typical)

Abseil, FreeType, ICU, libjpeg-turbo, libpng, libtiff, OpenJPEG, zlib, etc.—full list in PDFium release `licenses/` folder. **Must ship** in app “Third-party licenses” UI.

## External processes (desktop)

| Component | License | Notes |
| --- | --- | --- |
| LibreOffice | MPL-2.0 | Separate install; not linked; document in FAQ |
| veraPDF (optional) | MPL-2.0 / GPL-3+ dual | CLI validator only |

## Explicitly excluded (copyleft in app binary)

MuPDF (AGPL), Ghostscript (AGPL), Poppler (GPL), GPL `pdf_signer`.

## Syncfusion

Not used in core product (ADR-008).

## Compliance checklist (release)

- [ ] `ThirdPartyLicenses` screen or dialog scrollable text
- [ ] PDFium licenses directory copied to resources
- [ ] qpdf Apache 2.0 NOTICE
- [ ] Tesseract Apache 2.0
- [ ] tessdata attribution if required by pack used
- [ ] No GPL/AGPL linked native libs in release artifact (verify with `ldd`/APK analyzer)

## Agent rule

Before adding any dependency, append row to [DEPENDENCIES.md](DEPENDENCIES.md) and update this file if license is not MIT/BSD/Apache.
