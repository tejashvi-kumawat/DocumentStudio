# Document Studio — Master Project Specification

| Field | Value |
| --- | --- |
| **Document** | Master Project Specification |
| **Product** | Document Studio |
| **Version** | 1.0.0 |
| **Status** | Specification only — no implementation authorized by this document alone |
| **Last updated** | 2026-09-26 |
| **Primary framework** | Flutter (Dart) |
| **Audience** | Product owners, architects, and AI coding agents |

---

## How to use this document

1. Read sections 1–6 before making any product or architecture decision.
2. Treat **Non-negotiable principles** (section 4) as hard constraints unless the project owner explicitly changes them in writing.
3. Treat **Recommended architecture** (sections 10–21) as the default plan; deviations require an Architecture Decision Record (ADR).
4. Treat **Decisions requiring confirmation** (section 30) as blocking for Phase 0 completion and for irreversible dependency choices.
5. Do not implement features marked **Deferred** or **Investigation required** without updating this document.

---

## Table of contents

1. [Executive summary](#1-executive-summary)
2. [Product vision](#2-product-vision)
3. [Product principles](#3-product-principles)
4. [Non-negotiable constraints](#4-non-negotiable-constraints)
5. [Scope and non-goals](#5-scope-and-non-goals)
6. [Complete feature inventory](#6-complete-feature-inventory)
7. [Functional requirements](#7-functional-requirements)
8. [Non-functional requirements](#8-non-functional-requirements)
9. [Target platforms and platform matrix](#9-target-platforms-and-platform-matrix)
10. [Architecture proposal](#10-architecture-proposal)
11. [Flutter application architecture](#11-flutter-application-architecture)
12. [Technology evaluation and recommendations](#12-technology-evaluation-and-recommendations)
13. [Dependency and license strategy](#13-dependency-and-license-strategy)
14. [PDF engine strategy](#14-pdf-engine-strategy)
15. [Conversion strategy](#15-conversion-strategy)
16. [OCR strategy](#16-ocr-strategy)
17. [Editor and annotation architecture](#17-editor-and-annotation-architecture)
18. [UI/UX architecture](#18-uiux-architecture)
19. [Design system requirements](#19-design-system-requirements)
20. [Security architecture](#20-security-architecture)
21. [Privacy architecture](#21-privacy-architecture)
22. [File-processing architecture](#22-file-processing-architecture)
23. [Performance requirements](#23-performance-requirements)
24. [Error handling](#24-error-handling)
25. [Testing strategy](#25-testing-strategy)
26. [Cross-platform strategy](#26-cross-platform-strategy)
27. [AI development rules](#27-ai-development-rules)
28. [Documentation strategy](#28-documentation-strategy)
29. [Roadmap](#29-roadmap)
30. [Risks, unknowns, and decisions requiring confirmation](#30-risks-unknowns-and-decisions-requiring-confirmation)
31. [Architecture Decision Records (initial set)](#31-architecture-decision-records-initial-set)
32. [Feature specification template](#32-feature-specification-template)
33. [Glossary](#33-glossary)

---

## 1. Executive summary

**Document Studio** is a free, ad-free, privacy-first, offline-first **Flutter** application for phones, tablets, and desktops. It aims to unify the workflows users today spread across tools like Adobe Acrobat, iLovePDF, PDF24, and Smallpdf—viewing, organizing, converting, compressing, annotating, signing, protecting, and exporting documents—**without uploading files to any server**.

The product is **one application**, not a grid of disconnected mini-tools. A user opens a document, inspects it, edits or annotates it, reorganizes pages, converts or compresses it, signs or protects it, and exports or shares it through the OS—all as parts of the same experience.

**Technical direction:** Flutter for UI and orchestration; **native/local engines** behind a stable Dart API for PDF structure, rendering, OCR, images, and (on desktop) Office conversion. The UI must not embed low-level PDF logic.

**Honest scope:** Many advertised “Acrobat-class” capabilities are achievable locally, but **high-fidelity PDF ↔ Office round-tripping**, **deep editing of existing PDF text**, **PDF/A across all parts**, and **enterprise-grade cryptographic signing** are **hard** and must be phased, capability-scoped, and labeled honestly in the product.

**Current phase:** Specification and architecture only. **No application code** until blocking decisions in section 30 are resolved or explicitly waived by the project owner.

---

## 2. Product vision

### 2.1 What we are building

A professional document workspace that:

- Feels credible on **desktop** (keyboard, shortcuts, inspectors, batch jobs) and **mobile/tablet** (touch, camera scan, share sheet, Files integration).
- Keeps **all core processing on-device**.
- Remains **usable with no network connection**.
- Never requires an account for core features.
- Can grow new tools via a **module/tool architecture** without rewriting the core.

### 2.2 What success looks like

| Stakeholder | Success criterion |
| --- | --- |
| End user | Common PDF and image tasks complete locally in one app, with clear progress and safe file handling. |
| Privacy-conscious user | No document upload; optional strict offline mode; transparent “what leaves the device” (nothing, for core features). |
| Maintainer / AI agent | Clear layers, one engine per concern, feature specs, test corpus, ADRs. |
| Contributor | Permissive stack where possible; licenses documented; no surprise copyleft in the shipping binary without review. |

### 2.3 Positioning (explicit)

| Dimension | Document Studio |
| --- | --- |
| Price | Free core product |
| Ads | None |
| Cloud | No cloud processing for core features |
| AI | No LLM / generative document AI (unless explicitly approved later) |
| Platforms | Android, iOS/iPadOS, Windows, macOS, Linux |
| Primary UX | Native Flutter app, **not** a website in a window |

---

## 3. Product principles

1. **Unified product** — Tools are modes of one app (reader, organize, convert, secure), sharing navigation, design system, file model, and job runner.
2. **Local-first** — Default path: file on disk → engine → output on disk.
3. **Safety** — Prefer non-destructive workflows; never silently overwrite originals.
4. **Honesty** — Distinguish overlay vs true edit, visual vs cryptographic signature, repair vs recovery, conversion vs reflow.
5. **Progressive delivery** — Ship vertical slices (reader → organize → utilities) before exotic features.
6. **Cross-platform parity where reasonable** — Same features where engines allow; **document platform gaps** instead of faking parity.
7. **Agent-safe architecture** — Small modules, explicit boundaries, tests, ADRs; agents implement; humans own product decisions.

---

## 4. Non-negotiable constraints

Unless the project owner explicitly amends this specification:

| ID | Constraint |
| --- | --- |
| NC-01 | Core product is **free** — no subscription, paywall, or paid-only core features. |
| NC-02 | **No advertisements** and no ad SDKs. |
| NC-03 | **No backend** required for core functionality (no Firebase/Supabase/custom API for document processing). |
| NC-04 | **No cloud document processing** — files are not uploaded for conversion, OCR, compression, etc. |
| NC-05 | **No mandatory account or login** for core features. |
| NC-06 | **Offline-first** — normal operations work without internet. |
| NC-07 | **No local LLM / generative AI / cloud AI** for document processing unless explicitly approved later. |
| NC-08 | **No hidden telemetry**; if optional analytics are ever added, they must be opt-in, documented, and must not include document content. |
| NC-09 | **Primary deliverable is Flutter** for listed mobile and desktop targets — not a web-first product. |
| NC-10 | User documents **must not** be sent to third-party document APIs as part of core features. |

---

## 5. Scope and non-goals

### 5.1 In scope (eventual)

- PDF lifecycle: view, create, organize, annotate, edit (within engine limits), convert, compress, OCR, forms, signatures (visual + investigated crypto), security, redaction, compare, repair, PDF/A (where supportable), metadata, bookmarks, links, attachments, print.
- Images: view, transform, compress, convert, assemble to PDF, extract from PDF.
- Documents: text/HTML/Markdown ↔ PDF where feasible; Office ↔ PDF **especially on desktop**.
- Scanning (mobile-first): camera → enhanced image → PDF → optional OCR.
- Batch processing and (later) local workflow pipelines.

### 5.2 Non-goals (core product)

| Non-goal | Reason |
| --- | --- |
| Cloud collaboration, shared links, live co-editing | Requires server infrastructure and identity. |
| Cloud e-signature routing (send to N signers, reminders, audit portal) | Inherently network workflow. |
| Mandatory user accounts | Conflicts with privacy/offline positioning. |
| Web app as primary SKU | Explicit product direction; WASM may exist technically but is not the product. |
| “Crack” encrypted PDFs without user password | Unethical and infeasible to promise. |
| Perfect Adobe-compatible editing for all PDFs | Technically unrealistic with open engines. |
| AI summarization, Q&A, translation via LLM | Excluded by NC-07 unless approved later. |

### 5.3 Out of scope until explicitly requested

- Mobile store IAP, tipping, or “pro” tier.
- Plugin marketplace / third-party cloud connectors.
- Email/fax send services integrated in-app.

---

## 6. Complete feature inventory

Features use IDs **`DS-{DOMAIN}-{NNN}`**. **Phase** references section 29. **Status** at spec time: *Planned*.

### 6.1 Application shell and platform

| ID | Feature | Phase | Notes |
| --- | --- | --- | --- |
| DS-SHELL-001 | Multi-document workspace (tabs / recents) | 1+ | Desktop tabs; mobile may use stack + recents |
| DS-SHELL-002 | Command palette / quick actions (desktop) | 3+ | Optional on mobile |
| DS-SHELL-003 | Keyboard shortcuts | 1+ | Platform-specific maps |
| DS-SHELL-004 | Drag and drop (desktop) | 1+ | |
| DS-SHELL-005 | Share / export via OS | 1+ | Share sheet, SAF, intents |
| DS-SHELL-006 | File associations / “Open with” | 3+ | Per OS |
| DS-SHELL-007 | Strict offline mode toggle | 3+ | Blocks app-initiated network |
| DS-SHELL-008 | Privacy dashboard (local status) | 3+ | Educational UI, no phoning home |
| DS-SHELL-009 | Undo/redo (editor scope) | 5+ | Operation history stack |
| DS-SHELL-010 | Local autosave / crash recovery | 5+ | Temp drafts only |

### 6.2 PDF reader

| ID | Feature | Phase |
| --- | --- | --- |
| DS-READ-001 | Open PDF from picker / intent | 1 |
| DS-READ-002 | Page thumbnails | 1 |
| DS-READ-003 | Continuous / single / two-page (desktop/tablet) | 1 |
| DS-READ-004 | Zoom, fit page, fit width | 1 |
| DS-READ-005 | Rotate view (non-destructive) | 1 |
| DS-READ-006 | Full screen / presentation | 2 |
| DS-READ-007 | Text search + highlight hits | 1–2 |
| DS-READ-008 | Text selection and copy | 1–2 |
| DS-READ-009 | Go to page | 1 |
| DS-READ-010 | Bookmarks panel (view/navigate) | 2 |
| DS-READ-011 | Link following (internal/external) | 2 |
| DS-READ-012 | Attachments panel | 10 |
| DS-READ-013 | Document properties / metadata view | 2 |
| DS-READ-014 | Print | 2–3 |
| DS-READ-015 | Password prompt for encrypted PDFs | 1 |

### 6.3 PDF page management

| ID | Feature | Phase |
| --- | --- | --- |
| DS-ORG-001 | Merge PDFs | 2 |
| DS-ORG-002 | Split PDF | 2 |
| DS-ORG-003 | Extract pages | 2 |
| DS-ORG-004 | Delete pages | 2 |
| DS-ORG-005 | Reorder pages (DnD) | 2 |
| DS-ORG-006 | Duplicate / insert / replace pages | 2 |
| DS-ORG-007 | Rotate pages (destructive) | 2 |
| DS-ORG-008 | Reverse order | 2 |
| DS-ORG-009 | Split by range / every N / bookmarks | 3–10 |
| DS-ORG-010 | Odd/even extract | 2 |
| DS-ORG-011 | Blank page detection / removal | 3–10 |
| DS-ORG-012 | Crop / resize page media box | 10 |
| DS-ORG-013 | Change page size / orientation (content scale) | 10 |

### 6.4 PDF editing

| ID | Feature | Phase | Limitation class |
| --- | --- | --- | --- |
| DS-EDIT-001 | Add new text boxes | 5 | True new content |
| DS-EDIT-002 | Edit existing text | 5 | **Hard** — font subsetting |
| DS-EDIT-003 | Add/replace/delete/move images | 5 | Engine-dependent |
| DS-EDIT-004 | Shapes, lines, arrows, freehand | 5 | |
| DS-EDIT-005 | Find & replace (text) | 10 | Mostly new-content workflow |

### 6.5 Annotations

| ID | Feature | Phase |
| --- | --- | --- |
| DS-ANN-001 | Highlight / underline / strikeout / squiggly | 4 |
| DS-ANN-002 | Sticky note / comment | 4 |
| DS-ANN-003 | Text box / callout | 4 |
| DS-ANN-004 | Ink / drawing | 4 |
| DS-ANN-005 | Stamps | 4–8 |
| DS-ANN-006 | Annotation list / edit / delete | 4 |

### 6.6 Conversion

| ID | Feature | Phase | Platform notes |
| --- | --- | --- | --- |
| DS-CNV-001 | Images → PDF | 3 | All |
| DS-CNV-002 | PDF → images | 3 | All |
| DS-CNV-003 | TXT/MD/HTML → PDF | 3–6 | Layout simple |
| DS-CNV-004 | Office → PDF | 9 | **Desktop-first** (LibreOffice) |
| DS-CNV-005 | PDF → Office | 9–10 | **Low fidelity** — warn users |
| DS-CNV-006 | PDF → TXT/MD/HTML | 6–9 | Extraction-based |

### 6.7 Compression and optimization

| ID | Feature | Phase |
| --- | --- | --- |
| DS-OPT-001 | Compression profiles + custom | 3–7 |
| DS-OPT-002 | Image recompression / DPI | 3–7 |
| DS-OPT-003 | Grayscale option | 7 |
| DS-OPT-004 | Font/object/metadata cleanup | 7 |
| DS-OPT-005 | Before/after size statistics | 3 |

### 6.8 OCR

| ID | Feature | Phase |
| --- | --- | --- |
| DS-OCR-001 | Image OCR | 6 |
| DS-OCR-002 | Scanned PDF → searchable PDF | 6 |
| DS-OCR-003 | Language packs (bundled + optional download) | 6 |
| DS-OCR-004 | Preprocessing (deskew, denoise) | 6 |
| DS-OCR-005 | Batch OCR | 11 |

### 6.9 Security

| ID | Feature | Phase |
| --- | --- | --- |
| DS-SEC-001 | Encrypt / password to open | 7 |
| DS-SEC-002 | Permission flags | 7 |
| DS-SEC-003 | Unlock (with password) | 7 |
| DS-SEC-004 | Permanent redaction | 7–10 |
| DS-SEC-005 | Metadata scrub | 3+ |

### 6.10 Forms and signatures

| ID | Feature | Phase |
| --- | --- | --- |
| DS-FORM-001 | Detect and fill AcroForm fields | 8 |
| DS-FORM-002 | Flatten forms | 8 |
| DS-FORM-003 | Create/edit fields | 10 |
| DS-SIG-001 | Visual signatures (draw/type/image) | 8 |
| DS-SIG-002 | Cryptographic PDF signatures | 10 | Investigation |

### 6.11 Advanced PDF

| ID | Feature | Phase |
| --- | --- | --- |
| DS-ADV-001 | Compare PDFs | 10 |
| DS-ADV-002 | Repair / validate | 10 |
| DS-ADV-003 | PDF/A convert + validate | 10 |
| DS-ADV-004 | Bookmarks CRUD | 10 |
| DS-ADV-005 | Links CRUD | 10 |
| DS-ADV-006 | Attachments CRUD | 10 |

### 6.12 Images

| ID | Feature | Phase |
| --- | --- | --- |
| DS-IMG-001 | Image viewer | 3 |
| DS-IMG-002 | Convert / resize / crop / rotate | 3 |
| DS-IMG-003 | Compress + strip metadata | 3–7 |
| DS-IMG-004 | SVG rasterization (where used) | 6+ |

### 6.13 Scanning

| ID | Feature | Phase |
| --- | --- | --- |
| DS-SCAN-001 | Camera capture + document detect | 6 |
| DS-SCAN-002 | Perspective correction + enhance | 6 |
| DS-SCAN-003 | Multi-page scan → PDF | 6 |
| DS-SCAN-004 | Scan → OCR PDF | 6 |

### 6.14 Automation

| ID | Feature | Phase |
| --- | --- | --- |
| DS-BATCH-001 | Batch tool runner | 11 |
| DS-FLOW-001 | User-defined workflows | 12 |

---

## 7. Functional requirements

### 7.1 Global behavior

- **FR-G-01:** Every processing tool accepts explicit inputs (paths, URIs, or in-memory handles with provenance) and produces explicit outputs; no silent side effects on originals.
- **FR-G-02:** Long operations report progress and support cancellation where technically possible.
- **FR-G-03:** Errors map to user-readable messages (section 24); logs never contain document body text by default.
- **FR-G-04:** Encrypted PDFs require correct passwords; the app must not claim to bypass encryption.
- **FR-G-05:** Features unavailable on a platform must be hidden or disabled with explanation, not fail at runtime without context.

### 7.2 PDF reader (summary)

Must satisfy section 9 requirements of the product brief: navigation, zoom modes, search, selection, bookmarks (view), links, print/share, mobile gestures, desktop keyboard/mouse.

### 7.3 Page management

Must support merge, split, extract, delete, reorder, duplicate, rotate, insert, replace, reverse, range operations; desktop DnD and mobile touch reorder.

### 7.4 Editing and annotations

Must distinguish **ContentEdit** (mutates PDF content streams where supported) vs **Annotation** (standard annotation dictionaries) vs **Overlay** (non-PDF-native drawing in UI only — **avoid for export** unless explicitly “flatten to image”).

### 7.5 Conversion

Must document fidelity expectations in UI for Office and PDF→Office (section 15).

### 7.6 OCR

Must produce searchable PDFs with invisible text layer when engine supports it; allow plain text export.

### 7.7 Security

Redaction must remove underlying content when feature is labeled “Permanent redaction” (section 20).

### 7.8 Batch and workflows

Batch: configurable output folder, naming pattern, continue-on-error option. Workflows: DAG of registered local tools with saved presets.

---

## 8. Non-functional requirements

| ID | Category | Requirement |
| --- | --- | --- |
| NFR-01 | Responsiveness | UI isolate must not block on CPU-heavy work > ~16ms sustained; use isolates/native workers. |
| NFR-02 | Memory | Stream large files; avoid loading entire multi-hundred-MB PDF into Dart heap unless necessary. |
| NFR-03 | Startup | Cold start acceptable for heavy app; lazy-load engines and language packs. |
| NFR-04 | Accessibility | Support platform accessibility (Semantics, screen readers); keyboard nav on desktop. |
| NFR-05 | i18n | UI strings externalized; OCR languages separate from UI locale. |
| NFR-06 | Reliability | Atomic writes; crash-safe temp dirs; recoverable editor drafts. |
| NFR-07 | Security | Treat all imports as untrusted; limit parser allocations (section 20). |
| NFR-08 | Maintainability | One registration point for tools; no duplicate PDF merge implementations. |
| NFR-09 | Licensing | Shipping artifacts comply with aggregated licenses (section 13). |
| NFR-10 | Testability | Engines behind interfaces; golden tests for render; corpus for PDF ops (section 25). |

**Performance targets (initial — refine after Phase 1 benchmarks):**

| Scenario | Target (guidance) |
| --- | --- |
| Open 10 MB, 100-page PDF | Interactive navigation < 2 s on mid-range mobile, < 1 s desktop |
| Page render (cached) | < 100 ms perceived for adjacent pages |
| Merge 20 PDFs (500 pages total) | Complete with progress; no UI freeze |
| OCR 20 pages scanned | Background job; cancellable |
| Batch 100 compress jobs | Queue with partial failure report |

---

## 9. Target platforms and platform matrix

### 9.1 Supported platforms (primary)

| Platform | Form factors | Minimum OS (to be confirmed in ADR) |
| --- | --- | --- |
| Android | Phone, tablet | API 24+ recommended (qpdf/Tesseract ecosystem alignment) |
| iOS / iPadOS | Phone, tablet | iOS 14+ (file picker); 15.5+ if ML Kit used optionally |
| Windows | Desktop | Windows 10+ (WebView2 not required — Flutter) |
| macOS | Desktop | macOS 11+ (Apple Silicon + Intel) |
| Linux | Desktop | glibc-based distros; musl best-effort |

### 9.2 Capability matrix (expected — not all parity)

| Capability | Android | iOS | Win | macOS | Linux |
| --- | --- | --- | --- | --- | --- |
| PDF view (PDFium) | Yes | Yes | Yes | Yes | Yes |
| PDF page ops (qpdf) | Yes* | Yes* | Yes | Yes | Yes |
| Office → PDF | No** | No** | Yes | Yes | Yes |
| PDF → Office | Limited | Limited | Partial | Partial | Partial |
| Tesseract OCR | Yes | Yes | Yes | Yes | Yes |
| ML Kit OCR (optional) | Optional | Optional | No | No | No |
| Camera scan | Yes | Yes (VisionKit) | N/A | N/A | N/A |
| System print | Yes | Yes | Yes | Yes | Yes |

\*Requires shipping static/shared native libraries per ABI — engineering cost, feasible per qpdf/mobile build reports.  
\*\*Unless separate mobile strategy (serverless conversion not allowed) — see ADR-005.

### 9.3 Mobile-specific (mandatory design)

**Android:** Scoped storage, SAF URIs, persistable permissions, share intents, foreground service for long jobs where required, no assumption of raw paths, Camera permission, lifecycle-aware cancellation.

**iOS/iPadOS:** UIDocumentPicker, security-scoped bookmarks, share sheet, camera/photos permissions, background time limits, iPad multitasking layouts, Pencil/stylus as pointer where supported.

### 9.4 Desktop-specific (mandatory design)

File associations, drag-drop, multi-window (future), native print dialog, keyboard shortcuts, clipboard, context menus.

---

## 10. Architecture proposal

### 10.1 Layered model

```
┌─────────────────────────────────────────────────────────────┐
│  Presentation (Flutter widgets, routes, design system)       │
└────────────────────────────┬────────────────────────────────┘
                             │ commands / state
┌────────────────────────────▼────────────────────────────────┐
│  Application (use cases, controllers, ToolRunner, workflows) │
└────────────────────────────┬────────────────────────────────┘
                             │ domain types
┌────────────────────────────▼────────────────────────────────┐
│  Domain (DocumentRef, PageIndex, Job, AnnotationModel, …)    │
└────────────────────────────┬────────────────────────────────┘
                             │ ports (interfaces)
┌────────────────────────────▼────────────────────────────────┐
│  Infrastructure (engine adapters, FFI, platform channels)    │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│  Platform + Local filesystem + OS integrations               │
└─────────────────────────────────────────────────────────────┘
```

**Rule:** Widgets → **Application command** → **Domain operation** → **Engine port** → result. No widget imports PDFium FFI directly.

### 10.2 Core subsystems (engine ports)

| Port | Responsibility |
| --- | --- |
| `PdfRenderPort` | Rasterize pages, text extraction for search/selection |
| `PdfStructurePort` | Merge, split, rotate, encrypt, repair, linearize, metadata |
| `PdfEditPort` | Page objects: text, paths, images (where supported) |
| `PdfAnnotationPort` | Read/write standard annotations |
| `PdfFormPort` | AcroForm fields |
| `ImagePort` | Decode, encode, transform |
| `OcrPort` | OCR image or page render → text / searchable PDF |
| `ConversionPort` | Office and markup conversions |
| `PrintPort` | OS print |
| `ScanPort` | Camera + document detection (mobile) |
| `FileStoragePort` | Paths, SAF, temp files, atomic write |

Implementations may **compose** engines (e.g. render via PDFium, structure via qpdf).

### 10.3 Tool registry

Each user-facing tool registers:

- `toolId`, category, supported platforms
- input/output MIME types
- `estimateWork()` / `run(JobContext, progress, cancelToken)`

Batch and workflow engines iterate the same registry — **no one-off scripts** per tool.

### 10.4 Job execution

- **Interactive jobs** (view, edit): high priority, tied to document lifecycle.
- **Background jobs** (batch, OCR): `Isolate` / native worker pool; mobile respects OS background limits — use foreground notification on Android for long OCR.

### 10.5 Document model (conceptual)

- **`DocumentRef`**: stable ID, display name, source URI/path, format, security state, dirty flag.
- **`PdfDocumentHandle`**: opaque engine handle; not serialized to disk.
- **`PageRef`**: `(documentId, pageIndex)` for UI and jobs.
- **`EditSession`**: undo stack scoped to one document; commits produce new PDF bytes or incremental save via engine.

---

## 11. Flutter application architecture

### 11.1 Recommended project structure

```
lib/
  app/                 # MaterialApp, router, theme, DI
  design_system/       # tokens, components
  features/            # feature modules (reader, organize, …)
    reader/
      presentation/
      application/
      domain/
  core/
    domain/            # shared models, errors
    ports/             # abstract engine interfaces
    jobs/              # job runner, progress
  infrastructure/      # adapters (pdfium, qpdf, …)
  platform/            # per-OS services
packages/
  document_studio_pdf/           # optional federated plugin monorepo
  document_studio_pdf_qpdf/
  document_studio_ocr/
  document_studio_scan/
```

Monorepo **federated plugins** are recommended for FFI-heavy code to isolate build complexity from UI code.

### 11.2 State management

**Recommended (pending ADR-006):** Riverpod or similar explicit DI + async providers for job state.  
Requirements: testability, clear separation from engines, no global singletons for document handles.

### 11.3 Routing

- **Phone:** bottom nav for Home, Tools, Recents, Settings; document viewer full-screen route.
- **Tablet:** navigation rail + master/detail.
- **Desktop:** sidebar (library/tools) + document workspace + inspector panel.

Use `go_router` or equivalent; deep links for “open file” intents.

### 11.4 Plugin integration patterns

| Pattern | Use when |
| --- | --- |
| **Dart FFI** | PDFium, qpdf, Tesseract on desktop and mobile |
| **Platform channel** | VisionKit scanner, Android SAF helpers, file associations |
| **Pure Dart** | Markdown→PDF simple layout, job orchestration |
| **External process** | LibreOffice `soffice` on desktop only |

---

## 12. Technology evaluation and recommendations

Evaluations are based on verified 2026 public sources (pub.dev, project docs, licenses). **Final versions pinned at implementation time.**

### 12.1 PDF rendering and light manipulation

| Option | License | Flutter | Platforms | Verdict |
| --- | --- | --- | --- | --- |
| **pdfrx / pdfrx_engine / pdfium_flutter** | MIT (plugin); PDFium BSD/Apache + bundled deps | Strong | Android, iOS, Win, macOS, Linux | **Recommended** viewer + page combine + image→PDF |
| pdfrx_coregraphics | MIT | iOS/macOS only | Smaller app; different render path | Optional ADR |
| syncfusion_flutter_pdf* | Commercial / Community | Strong | All | **Reject for default** — revenue/employee limits |
| MuPDF | AGPL / commercial | Via bindings | All | **Reject** unless commercial license purchased |
| Poppler/Ghostscript | GPL/AGPL | Poor | Desktop | **Reject** for default stack |

**pdfrx limits (verified):** Strong page manipulation and rendering; **annotation authoring** and deep content edit APIs are **immature** (upstream discussions target future major versions). Plan complementary engines for annotations/security.

### 12.2 PDF structure, encryption, repair

| Option | License | Verdict |
| --- | --- | --- |
| **qpdf** | Apache-2.0 | **Recommended** merge/split/encrypt/decrypt/stream recompress/xref repair |
| lopdf (Rust) | MIT | Possible via FFI; encryption+object stream edge cases — not primary for Flutter |
| Apache PDFBox | Apache-2.0 | JVM — avoid as embedded default |

Mobile: qpdf **can** be cross-compiled (static libs); budget native build pipeline per ABI.

### 12.3 PDF editing and annotations

| Need | Engine direction |
| --- | --- |
| Add text/image/path | PDFium via pdfium_dart / custom FFI |
| Edit existing text | Limited — subset fonts; often replace via redact+overlay |
| Standard annotations | PDFium annot APIs or qpdf JSON/object rewrite — **custom adapter required** |
| Redaction | qpdf + content removal pipeline; verify with tests |

### 12.4 Images

| Option | License | Verdict |
| --- | --- | --- |
| **`image` (Dart)** | MIT | **Recommended** default for decode/resize/crop in isolates |
| flutter image plugins | Various | Use for display (`Image.memory`) |

WebP: `image` + `image_webp` (MIT) for broader codec support.

### 12.5 OCR

| Option | License | Platforms | Verdict |
| --- | --- | --- | --- |
| **Tesseract 5** | Apache-2.0 | All (bundle per platform) | **Recommended canonical engine** |
| tesseract_ocr / flutter_tesseract_ocr | BSD-3 (plugin) | Android, iOS | Useful bootstrap; extend for desktop |
| google_mlkit_text_recognition | Google terms | Android, iOS only | **Optional** fast Latin OCR; not sole engine |
| Apple Vision | Apple SDK | iOS/macOS | Optional; same caveat |

Searchable PDF: render page → Tesseract `pdf` output → merge layers (custom pipeline).

### 12.6 Office conversion

| Option | License | Verdict |
| --- | --- | --- |
| **LibreOffice headless** (`soffice --headless`) | MPL-2.0 | **Recommended desktop** for DOC/XLS/PPT → PDF |
| Embedded commercial SDKs | Commercial | Reject unless explicitly funded |
| Cloud APIs | N/A | **Forbidden** for core |

PDF → Office: extraction + heuristics only; **no layout guarantee**.

### 12.7 PDF/A

| Option | License | Verdict |
| --- | --- | --- |
| veraPDF | MPL-2.0 / GPL-3+ dual | Validation tool (external binary on desktop) |
| pdftopdfa (Python) | MPL-2.0+ | Possible desktop CLI; not mobile default |
| Ghostscript | AGPL | Reject |

Ship **PDF/A only after** validation pipeline proven on corpus.

### 12.8 Printing

| Option | License | Verdict |
| --- | --- | --- |
| **`printing`** | Apache-2.0 | **Recommended** cross-platform print |

### 12.9 File picking and storage

| Option | License | Verdict |
| --- | --- | --- |
| **`file_picker`** | MIT | **Recommended** |
| path_provider, share_plus | BSD/MIT | Standard |

### 12.10 Scanning

| Platform | Approach |
| --- | --- |
| iOS | **VisionKit** `VNDocumentCameraViewController` via platform channel |
| Android | **CameraX + OpenCV** (or maintained SDK e.g. Document-Scanning-Android-SDK) — **avoid ML Kit Document Scanner as required dependency** (Play Services) for offline parity |

### 12.11 Digital signatures

| Option | License | Verdict |
| --- | --- | --- |
| Visual signature | PDFium page objects | Phase 8 |
| pdf_signing (Dart) | MIT/Apache | WIP — investigate |
| pdf_signer | GPL-3.0 | **Do not ship** in default product |

Cryptographic signing: Phase 10 with legal/compliance review; PAdES levels requiring TSA need network — disclose if ever optional.

---

## 13. Dependency and license strategy

### 13.1 Allowed licenses (default)

**Permissive:** MIT, BSD-2/3, Apache-2.0, ISC, Unicode/ICU permissive, PDFium composite (retain NOTICES).

**Conditional:**

| License | Condition |
| --- | --- |
| MPL-2.0 | OK for **separate process** (LibreOffice) or file-level compliance; document in `LICENSES.md` |
| LGPL | Avoid linking unless dynamic linking compliance verified |
| GPL/AGPL | **Prohibited** in shipped app unless owner approves |

### 13.2 Dependency record template

Each entry in `docs/DEPENDENCIES.md` must include: Name, Version, Purpose, License, Repository, Platform support, Integration (pub / FFI / process), Security notes, Alternatives, Selection rationale.

### 13.3 Prohibited without approval

- Analytics SDKs that transmit content or persistent device IDs by default.
- Cloud OCR/convert SDKs.
- GPL/AGPL native libraries linked into the app binary.
- “Community” commercial licenses with org revenue caps as **sole** PDF engine (Syncfusion pattern).

### 13.4 Third-party notices

Ship **`NOTICE`** / **`ThirdPartyLicenses`** screen aggregating PDFium, qpdf, Tesseract, FreeType, etc., from upstream `licenses/` folders (bblanchon/pdfium-binaries pattern).

---

## 14. PDF engine strategy

### 14.1 Dual-engine model (recommended)

| Layer | Engine | Role |
| --- | --- | --- |
| **Render & interact** | PDFium (via pdfrx stack or thin FFI) | Display, text extract, search, forms display, light object insert |
| **Structure & security** | qpdf | Merge/split, rotate, encrypt, decrypt, linearize, stream compression, xref repair, attachment ops at PDF object level |

**Do not** implement PDF syntax parsers in Dart.

### 14.2 Single abstraction

`PdfService` facade internally delegates:

- `openDocument(path|bytes)` → render handle + optional qpdf doc id
- `saveDocument()` → qpdf rewrite or PDFium save — **one code path** per operation type documented in `PDF-ENGINE.md`

### 14.3 Feature mapping

| Feature | Primary engine |
| --- | --- |
| View / zoom / thumb | PDFium |
| Search / copy text | PDFium text page API |
| Merge/split/rotate pages | pdfrx_engine pages API + qpdf for edge cases |
| Encrypt/decrypt | qpdf |
| Compress streams | qpdf `--recompress-flate`, object cleanup |
| Image-heavy compress | Render + re-encode pipeline (lossy) — **destructive** — user consent |
| Forms fill | PDFium experimental form APIs — test per platform |
| Redaction | qpdf content removal + annotation cleanup |

### 14.4 iOS/macOS PDFium size

Optional **CoreGraphics path** (pdfrx_coregraphics) reduces binary size; if enabled, test render parity on corpus (fonts, transparency, overprint).

### 14.5 Passwords

- Attempt empty user password first where PDF allows.
- Never persist passwords in logs; optional session-only secure storage (platform keychain).

---

## 15. Conversion strategy

### 15.1 Fidelity classes (must show in UI)

| Class | Description | Example |
| --- | --- | --- |
| **A — Pixel/layout faithful** | Visual appearance preserved | PDF → PNG |
| **B — Structural faithful** | Tags/paragraphs, not exact layout | PDF → DOCX (best effort) |
| **C — Text only** | Plain text extraction | PDF → TXT |
| **D — Authoring new layout** | New document generated | MD → PDF |

### 15.2 Pipelines

| Conversion | Pipeline | Class |
| --- | --- | --- |
| JPG/PNG → PDF | image decode → page size → PDFium create OR pdfrx createFromJpeg | A |
| PDF → images | PDFium render at DPI | A |
| TXT/MD → PDF | Dart layout engine (simple) | D |
| HTML → PDF | WebView snapshot or lightweight HTML renderer — **investigate** | D |
| Office → PDF | Desktop: spawn LibreOffice with timeout and isolated profile dir | A–B |
| PDF → Office | Text/table extraction libraries — **limited** | B–C |

### 15.3 Mobile Office gap

**Default spec:** Office conversion tools **desktop-only** until ADR-005 approves a mobile strategy (e.g. “import PDF only on mobile”, or bundled converter — likely impractical size-wise).

### 15.4 Fonts

LibreOffice conversions require **document fonts** installed on OS; warn when missing (layout shift).

---

## 16. OCR strategy

### 16.1 Architecture

```
PDF page or image
  → optional OpenCV/dart preprocessing (deskew, binarize)
  → Tesseract (libtesseract)
  → outputs: plain text, hOCR/TSV, searchable PDF layer
  → if searchable PDF: merge text layer with original image (per-page)
```

### 16.2 Language packs

- Bundle **eng** (and one secondary as product decision).
- Additional languages: downloadable `.traineddata` to app private storage — **download is optional user action**, not silent phone-home; can ship offline language pack expansion files in store updates.

### 16.3 Platform adapters

| Platform | Adapter |
| --- | --- |
| Android/iOS | Plugin wrapping Tesseract4Android / SwiftyTesseract **or** unified FFI |
| Windows/macOS/Linux | FFI to libtesseract or controlled subprocess to `tesseract` binary |

**Single `OcrPort` interface** — no feature calls Tesseract directly from widgets.

### 16.4 Optional accelerators

ML Kit / Vision: only if results feed same `OcrResult` model and user can choose “Compatibility engine (Tesseract)” in settings.

### 16.5 Quality expectations

Handwriting, complex scripts, and low-DPI scans will fail partially — show confidence and allow manual retry with preprocessing presets.

---

## 17. Editor and annotation architecture

### 17.1 Three editing modes (user-visible)

| Mode | User label | Technical |
| --- | --- | --- |
| **Annotate** | Comments, highlights | PDF annotation dictionaries |
| **Add content** | Add text/image/shape | New page objects |
| **Edit existing** | Edit text | Mutate content streams — **only when engine confirms** |

UI must not label “Add text box” as “Edit PDF text”.

### 17.2 Coordinate systems

- PDF user space (points, origin bottom-left) ↔ Flutter logical pixels (top-left).
- Central **`PdfViewportTransform`** shared by viewer, hit-testing, annotations.

### 17.3 Undo/redo

Operation-based history at application layer:

- Each command implements `execute()` / `revert()` against engine or in-memory overlay model.
- Commit to PDF bytes on explicit Save or autosave checkpoint.

### 17.4 Annotation compatibility

Prefer standard subtypes (`Highlight`, `Text`, `Ink`, …) so external readers display annotations.

### 17.5 Redaction

Pipeline: mark regions → remove text/image operators under region → remove hidden text layer → strip metadata optionally → verify extraction cannot recover content (regression tests).

---

## 18. UI/UX architecture

### 18.1 Information architecture

**Primary areas:**

1. **Home** — Recents, favorites, open file, drop zone (desktop).
2. **Document workspace** — Viewer/editor canvas + page strip.
3. **Tools** — Categorized actions (Organize, Convert, Secure, …) — same engine as in-document menus.
4. **Inspector** — Properties, metadata, security, optimization stats.
5. **Settings** — Privacy, offline mode, OCR languages, default export folders.

### 18.2 Responsive layouts

| Breakpoint | Layout |
| --- | --- |
| Phone (<600dp) | Bottom nav; tools in sheets; single-pane viewer |
| Tablet (600–1024dp) | Rail + workspace; optional page strip |
| Desktop (>1024dp) | Sidebar + workspace + inspector; menu bar (macOS) |

**Forbidden:** Scaling phone UI to desktop width without adding inspector/toolbar density.

### 18.3 Interaction patterns

- Long operations: modal progress with cancel; desktop allows background panel.
- Destructive quality loss (strong compress, flatten): confirmation + preview where feasible.
- Empty states: guided “Open file” / “Scan document” / “Try sample” (bundled sample PDF, no network).

### 18.4 Command palette (desktop)

Searchable actions mirroring menus; extensible via tool registry.

---

## 19. Design system requirements

### 19.1 Brand direction

Professional utility — trustworthy, calm, dense enough for desktop, touch-friendly on mobile. Logo reference: stacked document mark with **Document** (neutral dark) + **Studio** (accent blue).

### 19.2 Tokens (initial — refine in `DESIGN-SYSTEM.md`)

| Token | Light | Dark |
| --- | --- | --- |
| `color.primary` | `#2563EB` (accent blue) | `#3B82F6` |
| `color.surface` | `#FFFFFF` | `#0F172A` |
| `color.surfaceAlt` | `#F8FAFC` | `#1E293B` |
| `color.textPrimary` | `#0F172A` | `#F1F5F9` |
| `color.textSecondary` | `#64748B` | `#94A3B8` |
| `color.success` | `#059669` | `#34D399` |
| `color.warning` | `#D97706` | `#FBBF24` |
| `color.error` | `#DC2626` | `#F87171` |
| `color.docRed` | `#EF4444` | (icon accent) |
| `color.docAmber` | `#F59E0B` | (icon accent) |

Typography: system UI stack (SF Pro, Roboto, Segoe UI) via Flutter `ThemeData`; monospace for paths/logs in debug only.

Spacing scale: 4, 8, 12, 16, 24, 32, 48.  
Radius: 8 default, 12 cards, 999 pills.  
Elevation: subtle shadows on desktop cards only; Material 3 on Android.

### 19.3 Components (must be shared)

Buttons (primary/secondary/ghost/destructive), text fields, dropdowns, menus, tabs, dialogs, bottom sheets, side panels, toolbars, data tables (batch queue), progress indicators, toasts/snackbars, list tiles, page thumbnail tile, document tab.

### 19.4 Icons

Use consistent outlined icon set (e.g. Material Symbols); custom icons only for PDF-specific tools if needed.

### 19.5 Themes

Light, dark, system — persisted locally.

---

## 20. Security architecture

### 20.1 Threat model (summary)

- Malformed PDFs (parser crashes, memory exhaustion).
- Decompression bombs (flate streams).
- JavaScript/actions in PDF (disable execution; engines should not run JS).
- Malicious attachments (scan with size limits; open with user consent).
- Path traversal in zip/extract workflows.
- Sensitive data in temp dirs or crash logs.
- Clipboard leaking redacted content after “copy”.

### 20.2 Controls

| Control | Implementation |
| --- | --- |
| Size limits | Configurable max file/pages/DPI for render |
| Timeouts | LibreOffice and repair ops |
| Temp directory | App-private; delete on success; secure delete best-effort |
| Passwords | Keychain/Keystore optional; never log |
| Redaction | True content removal (section 17.5) |
| Updates | Engine CVE tracking in maintenance process |

### 20.3 Encryption claims

qpdf/PDFium support standard PDF encryption. Weak legacy algorithms may still be read; warn on write. **Never** market “remove password” without user-supplied password.

---

## 21. Privacy architecture

### 21.1 Data flows (core product)

```
User file (local)
  → in-process engines
  → output file (local)
  → optional OS share sheet (user initiated)
```

No Document Studio server in path.

### 21.2 Network policy

- Core app: **no outbound network** required.
- **Strict offline mode:** OS-level blocking is not always possible; implement **application-level** refusal to open sockets for optional features (language pack download only when user taps Download and mode allows).

### 21.3 Logging

- Allowed: error codes, durations, file sizes, page counts.
- Forbidden: extracted text, passwords, base64 of documents, PII from document content.

### 21.4 Privacy dashboard (UI)

Static indicators: Network not used, No upload, No cloud processing, Local OCR, No AI — tied to actual build flags, not marketing alone.

---

## 22. File-processing architecture

### 22.1 Standard pipeline

```
1. Resolve input (path, content URI, bytes)
2. Validate format + size + permissions
3. Copy to job workspace (temp) if mutating
4. Execute engine steps
5. Validate output (open test, checksum optional)
6. Atomic rename to destination OR return to share sheet
7. Cleanup temp
```

### 22.2 Overwrite policy

Default: **Save As** new file. “Replace original” requires explicit checkbox + name confirmation.

### 22.3 Android SAF

Persist URI permissions; store stable document IDs in local prefs (no cloud sync).

### 22.4 Atomic write

Write to `*.partial` then rename; on failure, leave original untouched.

---

## 23. Performance requirements

- PDF render: tile large pages; cache bitmaps with LRU bounded by memory class (phone vs desktop).
- Use **`compute()` / isolates** for image encode, OCR, batch compress.
- qpdf operations on huge page counts: run in native thread pool; stream progress via page count.
- Avoid duplicating full PDF in Dart and native simultaneously when possible.

Benchmark suite in Phase 1 establishes baselines (section 25).

---

## 24. Error handling

### 24.1 Internal error codes

| Code | Meaning |
| --- | --- |
| `FILE_NOT_FOUND` | Missing path/URI |
| `INVALID_FILE` | Unreadable container |
| `INVALID_PDF` | Not PDF |
| `CORRUPTED_PDF` | Parse failure |
| `PASSWORD_REQUIRED` | Encrypted, no password |
| `WRONG_PASSWORD` | Decrypt failed |
| `UNSUPPORTED_FORMAT` | MIME/extension unsupported |
| `UNSUPPORTED_PLATFORM` | Tool not on this OS |
| `CONVERSION_FAILED` | Engine error |
| `OCR_FAILED` | No text / engine fail |
| `INSUFFICIENT_MEMORY` | OOM guard |
| `DISK_FULL` | Write failed |
| `PERMISSION_DENIED` | SAF/OS denial |
| `PROCESS_CANCELLED` | User cancel |
| `ENGINE_UNAVAILABLE` | Native lib missing |
| `TIMEOUT` | Operation exceeded limit |

### 24.2 User messages

Map codes → short title + actionable body (“Enter password”, “Free space”, “Try repair tool”).

### 24.3 Developer diagnostics

Detailed logs behind debug flag only; never default in release.

---

## 25. Testing strategy

### 25.1 Layers

| Layer | Scope |
| --- | --- |
| Unit | Domain, job runner, path validation, error mapping |
| Widget | Design system, reader controls |
| Integration | Engine adapters with golden PDFs |
| E2E | Open → merge → export on CI desktop |
| Native | FFI smoke tests per ABI |
| Performance | Benchmark regressions |
| Security | Malformed corpus, bomb sizes |

### 25.2 Test corpus (`tests/corpus/`)

Simple, large, scanned, encrypted, forms, annotations, image-heavy, font-heavy, malformed, multi-page, complex-layout, redaction verification, PDF/A samples.

### 25.3 Definition of done

Feature done only if: UI + engine + tests + platform matrix entry + known limitations documented in feature spec.

### 25.4 CI strategy

- Linux CI: qpdf + PDFium + unit tests.
- macOS/Windows runners for desktop FFI and LO conversions (scheduled).
- Mobile: build APK/IPA on release branches; device farm optional.

---

## 26. Cross-platform strategy

- **One Flutter codebase**; platform folders for entitlements, associations, scanners.
- **Conditional imports** for `dart:io` vs web — web not product target but keep engine interfaces pure where cheap.
- **Feature flags** per platform in tool registry — single source of truth.
- **Visual parity** not required; **functional parity** where engines allow.

---

## 27. AI development rules

Every AI agent **must**:

1. Read this specification before major changes.
2. Inspect existing code and ADRs before editing.
3. Follow layered architecture (section 10).
4. Avoid unrelated refactors and duplicate tools.
5. Avoid new dependencies without license entry in `DEPENDENCIES.md`.
6. Never introduce backend, cloud processing, or local AI without explicit approval.
7. Never exfiltrate document contents.
8. Add tests for new behavior.
9. Update docs and feature checklist when architecture or scope changes.
10. Preserve existing behavior unless spec changes.
11. Stop and document conflicts instead of silent decisions.
12. Not scaffold Flutter project or add pub dependencies unless the owner asks to begin implementation.

Agents are **implementers**, not product owners.

---

## 28. Documentation strategy

Create docs **when implementation starts**, driven by this spec — not empty placeholders.

| Document | Purpose |
| --- | --- |
| `docs/PROJECT-CONTEXT.md` | Short onboarding |
| `docs/PRODUCT-REQUIREMENTS.md` | FR/NFR extracted |
| `docs/ARCHITECTURE.md` | Layers, diagrams, ports |
| `docs/FLUTTER-ARCHITECTURE.md` | Folder layout, state, routing |
| `docs/TECH-STACK.md` | Pinned versions |
| `docs/DEPENDENCIES.md` | Full dependency records |
| `docs/LICENSES.md` | Compliance |
| `docs/DESIGN-SYSTEM.md` | Tokens, components |
| `docs/UI-UX.md` | Flows, breakpoints |
| `docs/SECURITY.md` | Threat model |
| `docs/PRIVACY.md` | Network policy |
| `docs/PDF-ENGINE.md` | PDFium+qpdf split |
| `docs/IMAGE-ENGINE.md` | Image pipelines |
| `docs/OCR-ENGINE.md` | Tesseract adapters |
| `docs/CONVERSION-ENGINE.md` | LO, fidelity classes |
| `docs/EDITOR-ARCHITECTURE.md` | Modes, undo |
| `docs/FILE-SYSTEM.md` | SAF, atomic write |
| `docs/PERFORMANCE.md` | Benchmarks |
| `docs/TESTING.md` | Corpus, CI |
| `docs/PLATFORM-INTEGRATION.md` | Intents, associations |
| `docs/RELEASE.md` | Store/desktop packaging |
| `docs/ROADMAP.md` | Living roadmap |
| `docs/DECISIONS.md` | ADR index |
| `features/*.md` | Per-feature specs |
| `.ai/AGENTS.md`, `RULES.md`, `WORKFLOW.md`, `CHECKLIST.md` | Agent ops |

---

## 29. Roadmap

### Phase 0 — Foundation

Flutter project (when authorized), monorepo plugins skeleton, ADRs, design tokens, `FileStoragePort`, tool registry shell, CI lint/test, corpus bootstrap.

**Exit:** Hello-world open PDF on all targets OR documented platform exceptions.

### Phase 1 — PDF reader

Open, render, thumbs, zoom, nav, search (basic), properties, password prompt, mobile gestures, desktop shortcuts.

### Phase 2 — Page management

Merge, split, extract, delete, reorder, rotate, insert, duplicate, reverse, odd/even.

### Phase 3 — Core tools

Compress (basic), image↔PDF, metadata view/edit, watermark/page numbers (simple).

### Phase 4 — Annotation

Highlight, underline, strikeout, notes, ink, shapes, list panel.

### Phase 5 — Editing

Add content + limited true edit; undo/redo; save/as.

### Phase 6 — OCR + scan

Tesseract integration, searchable PDF, mobile scan pipelines.

### Phase 7 — Security

Encrypt, permissions, unlock, metadata scrub, redaction v1.

### Phase 8 — Forms & visual signatures

Fill, flatten, signature stamps.

### Phase 9 — Office conversion (desktop)

LibreOffice integration, fidelity warnings.

### Phase 10 — Advanced PDF

Compare, repair, PDF/A, attachments, bookmarks/links edit, crypto signing investigation.

### Phase 11 — Batch processing

Queue UI, reports, partial success.

### Phase 12 — Workflow engine

Saved local pipelines.

---

## 30. Risks, unknowns, and decisions requiring confirmation

### 30.1 Risk register

| Risk | Impact | Probability | Mitigation | Open question |
| --- | --- | --- | --- | --- |
| PDF editing complexity | High | High | Phase add-content before true edit; honest UI | Which edit ops in v1? |
| pdfrx annotation gaps | High | Medium | Custom PDFium annot FFI or wait upstream | Build vs buy time |
| qpdf mobile binary size | Medium | Medium | Static link per ABI; lazy load | Acceptable APK size? |
| Office on mobile | High | High | Desktop-only tools | Mobile import strategy? |
| PDF→Office quality | Medium | High | Fidelity class C/B labels | Ship at all? |
| OCR size + speed | Medium | Medium | tessdata_fast; DPI limits | Bundled languages? |
| iOS background OCR | Medium | High | Foreground jobs | UX for long jobs |
| Android SAF UX friction | Medium | Medium | Strong recents + URI cache | |
| LibreOffice bundling | High | Medium | Require install vs ship | Installer size/legal |
| PDF/A compliance | Medium | High | Defer; external validator | Target parts 1b/2b/3? |
| Crypto signatures GPL libs | High | Medium | MIT WIP only | Legal review |
| Malformed PDF crashes | High | Medium | Fuzzing, limits | |
| Cross-render parity | Medium | Medium | Golden tests | Use CoreGraphics on Darwin? |
| Flutter FFI maintenance | Medium | Medium | Federated plugins | Monorepo owner |

### 30.2 Technical unknowns

- HTML→PDF best approach on all platforms without headless Chrome dependency.
- PDF compare at text level vs render diff — performance on mobile.
- Form filling appearance streams across PDFium versions.
- Whether to bundle LibreOffice or require user install.
- Desktop Linux musl support for PDFium prebuilts.

### 30.3 Decisions requiring confirmation (blocking)

| ID | Decision | Recommendation | Status |
| --- | --- | --- | --- |
| D-01 | Primary PDF viewer stack | pdfrx + PDFium | **Recommended** |
| D-02 | PDF structure/security engine | qpdf via FFI plugin | **Recommended** |
| D-03 | OCR engine | Tesseract everywhere | **Recommended** |
| D-04 | Optional mobile OCR accelerator | Off by default; ML Kit optional | Pending |
| D-05 | Office conversion on mobile | None in v1; desktop LibreOffice | **Recommended** |
| D-06 | LibreOffice delivery | Detect install + guided download (no silent install) | Pending |
| D-07 | Darwin PDF render | PDFium everywhere vs CoreGraphics on iOS/macOS | Pending |
| D-08 | State management | Riverpod | Pending |
| D-09 | Monorepo plugin layout | `packages/document_studio_*` | Pending |
| D-10 | Minimum OS versions | Android 24, iOS 14, Win10, macOS 11 | Pending |
| D-11 | Cryptographic signatures in scope | Phase 10 investigate; visual only v1 | Pending |
| D-12 | Strict offline + language downloads | User-initiated download only | Pending |

**Implementation must not begin** until D-01, D-02, D-03, D-05, and D-10 are **Confirmed** or waived in writing by the project owner.

---

## 31. Architecture Decision Records (initial set)

| ADR | Title | Status |
| --- | --- | --- |
| ADR-001 | Flutter as primary application framework | **Accepted** (per product brief) |
| ADR-002 | PDF rendering via PDFium (pdfrx ecosystem) | Proposed |
| ADR-003 | PDF structure via qpdf | Proposed |
| ADR-004 | OCR via Tesseract | Proposed |
| ADR-005 | Office conversion via LibreOffice headless (desktop) | Proposed |
| ADR-006 | State management library | Pending |
| ADR-007 | Android scanning without ML Kit dependency | Proposed |
| ADR-008 | Exclude Syncfusion as core PDF dependency | Proposed |
| ADR-009 | Exclude AGPL/Ghostscript/MuPDF from default stack | Proposed |

Full ADR text lives in `docs/DECISIONS.md` when created.

---

## 32. Feature specification template

Each file under `features/` must include:

- Feature ID, Name, Purpose, User story
- Supported platforms (matrix)
- Inputs / Outputs
- Functional requirements
- UI/UX requirements
- Processing architecture (engines, ports)
- Dependencies
- Error cases
- Security requirements
- Performance requirements
- Tests (with corpus references)
- Acceptance criteria
- Known limitations

---

## 33. Glossary

| Term | Definition |
| --- | --- |
| **AcroForm** | PDF interactive form fields |
| **Annotation** | PDF comment layer objects |
| **Fidelity class** | Conversion quality tier (section 15.1) |
| **Job** | Single runnable tool execution with progress |
| **Port** | Interface to an engine in infrastructure layer |
| **SAF** | Android Storage Access Framework |
| **Searchable PDF** | Image page + invisible text layer |
| **Tool** | Registered user-facing operation in registry |
| **True edit** | Modification of existing content streams |
| **Visual signature** | Appearance only, not PKCS#7/PAdES |

---

## Document control

| Version | Date | Author | Changes |
| --- | --- | --- | --- |
| 1.0.0 | 2026-09-26 | Architecture team | Initial master specification (Flutter, cross-platform) |

**Next review:** After confirmation of decisions D-01 through D-05 and D-10, or before Phase 0 coding starts.

---

*End of Master Project Specification*
