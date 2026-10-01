# Feature Gaps — Audit vs Repository (2026-09-27)

Comparison of **user-requested exhaustive scope** (prompt §7–48) against **existing** docs/specs before this audit.

**Legend:** **Closed** = now in FEATURE-INVENTORY / expanded checklist · **Open** = still needs spec/engine work · **Partial** = high-level only

**Parity buckets (honest vs iLovePDF + Acrobat Pro local workflows):**

| Bucket | Implemented | Partial | Missing / blocked |
| --- | --- | --- | --- |
| **View / read** | Offline viewer, tabs, find, links, bookmarks panel, presentation stub, document properties → metadata; Home **Open PDF** chooser (View / Edit pages / Compress / Protect) + recents last mode | Two-page continuous, fit height, full-screen OS immersive, annotation authoring | OCG layers, JS execution, shared review |
| **Organize pages** | `/organize` hub (16 tools), `/workspace` multi-PDF grid, export preview + cancel, viewer File/Tools menus + canvas context menu handoffs, password on `OrganizeToolLaunch` | Every tool route partial vs `DS-ORG-*`; ribbon manual mirror; crop/resize qpdf presets only; merge encrypted QA | Split by bookmarks (`DS-ORG-002-B` engine); resize content scaling; interactive crop |
| **Create / convert** | Images/text→PDF, PDF→images, compress profiles, scan → images-to-pdf handoff | Office convert (`/office-convert` blocked, no snackbar stubs); PDF→Office fidelity; HTML→PDF research | Cloud convert parity |
| **Protect / metadata** | Protect, unlock, edit/remove metadata with viewer handoff | Batch metadata, XMP depth | Enterprise IRM / Purview |
| **Markup** | Headers/footers, watermark, page numbers routes | Bates full spec, flatten pipeline | Full stamp/redaction Acrobat parity |
| **Sign** | `/sign/visual` + `/forms/fill` honest routes (partial/blocked) | Visual sign via watermark partial | PAdES / remote track (cloud) |
| **OCR** | Routes; desktop **`tesseract` CLI** when on PATH; status panel + probe | Searchable PDF pipeline; tessdata bundle/FFI | iLovePDF cloud OCR parity |
| **Batch / automation** | Batch route, command palette | Saved workflows depth | Action Wizard–level macros |
| **Platform** | Strict offline, desktop organize | Android SAF QA, Linux print | Virtual system PDF printer |
| **Cloud / AI** | — | — | E-sign tracking, AI summarize, cloud drive (intentional **Missing**) |

See [FEATURE-PARITY.md](FEATURE-PARITY.md) and [FEATURE-MATRIX.md](FEATURE-MATRIX.md) for row-level detail.

---

## PDF gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Opening: CLI args, corrupted/huge cancel | Partial in DS-READ | Closed in inventory DS-VIEW-* |
| View: two-page continuous, fit height, presentation | Partial | Closed |
| Navigation: back/forward, named destinations, page slider | Missing | Closed |
| Structures: layers (OCG), page labels, JS detection | Missing | Closed [R]/inventory |
| Bates numbering | Missing | Closed P2 |

## Editing gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Paragraph/line/char spacing, find-replace | Partial | Closed |
| Object z-order, group/align/distribute | Missing | Closed P2 |
| Rulers, alignment guides | Missing | Closed P2 |
| True vs overlay taxonomy | In EDITOR-ARCH | Closed + inventory |

## Annotation gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Cloud, polygon, eraser, stamp variants | Partial | Closed |
| Annotation search/filter, replies | Missing | Closed P2 |
| Flatten annotations | Mentioned | Closed |

## Conversion gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Per-converter fidelity matrix | CONVERSION-ENGINE classes | Closed FEATURE-INVENTORY |
| PDF→MD, clipboard/screenshot to PDF | Missing | Closed |
| EPUB, PDF/X | Not listed | Open P3 |

## OCR gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Hindi/Indic explicit | Not listed | Closed (tessdata) |
| OCR correction UI, confidence | Missing | Closed P2 |
| Batch OCR | Phase 11 | Closed |

## Security gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| AES revision matrix, inspect security | Partial | Closed |
| Residual-content scan after redact | SECURITY.md | Closed in inventory |

## Forms gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Form creation, validation, tab order, calc | Phase 10 partial | Closed P2 in inventory |
| Import/export FDF/XFDF | Missing | Open P2 |

## Signature gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| PAdES levels, cert store, validation | ADR-010 | Closed [R] |

## Scanning gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Auto-capture, flash, retake page | Partial DS-OCR-SCAN | Closed expanded |
| Background removal | Mentioned | Closed |

## Image studio gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| HEIC, GIF, adjust brightness/contrast | Partial IMAGE-ENGINE | Closed |
| EXIF inspect | Missing | Closed |

## Watermark / header / footer / page numbering

| Gap | Prior state | After audit |
| --- | --- | --- |
| Dedicated module specs | Only Phase 3 mention | Closed MODULE in inventory |
| Bates vs page numbers | Missing | Closed |

## File management gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| In-app file browser, favorites, batch rename | SHELL partial | Closed MOD-FILE |

## Batch / workflow gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Recursive folders, templates, import/export workflow | Partial BATCH spec | Closed |

