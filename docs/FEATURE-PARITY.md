# Feature Parity — Document Studio vs Market

**Purpose:** Map **functional** capabilities (not marketing) of major PDF products against Document Studio’s **planned local** scope.

**Legend — Document Studio column**

| Symbol | Meaning |
| --- | --- |
| **Plan** | In FEATURE-INVENTORY; local/offline target |
| **Part** | Partial / fidelity-limited (see limitations) |
| **No** | Not planned or not local |
| **R** | Research required before commitment |

**Competitors:** Adobe Acrobat Pro (desktop + documented services), iLovePDF (web + desktop offline), PDF24 Creator (Windows offline), Smallpdf (mostly cloud — analogous to iLovePDF web).

**Document-centric Adobe target (2026-09-27).** Parity is measured by *document journeys*, not by how many tool routes exist. The target is Acrobat Pro on the local desktop. You open one PDF into a tab backed by a single document session, and every capability runs against that open document: read, organize, protect, export, compress, sign and OCR. Each tool closes the loop with **Replace current** (undoable), **Open as new tab**, or **Save as**. The product should also feel Apple-grade: clear state (dirty, security, active tool), an undo path for every transform, progressive disclosure, and no snackbar-only or dead-end tool pages. A row below counts as parity only when it works from the open document with that loop closed. A standalone route with its own picker does not count. Journey map, top-25 shippable gaps, honest blocked list and next tickets: [.ai/ADOBE-PRODUCT-WAVE.md](../.ai/ADOBE-PRODUCT-WAVE.md).

Sources: Adobe product/compare pages (2026), iLovePDF help/premium tool lists, PDF24 Creator manual/changelog. Cloud-only competitor features are marked **Cloud** in Offline column.

---

## Core workflows parity (summary)

| Capability | iLovePDF | Acrobat Pro | PDF24 | Document Studio | Offline | Priority | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| View / navigate PDF | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Merge / split / organize pages | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Compress PDF | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Image ↔ PDF | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Office → PDF | Yes | Yes | Yes | Plan (desktop) | Yes | P0 | [S] |
| PDF → Office | Yes | Yes | Yes | Part | Yes | P1 | [S] |
| OCR searchable PDF | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Edit text/images in PDF | Yes | Yes | Yes | Part | Yes | P1 | [S] |
| Annotations / markup | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Fill PDF forms | Yes | Yes | Yes | Plan | Yes | P1 | [S] |
| Create PDF forms | Yes | Yes | Yes | Part | Yes | P2 | [S] |
| Visual signature | Yes | Yes | Yes | Plan | Yes | P1 | [S] |
| Cryptographic digital sign | Yes (premium) | Yes | Part | R | Yes | P2 | [R] |
| Password protect / unlock | Yes | Yes | Yes | Plan | Yes | P0 | [S] |
| Redaction (permanent) | Yes | Yes | Yes | Plan | Yes | P1 | [S] |
| Compare PDFs | Yes | Yes | Limited | Plan | Yes | P2 | [S] |
| Repair PDF | Yes | Limited | Yes | Plan | Yes | P2 | [S] |
| PDF/A convert + validate | Yes | Yes | Yes | Part | Yes | P2 | [R] |
| Watermark / page numbers | Yes | Yes | Yes | Plan | Yes | P1 | [S] |
| Scan → PDF | Yes (mobile) | Yes (app) | No | Plan | Yes | P1 | [S] |
| Batch processing | Desktop | Action Wizard | Yes | Plan | Yes | P1 | [S] |
| Saved workflows | Premium | Action Wizard | Profiles | Plan | Yes | P2 | [S] |
| Print to PDF (virtual printer) | No | No | **Win only** | No | Yes | P3 | [X] |
| Request/track remote e-sign | Yes | Yes | No | No | Cloud | — | [X] |
| AI summarize / chat / translate | Premium | Studio AI | No | No | Cloud/AI | — | [X] |
| Cloud storage integration | Yes | Yes | No | No | Cloud | — | [X] |
| Shared review / comments sync | Limited | Yes | No | No | Cloud | — | [X] |
| MS Purview / IRM | No | Yes | No | No | Enterprise | — | [X] |
| Accessibility auto-tag (AI) | No | Yes | No | Part (manual) | Yes | P2 | [R] |
| Preflight print production | No | Yes | Limited | R | Yes | P3 | [R] |
| Multimedia in PDF | Limited | Yes | No | No | Yes | P3 | [X] |

