# Feature Checklist — Document Studio

Mark `[x]` when exit criteria in the feature spec are met (spec + architecture + UI + engine + tests + security/privacy review per [MASTER-SPECIFICATION.md](../docs/MASTER-SPECIFICATION.md) §60).

**Authoritative ID list:** [docs/FEATURE-INVENTORY.md](../docs/FEATURE-INVENTORY.md) (193 rows). This checklist mirrors every inventory ID.

**Status at spec time:** `[ ]` = not complete · Inventory codes: `[S]` specified · `[R]` research · `[X]` unsupported

## Blocking decisions (before Phase 0 code)

| ID | Decision | Status |
| --- | --- | --- |
| D-01 | PDFium / pdfrx viewer stack | [x] |
| D-02 | qpdf structure engine | [ ] (pdfrx structure + qpdf CLI package; FFI pending) |
| D-03 | Tesseract OCR | [ ] |
| D-05 | Office desktop-only v1 | [ ] |
| D-10 | Minimum OS versions | [ ] |

## Phase 0 — Foundation

| Item | Status |
| --- | --- |
| Flutter project (authorized) | [x] |
| Engine plugin packages | [ ] (pdfrx yes; document_studio_qpdf CLI yes; OCR package in progress) |
| Tool registry + JobRunner | [x] (JobRunner + ToolRegistry shell) |
| FileStoragePort | [x] |
| Design tokens v0 | [x] |
| CI analyze + unit tests | [ ] (local `flutter test` passes; CI workflow TBD) |
| Test corpus files | [x] (minimal `tests/corpus/simple_one_page.pdf`) |


## Phase 0 — Cross-cutting / QA / edge (inventory)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-EDGE-001` | Disk full handling | P0 | [S] | [ ] |
| `DS-EDGE-002` | Cancel long operations — **partial:** `JobRunner.requestCancel` + cancel token; UI cancel on organize/compress/batch; unit test `test/core/job_runner_cancel_test.dart`; gaps: isolate-backed jobs, full RULES gate | P0 | [S] | [ ] |
| `DS-EDGE-005` | File locked / permission denied | P0 | [S] | [ ] |
| `DS-EDGE-006` | Atomic save failure rollback | P0 | [S] | [ ] |
| `DS-PLAT-AND-001` | Android SAF/scoped storage | P0 | [S] | [ ] |
| `DS-PLAT-IOS-001` | iOS Files/security scope | P0 | [S] | [ ] |
| `DS-QA-001` | Unit test gate per feature | P0 | [S] | [ ] |
| `DS-QA-002` | Corpus PDF regression | P0 | [S] | [ ] |