## UX gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Home quick tools grid exhaustive | UI-UX partial | Closed inventory MOD-UI |
| Command palette details | Mentioned | Closed |

## Accessibility gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Tag tree, remediation, PDF/UA check | Not in roadmap | **Open** Phase 13 |
| Flutter a11y for app chrome | NFR only | Closed in inventory |

## Platform gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Linux Wayland, split-screen Android | PLATFORM-INTEG partial | Closed matrix |
| Virtual printer | Not documented | Closed UNSUPPORTED |

## Testing gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Corpus file list exhaustive | README partial | Closed tests/corpus + TESTING |
| Security/perf test categories | TESTING.md | Closed |

## Release gaps

| Gap | Prior state | After audit |
| --- | --- | --- |
| Store packaging matrix | RELEASE.md | Closed |
| F-Droid / no-GMS Android | Not listed | Open P2 release |

## Documentation gaps (meta)

| Gap | Prior state | After audit |
| --- | --- | --- |
| FEATURE-INVENTORY.md | Missing | **Closed this audit** |
| FEATURE-MATRIX.md | Missing | Closed |
| FEATURE-PARITY.md | Missing | Closed |
| Expanded CHECKLIST | ~126 lines | Closed expanded file |
| Phases 13–15 roadmap | Phases 0–12 only | Closed ROADMAP update |

## Organize (implementation vs spec — reconciled 2026-09-26)

| Gap | State |
| --- | --- |
| Viewer → tool handoffs (menus + context menu) | **Partial** — `PdfViewerFileMenuButton`, `PdfViewerToolsMenuButton`, `PdfViewerDocumentToolsMenu`, `OrganizeToolLaunch` + workspace `parseWorkspaceRouteExtra`; gaps: merge multi-file from viewer, full menu QA |
| Viewer → tool handoffs (menus + context menu) | **Partial** — `PdfViewerFileMenuButton`, `PdfViewerToolsMenuButton`, `PdfViewerDocumentToolsMenu`, `OrganizeToolLaunch` + workspace `parseWorkspaceRouteExtra`; gaps: merge multi-file from viewer, full menu QA |
| Tool-first `/organize/*` routes (merge, split, workspace tools) | **Partial** — 16 catalog tools routed; `PageOrganizeService` + `PdfStructurePort`; checklist `[ ]` until spec exit + per-feature tests |
| Unified document workspace `/workspace` | **Partial** — `DocumentWorkspaceScreen` + `documentWorkspaceProvider` (same grid/export/preview/cancel as organize workspace); sidebar links to merge/split/hub |
| Document-level merge (`DS-ORG-001`) | **Partial** — `MergeToolScreen`, file reorder, per-doc preview pane, `showOrganizeExportPreview`, `JobRunner` cancel; gaps: encrypted multi-file QA, scale, no service merge test |
| Split every N / per-page / custom / selected (`DS-ORG-002`, `DS-ORG-002-A`) | **Partial** — `SplitToolScreen` + `split_plan.dart` + strip UI; export preview lists all output pages; cancel wired; no split engine regression test in repo |
| Preview before export (`DS-ORG-014`) | **Partial** — `showOrganizeExportPreview` on merge/split/move-between and all `PageWorkspaceToolScreen` exports; wide **`WorkspaceInspectorPanel`** on `/workspace` and tool routes |
| Workspace tools (extract/delete/reorder/rotate/…) | **Partial** — `PageWorkspaceToolScreen` + export preview + cancel on main path; no `DS-QA-001` gate per ID |
| Move between documents (`DS-ORG-006-A`) | **Partial** — dual-grid UI + `showOrganizeExportPreview` + `JobRunner` cancel + step strip / status bar |
| Split by bookmarks (`DS-ORG-002-B`) | **Blocked** — no bookmark/outline enumeration on PDF ports ([PDF-ENGINE.md](PDF-ENGINE.md)); **do not checklist** |
| Crop / resize (`DS-ORG-012`, `DS-ORG-013`) | **Partial** — `/organize/crop` and `/organize/resize` (`PageBoxQpdfToolScreen`); qpdf CLI + step strip / export preview / cancel; resize MediaBox only (**no content scaling**) |
| Blank page insert (`DS-ORG-006-B`) | **Partial** — `/organize/blank-page` + `BlankPageFactory`; no feature test |
| Document source chips on organize tool workspace | **Partial** — `OrganizeDocumentSourceChips` on `/workspace` (compact) + `PageWorkspaceToolScreen` when `allowAddPdf` and 2+ PDFs |
| Document source chips on organize tool workspace | **Partial** — `OrganizeDocumentSourceChips` on `/workspace` (compact) + `PageWorkspaceToolScreen` when `allowAddPdf` and 2+ PDFs |
| Organize automated tests | **Partial** — unit/widget: `split_plan_test`, workspace notifier/grid, hub widget, workspace empty state; `pdfrx_structure_test` merge skipped without PDFium; no end-to-end organize corpus suite |

## Still open (requires implementation or deep research)

- HTML→PDF engine choice on all platforms
- PDF→Office engine beyond LO/heuristics
- PdfAnnotationPort implementation path (pdfrx vs FFI)
- Crypto signature library (MIT/Apache)
- PDF/UA tagging tooling depth
- HEIC on Linux
- Form calculation JavaScript subset

Update this file when gaps close.
