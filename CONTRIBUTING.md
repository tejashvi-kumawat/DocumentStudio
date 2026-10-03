# Contributing to Document Studio

Thank you for helping improve Document Studio. This guide explains how to propose changes in a way that matches the product’s **offline-first**, **privacy-first** design.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Maintainer

**Tejashvi Kumawat**  
Portfolio: [tejashvi-kumawat.github.io](https://tejashvi-kumawat.github.io) · GitHub: [@tejashvi-kumawat](https://github.com/tejashvi-kumawat)

---

## What we optimize for

Contributions should protect these product rules:

1. **Local processing** — do not add a Document Studio cloud that receives user document bytes for core tools.
2. **No account wall** — do not introduce required sign-in for basic PDF workflows.
3. **Honest security** — no password cracking; redaction must remove underlying content, not only paint over it.
4. **Lean dependencies** — justify new packages (license, size, maintenance, offline suitability).
5. **Cross-platform care** — Flutter UI should remain usable on the platforms you touch; call out platform-specific gaps in the PR.

If a change conflicts with these rules, open an issue first so we can discuss scope.

---

## Ways to contribute

| Kind | Where to start |
| --- | --- |
| Bug report | [GitHub Issues](https://github.com/tejashvi-kumawat/DocumentStudio/issues) with OS, app version (`document_studio --version` when available), steps, expected vs actual |
| Feature idea | Issue first — describe the user job, not only an API |
| Docs (user site) | [`docs/pages/`](docs/pages/) + CSS/JS under [`docs/assets/`](docs/assets/) |
| App / engines | [`lib/`](lib/), packaging under [`scripts/`](scripts/) |
| Tests | [`test/`](test/), corpus notes in [`tests/corpus/`](tests/corpus/) |
| Security | Follow [SECURITY.md](SECURITY.md) — **do not** file a public issue with exploit detail |

Please **do not** attach confidential PDFs (contracts, IDs, medical forms) to public issues. Redact or use synthetic fixtures.

---

## Development setup

```bash
git clone https://github.com/tejashvi-kumawat/DocumentStudio.git
cd DocumentStudio
flutter pub get
flutter doctor   # fix any toolchain gaps for your target OS
```

Run the app:

```bash
flutter run -d linux     # or windows / macos / android / chrome
```

Tests:

```bash
make test-fast           # quick smoke during iteration
flutter test             # full suite before you open a PR
```

Docs site (SPA — needs HTTP):

```bash
cd docs && python3 -m http.server 8080
# http://127.0.0.1:8080/
```

More detail: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), [`docs/TESTING.md`](docs/TESTING.md), [`tests/corpus/README.md`](tests/corpus/README.md).

---

## Branch & commit workflow

1. Fork the repository (or use a feature branch if you have write access).
2. Create a branch from current **`master`** (keep **`main`** in sync for GitHub Pages — Pages serves `/docs` from `main`).
3. Make focused commits with clear messages (prefer conventional style):
   - `fix: …` — bug fix  
   - `feat: …` — user-visible capability  
   - `docs: …` — documentation / Pages content  
   - `chore: …` — tooling, CI, packaging glue  
   - `test: …` — tests only  
4. Keep PRs small enough to review. Large refactors should be discussed in an issue first.
5. Do **not** commit secrets, `.env` files, personal certificates, or machine-local paths under `.tools/`.

### Suggested commit message body

Explain **why**, not only **what**. Reference issue numbers when relevant (`Fixes #123`).

---

## Pull request checklist

Before you request review:

- [ ] Product rules above still hold (offline / privacy / honest security)
- [ ] `flutter analyze` is clean for touched code (or noted exceptions)
- [ ] Relevant tests added or updated; `flutter test` (or an agreed subset) passes locally
- [ ] User-facing docs updated when behavior or install steps change (`docs/pages/…`)
- [ ] Screenshots or short notes for UI changes when helpful
- [ ] No confidential sample documents committed
- [ ] Third-party license impact considered if you add dependencies ([`docs/LICENSES.md`](docs/LICENSES.md), [`THIRD_PARTY_LICENSES/`](THIRD_PARTY_LICENSES/))

PR description should include:

1. Problem / motivation  
2. Approach  
3. How you tested (OS + commands)  
4. Risk / follow-ups  

---

## Documentation map

| Audience | Location |
| --- | --- |
| End users (Pages) | [`docs/pages/`](docs/pages/) — overview, install, how-to, features, privacy |
| Engineering | Root [`docs/*.md`](docs/) — architecture, engines, threat model, release |
| Private planning | `docs-local/` (gitignored — not published) |

When you change a tool’s UX, update **[docs/pages/how-to.md](docs/pages/how-to.md)** (left procedure / right thumbnail pattern) and the feature list if needed.

GitHub Pages source: **`main`** branch, **`/docs`** folder. After merging docs to `master`, ensure `main` receives the same commit so the live site updates.

---

## CI & releases

- App **Release** / installer workflows are **manual** (`workflow_dispatch`) to avoid accidental heavy builds on docs pushes. See [`.github/workflows/`](.github/workflows/).
- Pages builds via GitHub’s `pages-build-deployment` when `main` changes under `/docs`.
- Do not bump release version numbers or publish installers from a drive-by PR unless the maintainer asks.

---

## License & contribution terms

The application is distributed under the terms in [LICENSE](LICENSE). Bundled engines and libraries remain under their upstream licenses.

Unless you state otherwise, contributions you submit are offered for inclusion in Document Studio under the same project license and copyright arrangement as the rest of the codebase, and you confirm you have the right to submit them.

---

## Questions

- Product / docs: [GitHub Issues](https://github.com/tejashvi-kumawat/DocumentStudio/issues)  
- Security: [SECURITY.md](SECURITY.md)  
- Short public note: [docs site → Contributing](https://tejashvi-kumawat.github.io/DocumentStudio/#/contributing)