**Status key:** [S] Specified in repo · [R] Research · [X] Intentionally unsupported / non-goal

---

## Detailed capability rows (representative)

| Capability | iLovePDF | Acrobat | Document Studio | Offline | Platform | Priority | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Tabbed multi-PDF | Web/Desktop | Yes | Plan | Yes | All | P1 | [S] |
| Bates numbering | No | Yes | Plan | Yes | All | P2 | [ ] |
| Split by bookmarks | Yes | Yes | Plan | Yes | All | P2 | [ ] |
| PDF → Markdown | Premium | Limited | Plan | Yes | All | P2 | [ ] |
| HTML → PDF | Yes | Yes | R | Yes | Desktop+ | P2 | [R] |
| Hindi / Indic OCR | Yes (cloud) | Yes | Plan (Tesseract) | Yes | All | P1 | [S] |
| Form calculations | Limited | Yes | R | Yes | All | P2 | [R] |
| Signature validation (PAdES) | Digital tier | Yes | R | Yes | Desktop | P2 | [R] |
| TSA timestamp | Cloud | Yes | Part optional | Network if used | P3 | [R] |
| Layer (OCG) view | No | Yes | R | Yes | All | P3 | [R] |
| JavaScript in PDF | No exec | Controlled | Detect/warn | Yes | All | P1 | [ ] |
| Strict offline mode | Desktop | N/A | Plan | Yes | All | P1 | [S] |
| Explorer/Finder open-with | Desktop | Yes | Win partial | Plan | Desktop | P1 | [S] |
| Virtual PDF printer | No | No | Win | No | Win only | P3 | [X] |

---

## §61 Final parity audit — “What still fails without Acrobat/iLovePDF?”

| User workflow | Classification | Document Studio response |
| --- | --- | --- |
| Send PDF to 5 people and track who signed | **F** Cloud | Local visual sign only; export and use email yourself |
| AI summary of 100-page contract | **F** Prohibited AI | Not in scope (NC-07) |
| Real-time co-editing with colleagues | **F** Cloud | Not in scope |
| Adobe Cloud storage / Document Cloud sync | **F** Cloud | OS Files only |
| Bulk legally binding e-sign with audit portal | **F** Cloud | Crypto sign investigate (local cert only) |
| Perfect Word round-trip layout | **D** Technical | Office convert with fidelity class B/C labels |
| Edit scanned PDF as native Word layout | **D** Technical | OCR + export; not true reflow |
| Print-any-app-to-PDF via system printer | **C** Platform | No OS printer driver v1; use export/convert |
| macOS virtual printer | **C** Platform | Same |
| Full XFA dynamic forms | **D** Technical | AcroForm focus; XFA best-effort/warn |
| MS Purview sensitivity labels | **E** Unsupported | Enterprise Adobe ecosystem |
| Payment collection on signature | **F** Cloud | Unsupported |
| AI auto-accessibility tagging | **F** AI | Manual tagging tools Phase 13 investigate |
| iLovePDF “Create PDF from blank design templates” | **B** Future | Phase 3+ simple blank; not full template store |
| Fax send | **E** Unsupported | Not planned |
| eInvoice XML → PDF (PDF24) | **B** Future | P3 investigate |

**A — Must implement (local):** View, organize, compress, convert (scoped), OCR, protect, annotate, basic edit, image tools, scan, batch, metadata, print.

**B — Advanced future:** Bates, PDF/A full, compare report export, form authoring advanced, bookmark generate from headings.

**C — Platform:** Virtual printer (Windows PDF24-style) deferred; mobile background OCR limits.

**D — Investigation:** HTML→PDF, PDF→Office quality, crypto PAdES, layers, form scripts.

**E — Intentionally unsupported:** Cloud collaboration, ads, accounts, telemetry, AI, remote sign routing.

**F — Prohibited by product principles:** Same as E for AI/cloud processing.

---

## Maintenance

When adding features, update this matrix and [FEATURE-INVENTORY.md](FEATURE-INVENTORY.md). Do not mark **Plan** as shipped until tested ([T]/[V] in inventory).
