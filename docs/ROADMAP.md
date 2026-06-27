# Document Studio — Roadmap

Living roadmap derived from [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md) section 29. Update this file when phases slip or scope changes; do not silently drift from the master spec.

## Principles

- One vertical slice at a time; shared tool registry and engine ports early.
- Do not start a phase until previous **exit criteria** are met (or waived in writing).
- Platform gaps (e.g. Office on mobile) stay hidden via registry, not broken UI.

## Phase 0 — Foundation

**Goal:** Repo and architecture ready for feature work.

| Deliverable | Notes |
| --- | --- |
| Flutter app skeleton (when authorized) | Single entry, flavors optional |
| Monorepo `packages/` for FFI plugins | pdfium/qpdf/ocr stubs |
| ADRs D-01–D-05, D-10 confirmed | See [DECISIONS.md](DECISIONS.md) |
| Design tokens v0 | Light/dark |
| `FileStoragePort` + SAF/path abstraction | |
| Tool registry + job runner shell | Progress, cancel |
| CI: analyze, unit tests | |
| Test corpus directory + 3–5 sample PDFs | Expand over time |

**Exit:** Open and render a multi-page PDF on each target platform, or document explicit exception with ADR.

---

## Phase 1 — PDF reader

**Features:** DS-READ-001 … DS-READ-015 (core subset)

**Exit:** Navigation, zoom, thumbnails, search (basic), password prompt, properties, phone + desktop layouts.

**Spec:** [features/DS-READ-PDF-VIEWER.md](../features/DS-READ-PDF-VIEWER.md)

---

## Phase 2 — Page management

**Spec:** [features/DS-ORG-PAGE-MANAGEMENT.md](../features/DS-ORG-PAGE-MANAGEMENT.md)

**Spec:** [features/DS-ORG-PAGE-MANAGEMENT.md](../features/DS-ORG-PAGE-MANAGEMENT.md)

**Features:** DS-ORG-001 … DS-ORG-008, DS-ORG-010

**Exit:** Merge/split/extract/reorder/rotate with non-destructive save-as; DnD on desktop.

---

## Phase 3 — Core tools

**Specs:** [DS-OPT-COMPRESS.md](../features/DS-OPT-COMPRESS.md), [DS-CNV-IMAGE-PDF.md](../features/DS-CNV-IMAGE-PDF.md)

**Exit:** Compress with stats; image↔PDF; watermark/page numbers (simple).

---

## Phase 4 — Annotation

**Spec:** [DS-ANN-ANNOTATION.md](../features/DS-ANN-ANNOTATION.md)

**Exit:** Standard annotations visible in external reader (corpus-tested).

---

## Phase 5 — Editing

**Spec:** [DS-EDIT-CONTENT.md](../features/DS-EDIT-CONTENT.md)

**Exit:** Add-content + undo/autosave; honest labeling vs true edit.

---

## Phase 6 — OCR + scan

**Spec:** [DS-OCR-SCAN.md](../features/DS-OCR-SCAN.md)

**Exit:** Searchable PDF from scan; languages; cancellable jobs.

---

## Phase 7 — Security

**Spec:** [DS-SEC-SECURITY.md](../features/DS-SEC-SECURITY.md)

**Exit:** Encrypt/decrypt; permanent redaction verified on corpus.

---

## Phase 8 — Forms & visual signatures

**Spec:** [DS-FORM-SIGN.md](../features/DS-FORM-SIGN.md)

**Exit:** Fill forms; visual sign + flatten.

---

## Phase 9 — Office conversion (desktop)

**Spec:** [DS-CNV-OFFICE.md](../features/DS-CNV-OFFICE.md)

**Exit:** LO integration; fidelity labels.

---

## Phase 10 — Advanced PDF

**Spec:** [DS-ADV-PDF.md](../features/DS-ADV-PDF.md)

**Exit:** Compare/repair/PDF-A scoped to proven engine support.

---

## Phase 11–12 — Batch & workflows

**Spec:** [DS-BATCH-WORKFLOW.md](../features/DS-BATCH-WORKFLOW.md)

**Exit:** Batch queue + saved local workflow presets.

---

## Phase 13 — Accessibility and professional tooling

**Goal:** Ship accessible application chrome and investigate PDF structure remediation within offline constraints.

| Workstream | Inventory examples | Notes |
| --- | --- | --- |
| App accessibility | DS-A11Y-001 … DS-A11Y-008 | Screen reader, keyboard, focus, high contrast |
| PDF accessibility inspection | DS-A11Y-010 … DS-A11Y-015 | Tag tree view, reading order, checker report |
| Remediation (feasible subset) | DS-A11Y-020+ | No promise of full Acrobat Tagging parity |
| Bookmarks/links authoring polish | DS-BMK-*, DS-LNK-* | Desktop/tablet first |
| Pre-flight / document properties | DS-META-*, properties panels | Unified inspector |

**Exit:** WCAG-oriented app UI on all targets; PDF accessibility **report** on corpus; remediation tools only where engine proof exists.

**Refs:** [FEATURE-INVENTORY.md](FEATURE-INVENTORY.md) MOD-A11Y, [TESTING.md](TESTING.md), [UI-UX.md](UI-UX.md)

---

## Phase 14 — Performance and hardening

**Goal:** Large-document and batch stability; security corpus; resource limits.

| Workstream | Inventory examples | Notes |
| --- | --- | --- |
| Rendering cache / lazy load | DS-EDGE-007, PERFORMANCE.md | Page/thumbnail eviction under memory pressure |
| Job isolation | DS-EDGE-002, DS-BATCH-* | Isolates, cancel, progress |
| Malformed PDF / bomb limits | DS-EDGE-004, DS-QA-004 | SECURITY.md limits |
| OCR/conversion benchmarks | DS-QA-005 | Per-platform baselines |
| Crash recovery | DS-EDGE-006, DS-SHELL-010 | Atomic writes verified |

**Exit:** Documented limits enforced; performance targets met on reference hardware; security regression suite green.

---

## Phase 15 — Cross-platform release

**Goal:** Store-ready builds and parity sign-off.

| Deliverable | Notes |
| --- | --- |
| Platform packaging | Android/iOS/macOS/Windows/Linux per [RELEASE.md](RELEASE.md) |
| File associations / open-with | DS-READ-001-D, DS-PLAT-* |
| Store compliance | Privacy nutrition labels; no undeclared network |
| Smoke matrix | [FEATURE-MATRIX.md](FEATURE-MATRIX.md) Tested column → [T]/[V] for P0 |
| Corpus regression | [tests/corpus/](tests/corpus/) full set |

**Exit:** P0 features verified on all primary platforms; known limitations documented in [UNSUPPORTED-FEATURES.md](UNSUPPORTED-FEATURES.md) and parity audit §61 in [FEATURE-PARITY.md](FEATURE-PARITY.md).

---

## Not scheduled

- Cloud collaboration, accounts, AI document features, web-primary SKU.
