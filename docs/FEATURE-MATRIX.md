# Feature Matrix — Document Studio

Platform symbols: **✅** Supported · **⚠️** Limited · **❌** Unsupported · **🔬** Research required

**Offline** = core path works without network. **Batch** = batch runner planned.

| Feature | Android | iOS | iPadOS | Windows | macOS | Linux | Offline | Batch | Tested |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PDF viewer / navigation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | — | [ ] (partial: continuous + single-page pdfrx layout toggle; not full DS-READ-003 exit) |
| Text search / copy | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | — | [ ] |
| Merge / split / organize | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | Yes | ✅ | [ ] |
| Compress PDF | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Image ↔ PDF | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] (partial: `/images-to-pdf` multi-image → PDF via pdfrx; not full CNV exit) |
| TXT/MD → PDF | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| HTML → PDF | 🔬 | 🔬 | 🔬 | ⚠️ | ⚠️ | ⚠️ | Yes | ⚠️ | [ ] |
| Office → PDF | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| PDF → Office | ❌ | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | Yes | ⚠️ | [ ] |
| OCR / searchable PDF | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Hindi/Indic OCR | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | Yes | ✅ | [ ] |
| Camera scan → PDF | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | Yes | ⚠️ | [ ] |
| Annotations | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ⚠️ | [ ] |
| Content edit (add/true) | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ❌ | [ ] |
| Form fill | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ⚠️ | [ ] |
| Form authoring | 🔬 | 🔬 | ⚠️ | ✅ | ✅ | ✅ | Yes | ❌ | [ ] |
| Visual signature | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ⚠️ | [ ] |
| Crypto digital sign | 🔬 | 🔬 | 🔬 | 🔬 | 🔬 | 🔬 | Yes | ❌ | [ ] |
| Encrypt / permissions | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Permanent redaction | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ⚠️ | [ ] |
| Watermark / page numbers | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Bates numbering | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Metadata edit/strip | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Compare PDFs | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ❌ | [ ] |
| Repair PDF | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ⚠️ | [ ] |
| PDF/A convert/validate | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | Yes | ⚠️ | [ ] |
| Bookmarks/links edit | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ❌ | [ ] |
| Attachments | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ⚠️ | [ ] |
| Print | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | — | [ ] |
| Batch processing | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Workflows | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| Strict offline mode | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | — | [ ] |
| Image studio | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | ✅ | [ ] |
| HEIC import | ⚠️ | ✅ | ✅ | 🔬 | ✅ | 🔬 | Yes | ⚠️ | [ ] |
| Accessibility app UI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Yes | — | [ ] (partial: workspace ribbon keyboard focus order; not full DS-A11Y-001) |
| PDF/UA tagging tools | 🔬 | 🔬 | 🔬 | 🔬 | 🔬 | 🔬 | Yes | ❌ | [ ] |
| Virtual system PDF printer | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — | — | [X] |
| Cloud sign tracking | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | No | — | [X] |
| AI document features | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — | — | [X] |

## Organize & workspace — implementation (partial)

Platform **⚠️** on the summary row means routes and engine paths exist on all targets, but **no `DS-ORG-*` checklist row is `[x]`** and **Tested** stays `[ ]` until [TESTING.md](TESTING.md) sign-off (see [.ai/CHECKLIST.md](../.ai/CHECKLIST.md)).

