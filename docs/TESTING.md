# Testing — Document Studio

## Pyramid

| Level | Scope | Tools |
| --- | --- | --- |
| Unit | Domain, job runner, error mapping, path sanitize | `flutter test` |
| Widget | Design system, reader chrome (mock ports) | `flutter test` + goldens |
| Integration | Engine adapters + corpus PDFs | integration_test / custom harness |
| Native | FFI smoke load qpdf/PDFium | per-platform CI job |
| E2E | Open → tool → save | desktop CI primary |
| Performance | Render 100pp, merge 500pp | benchmark harness, track regressions |

Feature is **not done** without tests appropriate to its layer (master spec §25).

## Test corpus

Location: `tests/corpus/` (see [tests/corpus/README.md](../tests/corpus/README.md)).

Required fixtures (add over time):

| File | Purpose |
| --- | --- |
| `simple-text.pdf` | Text search, copy |
| `multi-page-100.pdf` | Navigation perf |
| `large-50mb.pdf` | Memory smoke (optional CI skip) |
| `scanned-no-text.pdf` | OCR input |
| `encrypted-user-pass.pdf` | Password flow (password in README) |
| `forms-acroform.pdf` | Form fill Phase 8 |
| `annotations-standard.pdf` | Annot read Phase 4 |
| `image-heavy.pdf` | Compress |
| `font-subset.pdf` | Edit limitations |
| `malformed-xref.pdf` | Repair |
| `complex-layout.pdf` | Render golden |

Do not commit copyrighted documents; generate synthetics where possible.

## PDF correctness

- After merge/split: page count, rotation metadata
- After encrypt: opens only with password
- After redact: text extract must not contain redacted string

## OCR tests

- Fixed scan image → expected string contains keyword (language eng)
- Searchable PDF: text select finds OCR word (platform sample)

## Security tests

- Oversized dimension image rejected
- Zip bomb PDF aborts with error code

## CI strategy

| Job | Platform |
| --- | --- |
| `analyze` + unit/widget | Linux |
| qpdf/PDFium native smoke | Linux + scheduled macOS/Windows |
| LO conversion | scheduled desktop only |
| APK/IPA build | release branches |

## Golden images

- Store under `tests/goldens/`; `--update-goldens` only in intentional PRs
- CI compare with tolerance for font differences per platform

## Agent rule

New tool → add at least one corpus-based integration test or document why impossible in `.ai/CHECKLIST.md` note.
