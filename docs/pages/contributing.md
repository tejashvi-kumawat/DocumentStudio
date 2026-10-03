# Contributing

## Before you change code

1. Prefer small, focused PRs.
2. Don’t add cloud document processing or account systems.
3. Don’t add dependencies casually — justify size and license.
4. Keep user-facing behavior honest (encryption, redaction, offline).

## Repo layout (high level)

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter application |
| `packages/` | Local plugins / helpers |
| `scripts/` | Bundle & package scripts |
| `packaging/` | winget / Homebrew / apt templates |
| `docs/` | This GitHub Pages site |
| `docs-local/` | Private planning notes (not published) |

## Docs site

Public documentation lives only under `docs/` (designed site + `docs/pages/*.md`). Planning material in `docs-local/` stays local / gitignored.

## Issues & releases

- Bugs and features: GitHub Issues on the main repo  
- Binaries: GitHub Releases  