| Capability | Where | Shipped | Gaps (honest) | Tested |
| --- | --- | --- | --- | --- |
| Unified document workspace | `/workspace` — `DocumentWorkspaceScreen`, `documentWorkspaceProvider` (isolated from `/organize/*` workspace state) | **Partial** — Home, recents, command palette; multi-PDF import, export preview + job cancel; sidebar = open PDF list + add/insert; wide `WorkspaceInspectorPanel` | Not spec-complete vs `DS-SHELL-001`; page actions live on ribbon (see row below); no multi-doc corpus QA | [ ] |
| Workspace page ribbon (full catalog grouping) | `/workspace` — `WorkspacePageToolbar`; group captions from `OrganizeToolCatalog.groupTitle` (Page composition, Extract & split, Arrange pages, Page format) | **Partial** — icon + label segments for all 16 catalog capabilities (merge through resize); selection cluster; Insert menu; in-workspace delete/duplicate/rotate/reverse/odd-even/extract + handoffs to `/organize/*` (merge, split, reorder, insert, move-between, crop, resize) | **Not** generated from `OrganizeToolCatalog.tools` (manual mirror — e.g. Split under composition on ribbon vs extraction in hub); rotate CCW/180° ribbon-only vs single rotate tool route; crop/resize qpdf box edits only (no interactive crop; resize without content scale); no per-handoff QA; `workspace_page_toolbar_test` smoke only | [ ] |
| Merge + export preview | `/organize/merge` — `MergeToolScreen` | **Partial** — file list merge, in-screen per-file thumb pane, `showOrganizeExportPreview`, `JobRunner` cancel | Encrypted multi-file QA, large merge scale, no service-level merge test | [ ] |
| Split + export preview | `/organize/split` — `SplitToolScreen`, `split_plan.dart` | **Partial** — every N / custom / selected modes, strip UI, export preview (combined output pages), cancel | Bookmark split (`DS-ORG-002-B`) blocked; no split engine regression in repo | [ ] |
| Move between + preview | `/organize/move-between` — `MoveBetweenToolScreen` | **Partial** — dual grids, `showOrganizeExportPreview` (first/last thumbs + page order), cancel on active job | Not full `DS-ORG-014` spec parity; no feature/corpus test | [ ] |
| Crop pages (qpdf) | `/organize/crop` — `CropToolScreen` → `PageBoxQpdfToolScreen` | **Partial** — margin presets (CropBox), `showOrganizeExportPreview`, `JobRunner` cancel | Requires qpdf CLI + `supportsPageBoxEditing`; preset margins only (not visual crop rect); logic `crop_resize_workflow_test.dart`; service mock `page_organize_service_page_box_export_test.dart` (encrypted password passthrough); no corpus QA | [ ] |
| Resize pages (qpdf) | `/organize/resize` — `ResizeToolScreen` → `PageBoxQpdfToolScreen` | **Partial** — paper size (MediaBox), export preview, `JobRunner` cancel | **No content scaling** (`DS-ORG-013`); qpdf CLI; same service/logic tests as crop | [ ] |
| Extract (route wrapper) | `/organize/extract` → `ExtractToolScreen` → `PageWorkspaceToolScreen` (`extract`) | **Partial** — same workspace chrome as reorder/delete; selection export + preview + cancel | Widget mount test only; no extract corpus QA | [ ] |
| Reorder (route wrapper) | `/organize/reorder` → `ReorderToolScreen` | **Partial** — drag/move reorder + `showOrganizeExportPreview` + cancel | `reorder_pages_workflow_test.dart` + `reorder_tool_screen_test.dart`; no corpus QA | [ ] |
| Odd / even (route wrappers) | `/organize/odd-pages`, `/organize/even-pages` → `OddEvenToolScreen` | **Partial** — `PageWorkspaceToolScreen` odd/even export paths + preview + cancel | Widget mount tests only; no corpus QA | [ ] |
| Document source chips | `OrganizeDocumentSourceChips` on **`/workspace`** (compact) + **`PageWorkspaceToolScreen`** when `allowAddPdf` and 2+ PDFs | **Partial** | Single-file organize routes omit chips; no dedicated chip widget test | [ ] |

Tool-first **`/organize/*`** (hub + 16 catalog routes) shares `PageOrganizeService` + `PdfStructurePort` with the workspace above; the hub lists the same four groups as the ribbon. Reorder/delete/rotate/etc. use the same partial bar as extract unless called out in inventory. **`DS-ORG-005` + ribbon:** not `[x]` until each underlying `DS-ORG-*` passes RULES exit criteria ([.ai/CHECKLIST.md](../.ai/CHECKLIST.md)).

## Notes

- **Merge / split / organize:** Summary **⚠️** = partial implementation, offline-capable engine path. Bookmark split (`DS-ORG-002-B`) remains **blocked** (no outline parser — [PDF-ENGINE.md](PDF-ENGINE.md)). Do **not** mark **Tested** `[T]`/`[V]` or checklist **Done** `[x]` until `DS-QA-001` and per-feature exit criteria pass.
- **Office row:** Mobile intentionally ❌ v1 (ADR-005); use desktop or pre-convert.
- **⚠️ mobile:** Long OCR/batch jobs need foreground UX; smaller cache.
- **Crypto sign:** 🔬 until MIT/Apache library chosen (ADR-010).
- **Tested column:** update to [T]/[V] only after automated + manual sign-off per [TESTING.md](TESTING.md).

## Matrix maintenance

When [FEATURE-INVENTORY.md](FEATURE-INVENTORY.md) adds a P0/P1 row, add or update a line here.
