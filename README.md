# Document Studio

Document Studio is a free, offline, privacy-first document application for Android, iOS, iPadOS, Windows, macOS, and Linux. Files are processed on the user's device. The application has no account, no advertisements, no backend, and no cloud document processing.

The primary application framework is Flutter. **Phase 0–1 foundation and PDF viewer (pdfrx) are in progress** in `lib/`.

## Source of truth

Read [docs/MASTER-SPECIFICATION.md](docs/MASTER-SPECIFICATION.md) before any product, architecture, or implementation work.

Quick onboarding: [docs/PROJECT-CONTEXT.md](docs/PROJECT-CONTEXT.md).

## Documentation map

| Path | Purpose |
| --- | --- |
| [docs/MASTER-SPECIFICATION.md](docs/MASTER-SPECIFICATION.md) | Full product and architecture spec |
| [docs/PROJECT-CONTEXT.md](docs/PROJECT-CONTEXT.md) | Short onboarding |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Architecture Decision Records |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phased delivery (Phases 0–15) |
| [docs/FEATURE-INVENTORY.md](docs/FEATURE-INVENTORY.md) | **Authoritative** feature IDs and status |
| [docs/FEATURE-MATRIX.md](docs/FEATURE-MATRIX.md) | Platform × capability matrix |
| [docs/FEATURE-PARITY.md](docs/FEATURE-PARITY.md) | Parity vs Acrobat / iLovePDF / PDF24 |
| [docs/FEATURE-DEPENDENCIES.md](docs/FEATURE-DEPENDENCIES.md) | Engine and feature dependency graph |
| [docs/FEATURE-GAPS.md](docs/FEATURE-GAPS.md) | Scope audit vs prior docs |
| [docs/UNSUPPORTED-FEATURES.md](docs/UNSUPPORTED-FEATURES.md) | Explicit non-goals and reasons |
| [docs/TECH-STACK.md](docs/TECH-STACK.md) | Stack summary |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | Dependency and license registry |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System layers and patterns |
| [docs/FLUTTER-ARCHITECTURE.md](docs/FLUTTER-ARCHITECTURE.md) | App structure, routing, state |
| [docs/PDF-ENGINE.md](docs/PDF-ENGINE.md) | PDFium + qpdf split |
| [docs/OCR-ENGINE.md](docs/OCR-ENGINE.md) | Tesseract pipelines |
| [docs/CONVERSION-ENGINE.md](docs/CONVERSION-ENGINE.md) | Formats and LibreOffice |
| [docs/FILE-SYSTEM.md](docs/FILE-SYSTEM.md) | SAF, atomic write, temp files |
| [docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md) | Tokens and components |
| [docs/UI-UX.md](docs/UI-UX.md) | Layouts and flows |
| [docs/PRIVACY.md](docs/PRIVACY.md) | Privacy policy for engineering |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Local dev loop (targeted tests, `make test-fast`) |
| [docs/EDITOR-ARCHITECTURE.md](docs/EDITOR-ARCHITECTURE.md) | Edit modes, undo, coordinates |
| [docs/IMAGE-ENGINE.md](docs/IMAGE-ENGINE.md) | Image decode/transform |
| [docs/PLATFORM-INTEGRATION.md](docs/PLATFORM-INTEGRATION.md) | OS integrations per platform |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Performance targets |
| [docs/LICENSES.md](docs/LICENSES.md) | Third-party license compliance |
| [docs/RELEASE.md](docs/RELEASE.md) | Packaging and stores |
| [docs/PRODUCT-REQUIREMENTS.md](docs/PRODUCT-REQUIREMENTS.md) | FR/NFR summary |
| [features/](features/) | Feature specs Phases 1–12 ([index](features/README.md)) |
| [tests/corpus/](tests/corpus/) | Test PDF inventory |
| [.ai/AGENTS.md](.ai/AGENTS.md) | Instructions for AI agents |
| [.ai/RULES.md](.ai/RULES.md) | Mandatory dev rules |
| [.ai/WORKFLOW.md](.ai/WORKFLOW.md) | Implementation workflow |
| [.ai/CHECKLIST.md](.ai/CHECKLIST.md) | Phase / feature checklist |

## Current status

**Implementation in progress (2026-09-26):** Flutter app (6 platforms); home + settings; **PDF viewer** (tabs, thumbnail sidebar, search flow, print action); **Organize** (merge queue, reorder, split); **Compress** (lossless re-encode); **Image tools**; pdfrx + `document_studio_qpdf` CLI package. **Blocked / [R]:** qpdf FFI, Tesseract OCR, annotations write, Office conversion — [docs/BLOCKED-FEATURES-IMPLEMENTATION.md](docs/BLOCKED-FEATURES-IMPLEMENTATION.md).

### Run locally

```bash
flutter pub get
flutter run -d linux    # or android, windows, etc.
make test-fast   # smoke subset during iteration; full suite in CI
flutter build linux
```

### Tests and corpus

Corpus fixtures, encrypted-PDF bootstrap (`scripts/setup_portable_qpdf.sh` or system `qpdf`), and CI behavior are documented in [tests/corpus/README.md](tests/corpus/README.md). Use [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for targeted tests; run full `flutter test` before merge/release. Organize encrypted tests skip when the fixture is absent.

Verified on this environment: **Linux desktop** build (`flutter build linux --debug`). iOS/macOS/Windows/Android require their SDKs on the host.

### Version control

If the project was copied without git metadata, initialize a local repository with `git init`, then connect your remote (for example GitHub) and push — **do not commit** `.env`, credentials, or local secrets. Keep `.tools/` and other gitignored paths out of the repo.

## AI agents

Start with [.ai/AGENTS.md](.ai/AGENTS.md) and [.ai/RULES.md](.ai/RULES.md).
