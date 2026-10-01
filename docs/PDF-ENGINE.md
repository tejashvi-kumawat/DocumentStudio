# PDF Engine — Document Studio

## Policy

Do not implement PDF parsing in Dart. Use **PDFium** + **qpdf** behind ports (ADR-002, ADR-003).

## Port responsibilities

### PdfRenderPort (PDFium / pdfrx_engine)

| Operation | API direction |
| --- | --- |
| Open / close | `PdfDocument.openFile/openData` |
| Page count, metadata | document properties |
| Render bitmap | `PdfPage.render` @ scale/DPI |
| Text extract / search | `loadText`, search APIs |
| Thumbnails | render low-DPI |
| Create empty PDF | `createNew`, add pages |
| Images → PDF pages | `createFromJpegData`, page import |
| Light object insert | PDFium edit APIs (Phase 5+) |

### PdfStructurePort (qpdf)

| Operation | Notes |
| --- | --- |
| Merge / split / rotate pages | `--pages` semantics |
| Encrypt / decrypt | user password required |
| Linearize | optional |
| Recompress flate | compress tool |
| Remove unused objects | optimization |
| Repair xref | best-effort; not magic recovery |
| Attachments / outlines | Phase 10; qpdf C++ helpers |

## Operation routing table

| User feature | Primary | Fallback |
| --- | --- | --- |
| View PDF | PDFium | — |
| Merge PDF | pdfrx pages + assemble OR qpdf | qpdf if encrypt/complex |
| Split PDF | qpdf | pdfrx if simple |
| Compress (lossless) | qpdf | — |
| Compress (lossy images) | PDFium render + reencode | — |
| Encrypt | qpdf | — |
| Fill forms | PDFium | platform-tested |
| Redaction | qpdf + content rewrite | — |
| OCR searchable | Tesseract + PDFium/qpdf sandwich | — |

## Job cancellation (DS-EDGE-002)

Long organize/compress/batch paths run through [JobRunner](../lib/core/jobs/job_runner.dart). UI sets `JobHandle` on export/merge/split and calls `requestCancel`; the runner sets `JobCancelToken.isCancelled` and throws `PROCESS_CANCELLED` when the job finishes or when cooperative checks fail early (e.g. `PageOrganizeService.exportWorkspace` before qpdf/pdfrx assemble). Save dialogs are not shown after cancel. Isolate-backed jobs and every open path are not yet covered — see [.ai/CHECKLIST.md](../.ai/CHECKLIST.md) `DS-EDGE-002`.

## Password handling

- Prompt in application layer; pass `String` to engines only for duration of call.
- Clear sensitive buffers after use where API allows.
- Support empty user password attempt first (PDF spec).

## Save strategies

| Mode | When |
| --- | --- |
| Full rewrite | qpdf output, most tools |
| Incremental | only if engine supports and preserves signatures (investigate Phase 10) |

Default export: **new file** in user-chosen directory.

## Darwin optional path

`pdfrx_coregraphics` may replace PDFium on iOS/macOS for size. If enabled:

- Run render golden tests on same corpus
- Document in ADR supplement

## Licensing shipped in app

Include PDFium `licenses/` bundle and qpdf Apache notice in **Settings → Legal**.

## Known engine limits (product honesty)

- **True edit** of existing text: limited by font subsetting; often redact+overlay.
- **Annotation write:** pdfrx immature; plan custom PDFium annot FFI (see GitHub pdfrx #545).
- **XFA** forms: poor support; warn user.
- **JavaScript** in PDF: do not execute.

## Version pinning

Record PDFium build (e.g. chromium rev from pdfium_flutter) and qpdf x.y.z in [DEPENDENCIES.md](DEPENDENCIES.md) at Phase 0.
