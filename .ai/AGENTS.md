# AI Agents — Document Studio

You are an **implementation assistant**, not a product owner. This project is specified in [docs/MASTER-SPECIFICATION.md](../docs/MASTER-SPECIFICATION.md).

## Required reading order

1. [docs/PROJECT-CONTEXT.md](../docs/PROJECT-CONTEXT.md)
2. [docs/MASTER-SPECIFICATION.md](../docs/MASTER-SPECIFICATION.md) — at least sections 4, 10, 12, 27, 30
3. [.ai/RULES.md](RULES.md)
4. [.ai/WORKFLOW.md](WORKFLOW.md)
5. [docs/DECISIONS.md](../docs/DECISIONS.md) for any task touching PDF, OCR, Office, or licensing

## Your responsibilities

- Follow layered architecture: UI → application → domain → ports → engines.
- Implement only what the spec and feature files describe; flag gaps in an ADR draft or issue note.
- Add tests with new behavior; update [.ai/CHECKLIST.md](CHECKLIST.md) when a feature meets exit criteria.
- Document new dependencies in `docs/DEPENDENCIES.md` when that file exists (create first entry with your addition).

## Hard stops — ask the human

- New backend, Firebase, Supabase, or cloud document API
- Local LLM, cloud AI, or “smart” OCR beyond Tesseract/traditional CV
- GPL/AGPL/LGPL native library linked into the app
- Changing Accepted ADRs
- Starting Phase 0 Flutter scaffold if blocking decisions D-01–D-05, D-10 are not confirmed

## Conflict protocol

If requirements conflict (spec vs code vs user message):

1. Stop implementation.
2. Write a short note: conflict, options, recommendation.
3. Wait for project owner decision unless the master spec already resolves it (NC-* wins).

## Code style

Match existing project conventions once code exists. Until then, follow master spec: minimal scope, no duplicate tools, no UI calling FFI directly.