## Phase 1 — PDF viewer + file shell
Spec: [DS-READ-PDF-VIEWER.md](../features/DS-READ-PDF-VIEWER.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-A11Y-001` | App accessibility | P0 | [ ] | [ ] |
| `DS-EDGE-007` | Memory pressure cache eviction | P1 | [ ] | [ ] |
| `DS-EDGE-009` | Corrupted PDF user messaging | P0 | [S] | [ ] |
| `DS-FILE-001` | Recent/favorites — **partial:** recents via `RecentFilesRepository` + `recentsProvider` (same as `DS-READ-001-B`); **favorites not implemented** (`DS-READ-001-C` open); prefs JSON not inventory “Local DB”; gaps: pin/unpin, `DS-FILE-002` search/sort, SAF URI in recents, full RULES gate; **no dedicated tests** (home smoke only in `test/widget_test.dart`) | P0 | [S] | [ ] |
| `DS-READ-001` | Open PDF | P0 | [S] | [ ] |
| `DS-READ-001-A` | Multi-document tabs | P1 | [S] | [ ] |
| `DS-READ-001-B` | Recent files — **partial:** `lib/core/storage/recent_files_repository.dart` (`recent_files_v1`, max 30, path + display name); `RecentsNotifier` / home **Recent documents** + empty state; `OrganizeRecentPdfsSection` on organize hub (PDFs, max 5); `addRecent` from home pickers, workspace/merge/workspace-tool/qpdf exports; tap PDF → `/workspace`, else viewer after `validateOpenable`; gaps: no `lastOpened`, missing-file UX, Android/iOS persistable URI, not all viewer opens record recents, full RULES gate; **repo/provider tests** `test/features/recents_provider_test.dart` (add, dedupe, max cap); home widget smoke only in `test/widget_test.dart` | P0 | [S] | [ ] |
| `DS-READ-001-C` | Favorites | P2 | [ ] | [ ] |
| `DS-READ-001-E` | Encrypted PDF open | P0 | [S] | [ ] |
| `DS-READ-002` | Page thumbnails strip | P0 | [S] | [ ] |
| `DS-READ-003-A` | Single page mode | P0 | [S] | [ ] |
| `DS-READ-003-B` | Continuous scroll | P0 | [S] | [ ] |
| `DS-READ-003-C` | Two page | P1 | [S] | [ ] |
| `DS-READ-004-A` | Fit page | P0 | [S] | [ ] |
| `DS-READ-004-B` | Fit width | P0 | [S] | [ ] |
| `DS-READ-004-D` | Custom zoom / pinch / wheel | P0 | [S] | [ ] |
| `DS-READ-004-E` | Double-tap zoom | P0 | [S] | [ ] |
| `DS-READ-005-A` | Rotate view temp | P1 | [S] | [ ] |
| `DS-READ-007-A` | Find in document | P0 | [S] | [ ] |
| `DS-READ-008-A` | Select/copy text | P0 | [S] | [ ] |
| `DS-READ-009-A` | Go to page | P0 | [S] | [ ] |
| `DS-READ-009-C` | First/prev/next/last — **partial:** `PdfViewerPageShortcuts` + `PdfViewerPageToolbarControls` on `PdfViewerScreen` (keyboard + toolbar → `navigatePdfViewerPage` / `PdfViewerController`); pdfrx `onKey` in `buildPdfViewerParams`; tests `pdf_viewer_page_shortcuts_test.dart`, `pdf_viewer_page_toolbar_controls_test.dart`; gap: full RULES gate | P0 | [S] | [ ] |
| `DS-READ-015` | Password UI | P0 | [S] | [ ] |
| `DS-SHELL-003` | Keyboard shortcuts | P0 | [S] | [ ] |
| `DS-UI-001` | Home quick tools — **partial:** `HomeScreen` hero CTAs (Open in workspace, New workspace, View PDF, All tools) + **Quick tools** grid (first 4 of `HomeScreen.buildToolCatalog` / `DsToolCard`); full 8-tool catalog on `ToolsHubScreen` (`/tools`); Scan/Convert `comingSoon` snackbar; shared catalog with tools hub; gaps: desktop drop zone, favorites/recents spec parity (§18.1), bundled sample PDF, tool-registry-driven catalog; widget smoke `test/widget_test.dart` (`Document Studio`, `New workspace`) | P0 | [S] | [ ] |
| `DS-UI-002` | Responsive shells — **partial:** `DsAppShell` on `StatefulShellRoute` (`app_router.dart`) — bottom nav `<600dp`, `NavigationRail` `600–1024`, extended rail `≥1024` (Home / Workspace / Tools / Settings); home + tools hub grid column breakpoints; gaps: unused legacy `ResponsiveShell` / `layoutSizeForWidth` (not routed); viewer/workspace/tablet inspector density under other IDs; no breakpoint/shell widget tests; full RULES gate | P0 | [S] | [ ] |

## Phase 2 — Page organization + viewer polish
Spec: [DS-ORG-PAGE-MANAGEMENT.md](../features/DS-ORG-PAGE-MANAGEMENT.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-BMK-001` | View bookmarks | P1 | [S] | [ ] |
| `DS-EDGE-003` | Password-protected pipeline — **partial:** `loadOrganizeImportPageCount` in `organize_pdf_import.dart` (`promptPdfPassword` + recursive retry like merge `_loadPageCount`, snack on wrong/cached-bad password + re-prompt) wired on organize/workspace import (`PageWorkspaceToolScreen`, `DocumentWorkspaceScreen`, merge append, crop/resize); unit tests `test/features/pdf_password_workflow_test.dart` (mock `loadInfo`, wrong-password loop, dialog smoke) + `test/infrastructure/page_organize_service_merge_test.dart` (`mergeAndPromptSave` forwards `passwordsByPath` + first-path `password` to `PdfStructurePort.merge`); gaps: encrypted export QA on all tools, full RULES gate | P0 | [S] | [ ] |
| `DS-LNK-001` | View/follow links | P1 | [S] | [ ] |
| `DS-ORG-001` | Merge PDFs (`/organize/merge`) — **partial:** UI, `PageOrganizeService.mergeAndPromptSave`, per-doc thumb + `showOrganizeExportPreview`, cancel via `JobRunner`; service test `test/infrastructure/page_organize_service_merge_test.dart` (mock `PdfStructurePort`, ordered merge, `passwordsByPath` passthrough); gaps: encrypted multi-file device/CLI QA, scale | P0 | [S] | [ ] |
| `DS-ORG-002` | Split PDF (`/organize/split`) — **partial:** `SplitToolScreen`, `split_plan.dart`, strip UI, export preview (all part pages in one dialog), cancel; unit tests `test/domain/split_plan_test.dart` (selected modes, export preview page list, engine ranges) + `test/infrastructure/page_organize_service_split_test.dart` (mock `splitByRanges` save paths); gaps: encrypted QA, full RULES gate; no bookmark mode (`DS-ORG-002-B` blocked) | P0 | [S] | [ ] |
| `DS-ORG-003` | Extract pages (`/organize/extract`) — **partial:** workspace UI + export preview + cancel; unit test `test/features/extract_pages_workflow_test.dart` (export page list when `exportSelectionOnly`; not full RULES gate) | P0 | [S] | [ ] |
| `DS-ORG-004` | Delete pages (`/organize/delete`) — **partial:** workspace UI + export preview + cancel; unit test `test/features/delete_pages_workflow_test.dart` (not full RULES gate) | P0 | [S] | [ ] |
| `DS-ORG-005` | Reorder pages (`/organize/reorder`, hub deep-link) — **partial:** workspace UI + export preview + cancel; also `/workspace` (see note below); unit test `test/features/reorder_pages_workflow_test.dart` (not full RULES gate) | P0 | [S] | [ ] |
| `DS-ORG-006` | Insert/replace/duplicate routes — **partial:** `PageWorkspaceToolScreen` configs + engine export; unit tests `test/features/duplicate_pages_workflow_test.dart` (duplicate export page count), `test/features/insert_replace_pages_workflow_test.dart` (`insertPagesFromFileAt` grows export count; `replaceSelectedFromFile` in-place count); not full RULES gate | P0 | [S] | [ ] |
| `DS-ORG-006-A` | Move between docs (`/organize/move-between`) — **partial:** dual-grid UI + preview + cancel; workspace ribbon **Move pages** handoff with `initialFiles`; unit test `test/features/move_between_workflow_test.dart` (destination page list assembly; not full RULES gate) | P1 | [S] | [ ] |
| `DS-ORG-006-B` | Add blank page (`/organize/blank-page`) — **partial:** `BlankPageFactory` + workspace insert; unit test `test/features/blank_page_workflow_test.dart` (`insertBlankAfterSelection`; not full RULES gate) | P0 | [S] | [ ] |
| `DS-ORG-007` | Rotate pages (`/organize/rotate`) — **partial:** workspace rotation + export preview + cancel; unit test `test/features/rotate_pages_workflow_test.dart` (rotateSelected degrees + export list; not full RULES gate) | P0 | [S] | [ ] |
| `DS-ORG-008` | Reverse order (`/organize/reverse`) — **partial:** workspace UI + export preview + cancel; unit test `test/features/reverse_pages_workflow_test.dart` (not full RULES gate) | P1 | [S] | [ ] |
| `DS-ORG-010` | Odd/even extract — **partial:** workspace odd/even export paths + cancel; unit test `test/features/odd_even_pages_workflow_test.dart` (not full RULES gate) | P1 | [S] | [ ] |
| `DS-ORG-014` | Preview before export — **partial:** `OrganizeExportPreviewDialog` on merge/split, workspace exports, and move-between; wide workspace thumb pane; no dedicated preview test — export lists covered by per-tool `*_workflow_test.dart` + `split_plan_test` / merge-split-export service tests (`page_organize_service_export_test.dart` mocks `assemblePageSources`); move-between / others not full spec parity (e.g. full thumb strip) | P1 | [ ] | [ ] |
| `DS-PRT-001` | Print PDF — **partial:** `PrintService` + `printing` package; viewer `PdfPrintButton` / shortcuts; workspace **`WorkspacePageToolbar`** Page format **Print** on primary imported PDF (`document_workspace_screen.dart`); gaps: print edited/exported workspace output, range/copies/scale, full RULES gate | P1 | [S] | [ ] |
| `DS-READ-003-D` | Two page continuous | P2 | [ ] | [ ] |
| `DS-READ-004-C` | Fit height | P2 | [ ] | [ ] |
| `DS-READ-006` | Fullscreen / presentation | P2 | [ ] | [ ] |
| `DS-READ-007-B` | Find next/prev highlight — **partial:** `PdfSearchMatchBar` match index label + prev/next tooltips/callbacks (disabled when no matches); widget test `test/features/pdf_search_match_bar_test.dart`; gaps: `PdfTextSearcher` highlight scroll in viewer, full RULES gate | P0 | [S] | [ ] |
| `DS-READ-008-B` | Select all text | P2 | [ ] | [ ] |
| `DS-READ-009-B` | Page slider | P2 | [ ] | [ ] |
| `DS-READ-010` | Bookmarks/outline panel | P1 | [S] | [ ] |
| `DS-READ-011` | Follow links | P1 | [S] | [ ] |
| `DS-READ-013` | Document properties — **partial:** `showDocumentProperties` dialog/sheet (title, author, pages via `PdfRenderPort.loadInfo`) from viewer info action; `PdfrxRenderAdapter.loadInfo` reads Title/Author via PDFium (`pdfrx_document_metadata.dart`); widget test `test/features/document_properties_dialog_test.dart`; adapter/metadata tests `test/infrastructure/pdfrx_adapter_test.dart` + `pdfrx_document_metadata_test.dart` (native PDFium skipped in VM); corpus `tests/corpus/with_document_metadata.pdf`; gaps: encrypted/size fields, full RULES gate | P0 | [S] | [ ] |
| `DS-READ-014` | Print | P1 | [S] | [ ] |

**`DS-ORG-005` + `/workspace` (Acrobat-style UX refactor):** **sidebar** = open PDF list + Add/Insert only. **`WorkspacePageToolbar`** = full catalog in four labeled groups (Page composition, Extract & split, Arrange pages, Page format) — icon + caption per action; merge/split/crop/resize/reorder tool handoffs on ribbon. **`OrganizeDocumentSourceChips`** when sidebar hidden. **`WorkspaceInspectorPanel`** on wide layouts. Not `[x]` until full RULES gate per `DS-ORG-*`.

Organize (verified 2026-09-26): tool-first `/organize/*` + unified **`/workspace`** (`DocumentWorkspaceScreen`, isolated `documentWorkspaceProvider`) in `lib/features/page_management/` and `lib/features/document_workspace/`. Engine: `PageOrganizeService` + `PdfStructurePort`. **No `DS-ORG-*` Done column is `[x]`** until full exit gate (spec + architecture + UI + engine + tests per `DS-QA-001` + security/privacy review per MASTER-SPEC §60); partial workflow/service tests below do **not** satisfy the gate. Encrypt/SAF QA and full preview/cancel sign-off on export jobs remain unsigned.

**Organize test inventory (partial coverage only):**

| Layer | Test file | Maps to |
| --- | --- | --- |
| Workflow | `test/features/delete_pages_workflow_test.dart` | `DS-ORG-004` |
| Workflow | `test/features/extract_pages_workflow_test.dart` | `DS-ORG-003` |
| Workflow | `test/features/reorder_pages_workflow_test.dart` | `DS-ORG-005` |
| Workflow | `test/features/rotate_pages_workflow_test.dart` | `DS-ORG-007` |
| Workflow | `test/features/reverse_pages_workflow_test.dart` | `DS-ORG-008` |
| Workflow | `test/features/odd_even_pages_workflow_test.dart` | `DS-ORG-010` |
| Workflow | `test/features/duplicate_pages_workflow_test.dart` | `DS-ORG-006` (duplicate) |
| Workflow | `test/features/insert_replace_pages_workflow_test.dart` | `DS-ORG-006` (insert/replace) |
| Workflow | `test/features/blank_page_workflow_test.dart` | `DS-ORG-006-B` |
| Workflow | `test/features/move_between_workflow_test.dart` | `DS-ORG-006-A` |
| Domain | `test/domain/split_plan_test.dart` | `DS-ORG-002`, `DS-ORG-002-A` |
| Service | `test/infrastructure/page_organize_service_merge_test.dart` | `DS-ORG-001` |
| Service | `test/infrastructure/page_organize_service_split_test.dart` | `DS-ORG-002`, `DS-ORG-002-A` |
| Service | `test/infrastructure/page_organize_service_export_test.dart` | workspace export (`assemblePageSources` order, rotation, `passwordsByPath` → password); shared engine path for `DS-ORG-003`–`DS-ORG-010`, `/workspace` |
| Workspace / hub | `test/features/organize_workspace_notifier_test.dart`, `organize_page_grid_test.dart`, `organize_screen_test.dart`, `workspace_page_toolbar_test.dart`, `document_workspace_test.dart` | shared workspace / `DS-ORG-005` shell |
| Widget smoke | `test/features/*_tool_screen_test.dart` (merge, split, extract, delete, reorder, rotate, reverse, duplicate, insert, replace, blank, odd/even, …) | mount + primary actions only |

Adapter merge integration test remains skipped without PDFium. **`DS-ORG-002-B` (bookmark split) and content scaling on resize stay out of scope / blocked** — do not mark Done until engine supports outlines and scaling policy is defined.

## Phase 3 — Creation, compress, image, conversion (core)
Spec: Compress/CNV/Image specs

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-CNV-001` | Images to PDF | P0 | [S] | [ ] |
| `DS-CNV-002` | PDF to images | P0 | [S] | [ ] |
| `DS-CNV-FMT-005` | JPG/JPEG to PDF | P0 | [S] | [ ] |
| `DS-CNV-FMT-006` | PNG to PDF | P0 | [S] | [ ] |
| `DS-CNV-FMT-007` | WEBP to PDF | P1 | [S] | [ ] |
| `DS-CNV-FMT-008` | TIFF to PDF | P1 | [ ] | [ ] |
| `DS-CNV-FMT-009` | BMP to PDF | P2 | [ ] | [ ] |
| `DS-CNV-FMT-013` | PDF to JPG/PNG/WEBP/TIFF | P0 | [S] | [ ] |
| `DS-CREATE-001` | Images to PDF | P0 | [S] | [ ] |
| `DS-CREATE-002` | Text to PDF | P1 | [ ] | [ ] |
| `DS-CREATE-005` | Blank PDF | P1 | [ ] | [ ] |
| `DS-FILE-002` | Search/sort/filter | P2 | [ ] | [ ] |
| `DS-HDR-001` | Headers/footers | P1 | [ ] | [ ] |
| `DS-IMG-001` | Image viewer | P1 | [S] | [ ] |
| `DS-IMG-002` | Convert/resize/crop/rotate | P1 | [S] | [ ] |
| `DS-IMG-003` | Compress/exif strip | P1 | [S] | [ ] |
| `DS-META-001` | View/edit metadata | P1 | [S] | [ ] |
| `DS-META-002` | Remove all metadata | P1 | [S] | [ ] |
| `DS-OPT-001` | Compress profiles | P0 | [S] | [ ] |
| `DS-OPT-001-A` | Lossless stream optimize | P0 | [S] | [ ] |
| `DS-OPT-005` | Size statistics | P0 | [S] | [ ] |
| `DS-ORG-002-A` | Split every N pages — **partial:** covered by `/organize/split` + `SplitMethodKind.everyN`; tests `test/domain/split_plan_test.dart` (every-N modes) + `test/infrastructure/page_organize_service_split_test.dart`; same exit gaps as `DS-ORG-002` | P1 | [S] | [ ] |
| `DS-PGN-001` | Page numbering | P1 | [ ] | [ ] |
| `DS-PLAT-DESK-001` | Desktop DnD/associations | P1 | [S] | [ ] |
| `DS-PRT-002` | Print images | P2 | [ ] | [ ] |
| `DS-READ-001-D` | Open-with / file association | P1 | [S] | [ ] |
| `DS-READ-009-D` | Back/forward nav | P2 | [ ] | [ ] |
| `DS-SEC-005` | Metadata removal | P1 | [S] | [ ] |
| `DS-SHELL-002` | Command palette | P2 | [S] | [ ] |
| `DS-SHELL-007` | Strict offline mode | P1 | [S] | [ ] |
| `DS-SHELL-008` | Privacy dashboard | P1 | [S] | [ ] |
| `DS-VIEW-005` | Dark canvas mode | P3 | [ ] | [ ] |
| `DS-WTM-001` | Text/image watermark | P1 | [ ] | [ ] |
| `DS-WTM-002` | Page range/odd/even | P2 | [ ] | [ ] |

## Phase 4 — Annotations
Spec: [DS-ANN-ANNOTATION.md](../features/DS-ANN-ANNOTATION.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-ANN-001` | Text markup | P0 | [S] | [ ] |
| `DS-ANN-002` | Sticky note/comment | P0 | [S] | [ ] |
| `DS-ANN-003` | Text box/callout | P1 | [S] | [ ] |
| `DS-ANN-004` | Ink/pen/pencil/eraser | P1 | [S] | [ ] |
| `DS-ANN-005` | Stamps/custom/date | P1 | [S] | [ ] |
| `DS-ANN-006` | Annotation list/search/filter | P1 | [S] | [ ] |

## Phase 5 — Content editing
Spec: [DS-EDIT-CONTENT.md](../features/DS-EDIT-CONTENT.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-EDIT-001` | Add text | P1 | [S] | [ ] |
| `DS-EDIT-002` | Edit existing text | P2 | [S] | [ ] |
| `DS-EDIT-003` | Image objects CRUD | P1 | [S] | [ ] |
| `DS-EDIT-004` | Shapes/paths/freehand objects | P1 | [S] | [ ] |
| `DS-EDIT-006` | Font/style/alignment/spacing | P1 | [ ] | [ ] |
| `DS-EDIT-007` | Z-order/group/align | P2 | [ ] | [ ] |
| `DS-SHELL-009` | Undo/redo | P0 | [S] | [ ] |
| `DS-SHELL-010` | Autosave recovery | P1 | [S] | [ ] |

## Phase 6 — OCR + scanner
Spec: [DS-OCR-SCAN.md](../features/DS-OCR-SCAN.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-CNV-003` | TXT/MD/HTML to PDF | P2 | [S] | [ ] |
| `DS-CNV-006` | PDF to TXT/HTML/MD | P1 | [S] | [ ] |
| `DS-CREATE-004` | Markdown to PDF | P2 | [ ] | [ ] |
| `DS-CREATE-006` | Scan/camera to PDF | P1 | [S] | [ ] |
| `DS-CREATE-007` | Clipboard to PDF | P3 | [ ] | [ ] |
| `DS-CREATE-008` | Screenshot to PDF | P3 | [ ] | [ ] |
| `DS-IMG-004` | HEIC/GIF/SVG | P2 | [R] | [ ] |
| `DS-OCR-001` | Image OCR | P0 | [S] | [ ] |
| `DS-OCR-002` | Searchable PDF | P0 | [S] | [ ] |
| `DS-OCR-003` | Language packs | P1 | [S] | [ ] |
| `DS-OCR-004` | Preprocess deskew/denoise | P1 | [S] | [ ] |
| `DS-OCR-006` | OCR preview/correction | P2 | [ ] | [ ] |
| `DS-SCAN-001` | Camera scanner | P1 | [S] | [ ] |
| `DS-SCAN-002` | Perspective/deskew/enhance | P1 | [S] | [ ] |
| `DS-SCAN-003` | Multi-page scan session | P1 | [S] | [ ] |
| `DS-SCAN-004` | Scan to searchable PDF | P1 | [S] | [ ] |

## Phase 7 — Security + redaction
Spec: [DS-SEC-SECURITY.md](../features/DS-SEC-SECURITY.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-EDGE-004` | Decompression bomb limits | P0 | [ ] | [ ] |
| `DS-OPT-001-B` | Lossy image reencode | P1 | [S] | [ ] |
| `DS-OPT-002` | DPI/image downsampling | P1 | [S] | [ ] |
| `DS-OPT-003` | Grayscale/mono | P2 | [S] | [ ] |
| `DS-OPT-004` | Font/object cleanup | P2 | [S] | [ ] |
| `DS-RED-001` | Mark text/image/region | P1 | [S] | [ ] |
| `DS-RED-002` | Residual content scan | P2 | [ ] | [ ] |
| `DS-SEC-001` | Encrypt/passwords | P0 | [S] | [ ] |
| `DS-SEC-002` | Permission flags | P0 | [S] | [ ] |
| `DS-SEC-003` | Unlock with password | P0 | [S] | [ ] |
| `DS-SEC-004` | Permanent redaction | P1 | [S] | [ ] |
| `DS-VIEW-003` | JavaScript detection | P1 | [ ] | [ ] |
| `DS-VIEW-004` | Launch action warning | P1 | [ ] | [ ] |

## Phase 8 — Forms + signatures
Spec: [DS-FORM-SIGN.md](../features/DS-FORM-SIGN.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-ANN-007` | Flatten annotations | P1 | [ ] | [ ] |
| `DS-EDGE-008` | XFA form warning | P1 | [ ] | [ ] |
| `DS-FORM-001` | Detect/fill fields | P1 | [S] | [ ] |
| `DS-FORM-002` | Flatten forms | P1 | [S] | [ ] |
| `DS-SIG-001` | Visual signature | P1 | [S] | [ ] |

## Phase 9 — Office conversion (desktop)
Spec: [DS-CNV-OFFICE.md](../features/DS-CNV-OFFICE.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-CNV-FMT-001` | DOC to PDF | P1 | [S] | [ ] |
| `DS-CNV-FMT-002` | DOCX to PDF | P0 | [S] | [ ] |
| `DS-CNV-FMT-003` | XLS/XLSX to PDF | P1 | [S] | [ ] |
| `DS-CNV-004` | Office to PDF | P0 | [S] | [ ] |
| `DS-CNV-004` | Office to PDF | P0 | [S] | [ ] |
| `DS-CNV-FMT-004` | PPT/PPTX to PDF | P1 | [S] | [ ] |
| `DS-CNV-005` | PDF to Office | P1 | [S] | [ ] |
| `DS-CNV-FMT-010` | PDF to DOCX | P1 | [S] | [ ] |
| `DS-CREATE-003` | HTML to PDF | P2 | [R] | [ ] |

## Phase 10 — Compare, repair, PDF/A, advanced
Spec: [DS-ADV-PDF.md](../features/DS-ADV-PDF.md)

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-ADV-001` | Compare PDFs | P2 | [S] | [ ] |
| `DS-ADV-002` | Repair/validate | P2 | [S] | [ ] |
| `DS-ADV-003` | PDF/A convert+validate | P2 | [R] | [ ] |
| `DS-ANN-008` | Reply threads | P3 | [ ] | [ ] |
| `DS-ATT-001` | View attachments | P2 | [S] | [ ] |
| `DS-ATT-002` | Add/remove/extract | P2 | [S] | [ ] |
| `DS-BMK-002` | CRUD/nest/reorder | P2 | [S] | [ ] |
| `DS-CNV-007` | PDF to Markdown | P2 | [ ] | [ ] |
| `DS-CNV-FMT-011` | PDF to XLSX | P2 | [ ] | [ ] |
| `DS-CNV-FMT-012` | PDF to PPTX | P3 | [ ] | [ ] |
| `DS-CREATE-009` | PDF/A on create | P2 | [R] | [ ] |
| `DS-EDIT-005` | Find replace | P2 | [S] | [ ] |
| `DS-FORM-003` | Create/edit fields | P2 | [S] | [ ] |
| `DS-FORM-004` | Tab order/validation/required | P2 | [ ] | [ ] |
| `DS-FORM-005` | Import/export form data | P3 | [R] | [ ] |
| `DS-LNK-002` | Create/edit/delete links | P2 | [S] | [ ] |
| `DS-ORG-002-B` | Split by bookmarks (blocked — no engine outline parser) | P2 | [ ] | [ ] |
| `DS-ORG-002-C` | Split by size | P3 | [R] | [ ] |
| `DS-ORG-011` | Blank page detect/remove | P2 | [ ] | [ ] |
| `DS-ORG-012` | Crop page boxes — **partial:** `/organize/crop` (`PageBoxQpdfToolScreen`) + qpdf margin presets when CLI available; export preview + cancel via `JobRunner`; gaps: interactive crop box, no feature test; not checklist-complete | P2 | [S] | [ ] |
| `DS-ORG-013` | Resize/orientation media box — **partial:** `/organize/resize` (`PageBoxQpdfToolScreen`) sets MediaBox only (**no content scaling**); qpdf CLI; export preview + cancel via `JobRunner`; gaps: content scale path blocked, no feature test; not checklist-complete | P2 | [S] | [ ] |
| `DS-PGN-002` | Bates numbering | P2 | [ ] | [ ] |
| `DS-PREF-001` | Preflight/properties | P2 | [ ] | [ ] |
| `DS-READ-012` | Attachments panel | P2 | [S] | [ ] |
| `DS-SIG-002` | Cryptographic sign | P2 | [R] | [ ] |
| `DS-SIG-003` | Validate signatures | P2 | [R] | [ ] |
| `DS-VIEW-001` | Page labels display | P2 | [ ] | [ ] |
| `DS-VIEW-002` | Optional layers OCG | P3 | [R] | [ ] |

## Phase 11 — Batch processing

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-BATCH-001` | Batch runner | P1 | [S] | [ ] |
| `DS-EDGE-010` | Partial batch success report | P1 | [S] | [ ] |
| `DS-FILE-003` | Batch rename/delete | P2 | [ ] | [ ] |
| `DS-IMG-005` | Batch image tools | P1 | [ ] | [ ] |
| `DS-META-003` | Batch metadata | P2 | [ ] | [ ] |
| `DS-OCR-005` | Batch OCR | P1 | [S] | [ ] |
| `DS-ORG-015` | Batch organization | P1 | [S] | [ ] |

## Phase 12 — Workflow / action engine

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-FLOW-001` | Workflow engine | P2 | [S] | [ ] |

## Phase 13 — Accessibility + professional tooling

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-A11Y-002` | PDF tagging inspection | P2 | [R] | [ ] |
| `DS-A11Y-003` | PDF/UA validation | P3 | [R] | [ ] |
| `DS-BMK-003` | Generate from headings | P3 | [R] | [ ] |

## Phase 14 — Performance + hardening

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-QA-004` | Security malformed PDF suite | P1 | [ ] | [ ] |
| `DS-QA-005` | Performance benchmarks | P1 | [S] | [ ] |

## Phase 15 — Cross-platform release

| ID | Feature | Pri | Inv | Done |
| --- | --- | --- | --- | --- |
| `DS-QA-003` | Cross-platform smoke | P0 | [ ] | [ ] |

---

**Documentation pack:** specification phase complete (2026-09-26).
**Parity / matrix / gaps:** [FEATURE-PARITY.md](../docs/FEATURE-PARITY.md) · [FEATURE-MATRIX.md](../docs/FEATURE-MATRIX.md) · [FEATURE-GAPS.md](../docs/FEATURE-GAPS.md) · [UNSUPPORTED-FEATURES.md](../docs/UNSUPPORTED-FEATURES.md)
**Last updated:** 2026-09-26 (Phase 1 home/recents/shell rows reconciled; organize tools prior)
