# Dependencies — Document Studio

**Status:** Active — matches `pubspec.yaml` as of Phase 0 implementation start (2026-09-26).

Record template:

| Field | Value |
| --- | --- |
| Name | |
| Version | Pin at add time |
| Purpose | |
| License | |
| Repository | |
| Platforms | |
| Integration | pub / FFI / subprocess |
| Security notes | |
| Alternatives considered | |
| Selection rationale | |

---

## In pubspec (implemented / integrated)

| Name | Version (pubspec) | Purpose | License | ADR |
| --- | --- | --- | --- | --- |
| pdfrx | ^2.6.5 | PDF viewer widget + PDFium | MIT + PDFium NOTICES | ADR-002 |
| pdfrx_engine / pdfium_flutter | transitive | Native PDFium | MIT + NOTICES | ADR-002 |
| flutter_riverpod | ^3.4.3 | State / DI | MIT | ADR-006 pending |
| go_router | ^18.0.1 | Routing | BSD-3 | — |
| file_picker | ^13.1.0 | Open/save (v13 bytes-based save) | MIT | — |
| path_provider | ^2.1.6 | App directories | BSD-3 | — |
| shared_preferences | ^2.5.5 | Recents, settings | BSD-3 | — |
| equatable | ^3.0.0 | Value types | MIT | — |
| uuid | ^4.6.0 | Job IDs | MIT | — |
| logging | ^1.3.0 | App logging (no document content) | BSD-3 | — |
| image | ^4.10.1 | Decode, resize, PNG/JPEG encode | MIT | — |
| printing | ^5.15.1 | OS print dialog for PDF bytes | Apache-2.0 | — |
| document_studio_qpdf | path `packages/` | qpdf CLI bridge (FFI TBD) | Apache-2.0 (qpdf) | ADR-003 |
| document_studio_ocr | path `packages/` | OCR/searchable-PDF ports (stubs `[B]`) | Apache-2.0 (Tesseract when linked) | ADR-004 |

## Planned (not yet in pubspec)

| Name | Purpose | License | Integration | ADR |
| --- | --- | --- | --- | --- |
| qpdf (FFI) | Full structure engine in-process | Apache-2.0 | Custom FFI plugin | ADR-003 |
| Tesseract (native) | OCR runtime + tessdata | Apache-2.0 | Plugin / FFI | ADR-004 |
| share_plus | OS share sheet | BSD-3 | pub | — |

## Explicitly excluded (default)

| Name | Reason |
| --- | --- |
| syncfusion_flutter_pdf* | Commercial / Community license limits | ADR-008 |
| MuPDF (AGPL) | Copyleft unless commercial license | ADR-009 |
| Ghostscript | AGPL | ADR-009 |
| google_mlkit_* (required core) | Mobile-only; not sole OCR | ADR-004 |
| pdf_signer | GPL-3.0 | ADR-010 |

## External processes (desktop)

| Name | Purpose | License | Integration |
| --- | --- | --- | --- |
| LibreOffice (`soffice`) | Office → PDF | MPL-2.0 | subprocess | ADR-005 |
| veraPDF (optional) | PDF/A validation | MPL-2.0 / GPL-3+ dual | subprocess | Phase 10 |

---

## Changelog

| Date | Change |
| --- | --- |
| 2026-09-26 | Initial planned stack; no pubspec yet |
| 2026-09-26 | Added `image` for Image Engine (Agent 9) |
| 2026-09-26 | Added `image` for Image Engine (Agent 9) |
| 2026-09-26 | Added `printing` ^5.15.1 for DS-READ-014 / DS-PRT-001 |
