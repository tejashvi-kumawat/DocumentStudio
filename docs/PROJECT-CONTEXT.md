# Document Studio — Project Context

Read this first, then [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md) for full detail.

## What this is

**Document Studio** is a free, ad-free, offline, privacy-first **Flutter** app for Android, iOS/iPadOS, Windows, macOS, and Linux. Users work with PDFs, images, and common document formats **on device**. There is no backend, no cloud document processing, no accounts, and no AI document features in scope.

## What we are not building

- A website wrapped as the main product
- Cloud upload/convert/OCR workflows
- Subscription tiers, ads, or telemetry that includes document content
- “Unlock PDF without password” or fake redaction

## Architecture in one diagram

```
Flutter UI → Application (tools/jobs) → Domain models → Engine ports (FFI/plugins) → Local files
```

**Two-engine PDF model (recommended):** PDFium for render/interaction; qpdf for structure, encryption, compression, repair.

## Non-negotiables

See master spec section 4 (NC-01 … NC-10). If a task conflicts, stop and record an ADR or ask the project owner.

## Before you write code

1. Confirm blocking decisions in master spec **section 30.3** (D-01, D-02, D-03, D-05, D-10) or get explicit waiver.
2. Read [.ai/RULES.md](../.ai/RULES.md) and [.ai/WORKFLOW.md](../.ai/WORKFLOW.md).
3. Do not add pub dependencies without a `docs/DEPENDENCIES.md` entry (create entry when that file exists).

## Repository status

**Specification phase complete** (feature specs Phases 1–12 + engineering docs). No Flutter project in repo yet.

Confirm decisions D-01, D-02, D-03, D-05, D-10 (or waive) before Phase 0 coding.

## Key documents

| Document | Use |
| --- | --- |
| [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md) | Source of truth |
| [DECISIONS.md](DECISIONS.md) | ADRs |
| [ROADMAP.md](ROADMAP.md) | Phases and exit criteria |
| [../.ai/CHECKLIST.md](../.ai/CHECKLIST.md) | Feature completion checklist |
