# Organize (Page Management) — UX / workflow plan

**Feature owner:** Lead · **Spec:** `features/DS-ORG-PAGE-MANAGEMENT.md` · **Phase 2**

## Architecture (2026-03)

**Tool-first (NOW):** `/organize` hub → pick operation → dedicated tool route (`/organize/merge`, `/organize/reorder`, …).

**Document-first workspace (LATER):** Reuse `OrganizePageRef`, `PageOrganizeService`, `OrganizePageGrid`, selection model — do not duplicate engine logic.

## Hub

- Grouped cards: composition, extract & split, arrange, format
- Catalog: `organize_tool_catalog.dart` maps to FEATURE-INVENTORY `DS-ORG-*`
- Coming soon: replace, move-between, blank, crop, resize, bookmark split

## Tool routes (implemented / partial)

| Route | Tool |
| --- | --- |
| `/organize` | Hub |
| `/organize/merge` | Merge PDFs (file list, reorder, drop) |
| `/organize/split` | Every N, one-per-page, custom ranges + output preview chips |
| `/organize/reorder` | Thumbnail workspace + export |
| `/organize/delete` | Select + delete + export remainder |
| `/organize/extract` | Export selection only |
| `/organize/rotate` | Rotate selection + export |
| `/organize/duplicate` | Duplicate + export |
| `/organize/reverse` | Reverse + export |
| `/organize/odd-pages` / `even-pages` | Filtered export |
| `/organize/insert` | Multi-PDF append + reorder |

## Shared components

- `OrganizeToolScaffold`, `OrganizeDropTarget`, `OrganizeDropZone`, `OrganizeDocumentSourceList`, `OrganizeWorkflowStrip`, `OrganizePageGrid`, `OrganizeWorkspaceNotifier`, `PageOrganizeService`, `split_plan.dart`, password prompt

## Bug fix

- **DragTarget builder recursion** in page grid (infinite widget tree / hang) — fixed by separating `content` from `DragTarget.builder` child.

## Exit criteria (open)

- Per-tool: progress/cancel, tests, visual QA, encrypted PDFs, large jobs, preview-before-export, insert/replace/move/blank/crop/resize engines
- Checklist `[x]` only when each `DS-ORG-*` item passes full RULES gate
