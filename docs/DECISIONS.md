# Architecture Decision Records

Index of decisions for Document Studio. **Do not change Accepted ADRs** without a new ADR that supersedes them.

Format: Context → Decision → Alternatives → Consequences → Status

---

## ADR-001 — Flutter as primary application framework

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Accepted** |

### Context

The product must ship on Android, iOS/iPadOS, Windows, macOS, and Linux with one maintainable codebase. Desktop and mobile are co-primary. The product must not be a web-first wrapper.

### Decision

Use **Flutter (Dart)** for UI, application orchestration, and domain logic. Use federated plugins, FFI, and platform channels for native engines.

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| Tauri + React + Rust | Valid for desktop-only; rejected as primary per product direction |
| .NET MAUI | Smaller cross-platform PDF ecosystem in one stack |
| Native apps per platform | Unmaintainable for breadth of tools |

### Consequences

- Strong shared UI; native build complexity lives in plugins.
- FFI/plugin CI required per platform ABI.
- Web target is not the product SKU (pdfrx web exists but out of scope).

---

## ADR-002 — PDF rendering and viewer via PDFium (pdfrx ecosystem)

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Accepted** — integrated in app (2026-09-26) |

### Context

Need cross-platform PDF viewing, text extraction, search, thumbnails, and light document creation/page assembly on all primary targets.

### Decision

Adopt **PDFium** packaged for Flutter via **pdfrx / pdfrx_engine / pdfium_flutter** (MIT plugin; PDFium with bundled third-party NOTICES). Implemented via `PdfrxRenderAdapter` and `PdfViewer` in `lib/infrastructure/pdf/` and `lib/features/pdf_viewer/`.

Optional later: **pdfrx_coregraphics** on iOS/macOS only to reduce binary size, with parity tests.

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| Syncfusion Flutter PDF | Commercial / Community license limits; not aligned with unconditional free product |
| MuPDF | AGPL unless commercial license from Artifex |
| Poppler/Ghostscript | GPL/AGPL linkage concerns |
| Platform-only (PDFKit everywhere) | Breaks parity on Android/Windows/Linux |

### Consequences

- Must ship and maintain PDFium binaries per ABI (pdfium_flutter native assets / XCFramework).
- Annotation **authoring** and deep edit APIs are incomplete in pdfrx today; plan complementary work (ADR-002 supplement or custom FFI).
- License compliance: include PDFium and dependency license texts in app legal screen.

---

## ADR-003 — PDF structure, security, and repair via qpdf

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** — confirm before Phase 0 engine work |

### Context

Merge, split, encrypt, decrypt, stream recompression, xref repair, and many “iLovePDF-style” operations need a mature structural PDF library. PDFium is not a full structural editor.

### Decision

Implement **`PdfStructurePort`** with **qpdf** (Apache-2.0) via a dedicated Flutter FFI plugin (static or dynamic per platform).

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| lopdf only | Rust; Flutter integration path heavier; encryption/object-stream edge cases |
| PDFium only | Insufficient for many structural transforms |
| Apache PDFBox | JVM embedding undesirable |

### Consequences

- Custom plugin build for Android ABIs, iOS, Windows, macOS, Linux (qpdf supports mobile static builds with CI).
- Two-engine coordination: define which operations call PDFium vs qpdf in `PDF-ENGINE.md` when written.
- qpdf does not render or OCR; stays structural.

---

## ADR-004 — OCR via Tesseract

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** — confirm before Phase 6 |

### Context

Offline OCR for images and scanned PDFs; searchable PDF output; 100+ languages; no cloud OCR.

### Decision

**Tesseract 5** (`libtesseract`, Apache-2.0) as the **canonical** OCR engine behind `OcrPort` on all platforms.

Mobile may use existing Flutter plugins (e.g. tesseract_ocr) as adapters initially; desktop via FFI or controlled subprocess.

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| Google ML Kit only | Android/iOS only; Play Services/bundling concerns on Android |
| Apple Vision only | iOS/macOS only; inconsistent searchable PDF pipeline |
| Cloud OCR APIs | Violates NC-04 / NC-10 |

### Consequences

- Large language packs; bundle minimal set (e.g. eng); optional user-initiated downloads.
- Searchable PDF requires custom merge of image layer + Tesseract PDF text layer.
- OCR jobs are long-running; foreground UX on mobile.

---

## ADR-005 — Office conversion via LibreOffice headless (desktop only, v1)

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** — confirm D-06 delivery model |

### Context

DOC/DOCX/XLS/XLSX/PPT/PPTX → PDF with reasonable fidelity locally without cloud APIs.

### Decision

On **Windows, macOS, Linux only**, run **LibreOffice** headless:

`soffice --headless --convert-to pdf --outdir <dir> <file>`

Use isolated user profile per job; timeouts; no network.

**Mobile v1:** Office conversion tools **not offered** (hide via tool registry); import/export via PDF/images only unless a future ADR adds a mobile strategy.

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| Bundled LO in installer | Huge size; signing/update burden |
| Cloud convert APIs | Forbidden for core |
| Perfect PDF→Office | Not technically honest; extraction-only with warnings |

### Consequences

- MPL-2.0: document LibreOffice separation; app remains proprietary-friendly if LO is external process.
- User must install LO or app guides install (D-06 pending).
- Font/layout caveats required in UI.

---

## ADR-006 — State management (pending)

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Pending** |

### Context

Need testable async job state, document session state, and DI without global PDF handles.

### Decision (recommended)

**Riverpod** (or equivalent explicit provider DI). Final choice at Phase 0 start.

### Alternatives

Bloc, GetIt + ChangeNotifier, Elementary — acceptable if ADR updated.

---

## ADR-007 — Android document scanning without ML Kit Document Scanner dependency

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** |

### Context

Scan-to-PDF on Android must work offline and without requiring Google Play Services for core parity with strict privacy positioning.

### Decision

**iOS:** VisionKit `VNDocumentCameraViewController` via platform channel.

**Android:** CameraX + document detection (OpenCV-based module or maintained OSS SDK), not ML Kit Document Scanner as the only path.

### Alternatives

ML Kit bundled text recognition optional (ADR-004 optional accelerator), not required for scan geometry.

### Consequences

More custom native code on Android; test across OEM cameras.

---

## ADR-008 — Exclude Syncfusion as core PDF dependency

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** |

### Context

Syncfusion Flutter PDF is feature-rich but license is commercial or Community with revenue/employee caps.

### Decision

Do **not** depend on Syncfusion for core viewer/editor/manipulation. PDFium + qpdf stack instead.

### Consequences

More in-house glue for annotations/editing; no license compliance cliff as company grows.

---

## ADR-009 — Exclude AGPL/GPL PDF stacks from default shipping binary

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** |

### Context

MuPDF, Ghostscript, Poppler, FairScan-style stacks often use AGPL/GPL.

### Decision

Default engine set excludes **AGPL/GPL-linked** native libraries. Ghostscript not used for PDF/A or compression in core product.

### Consequences

PDF/A and some repair/compress scenarios are harder; use Apache/MIT tools (qpdf, veraPDF as external validator, etc.).

---

## ADR-010 — Visual vs cryptographic signatures

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Proposed** |

### Context

Users expect “sign PDF”; legally distinct visual stamp vs PAdES/PKCS#7.

### Decision

**Phase 8:** Visual signatures only (draw/type/image, flatten).

**Phase 10+:** Investigate cryptographic signing with **MIT/Apache** libraries only; reject GPL `pdf_signer` in default build. PAdES levels requiring TSA are optional and network-disclosed.

### Consequences

Product must label features clearly in UI and docs.

---

## ADR-011 — Authoritative feature inventory document

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Accepted** |

### Context

Product scope must be exhaustive before implementation. Multiple documents (master spec §6, feature cluster specs, checklist) risk drift.

### Decision

**[FEATURE-INVENTORY.md](FEATURE-INVENTORY.md)** is the authoritative row-level feature list (ID, priority, phase, status, engines, limitations). **[.ai/CHECKLIST.md](../.ai/CHECKLIST.md)** mirrors inventory IDs for implementation tracking. Master spec §6 remains a **summary index** only. Platform support claims require **[FEATURE-MATRIX.md](FEATURE-MATRIX.md)**; competitor mapping requires **[FEATURE-PARITY.md](FEATURE-PARITY.md)**.

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| Master spec §6 tables only | Too large to maintain; already duplicated |
| Issue tracker as SoT | Not in repo; offline agents need files |

### Consequences

Any new feature requires an inventory row before implementation. Splitting IDs uses `-A`, `-B` suffixes; do not reuse IDs.

---

## ADR-012 — Page structure operations via pdfrx assemble (interim)

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Accepted** (interim until qpdf FFI) |

### Context

qpdf FFI plugin is not yet built. Users need merge/split/reorder on all platforms now.

### Decision

Implement **`PdfrxStructureAdapter`** using `PdfDocument.pages`, `assemble()`, and `encodePdf()` for unencrypted PDFs. Ship **`packages/document_studio_qpdf`** for optional **qpdf CLI** when installed (encrypted merge/rotate). **`CompositePdfStructureAdapter`** routes between them.

### Consequences

- Encrypted PDF structure ops require qpdf CLI on PATH or wait for FFI.
- Large jobs must run via `JobRunner` / organize service with save-as (never overwrite originals).

---

## ADR-011 — Authoritative feature inventory document

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Accepted** |

### Context

Product scope must be exhaustive before implementation. Multiple documents (master spec §6, feature cluster specs, checklist) risk drift.

### Decision

**[FEATURE-INVENTORY.md](FEATURE-INVENTORY.md)** is the authoritative row-level feature list (ID, priority, phase, status, engines, limitations). **[.ai/CHECKLIST.md](../.ai/CHECKLIST.md)** mirrors inventory IDs for implementation tracking. Master spec §6 remains a **summary index** only. Platform support claims require **[FEATURE-MATRIX.md](FEATURE-MATRIX.md)**; competitor mapping requires **[FEATURE-PARITY.md](FEATURE-PARITY.md)**.

### Alternatives considered

| Alternative | Why not default |
| --- | --- |
| Master spec §6 tables only | Too large to maintain; already duplicated |
| Issue tracker as SoT | Not in repo; offline agents need files |

### Consequences

Any new feature requires an inventory row before implementation. Splitting IDs uses `-A`, `-B` suffixes; do not reuse IDs.

---

## ADR-012 — Page structure operations via pdfrx assemble (interim)

| Field | Value |
| --- | --- |
| **Date** | 2026-09-26 |
| **Status** | **Accepted** (interim until qpdf FFI) |

### Context

qpdf FFI plugin is not yet built. Users need merge/split/reorder on all platforms now.

### Decision

Implement **`PdfrxStructureAdapter`** using `PdfDocument.pages`, `assemble()`, and `encodePdf()` for unencrypted PDFs. Ship **`packages/document_studio_qpdf`** for optional **qpdf CLI** when installed (encrypted merge/rotate). **`CompositePdfStructureAdapter`** routes between them.

### Consequences

- Encrypted PDF structure ops require qpdf CLI on PATH or wait for FFI.
- Large jobs must run via `JobRunner` / organize service with save-as (never overwrite originals).

---

## Superseded

None.
