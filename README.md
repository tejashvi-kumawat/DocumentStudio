# Document Studio

**Document Studio** is a free, ad-free, offline-first PDF and document workspace for **Windows**, **macOS**, and **Linux** (with mobile targets in the Flutter codebase). Files are processed **on your device** — no account, no ads, and no Document Studio cloud that receives your documents for core tools.

| | |
| --- | --- |
| **Latest release** | [v1.1.0](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.1.0) |
| **Product docs** | [tejashvi-kumawat.github.io/DocumentStudio](https://tejashvi-kumawat.github.io/DocumentStudio/) |
| **Author** | [Tejashvi Kumawat](https://tejashvi-kumawat.github.io) |
| **License** | See [LICENSE](LICENSE) (app) · third-party engines keep their own licenses |

---

## Why Document Studio

Most PDF tools push you into a browser upload or a subscription suite. Document Studio aims for the opposite:

- **Local pipelines** — merge, split, compress, encrypt, OCR, Office→PDF, and more on disk
- **Honest security** — encryption needs the real password; redaction removes content, not only a black box
- **Real desktop installs** — Start Menu / Applications / Linux app menu after Setup / DMG / `.deb`
- **No account wall** — open a file, run a tool, save

---

## Download (v1.1.0)

| Platform | Installer |
| --- | --- |
| **Windows** | [DocumentStudio-1.1.0-Setup.exe](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.1.0/DocumentStudio-1.1.0-Setup.exe) |
| **macOS** | [DocumentStudio-1.1.0-macos.dmg](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.1.0/DocumentStudio-1.1.0-macos.dmg) |
| **Linux (Debian/Ubuntu amd64)** | [document-studio_1.1.0_amd64.deb](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.1.0/document-studio_1.1.0_amd64.deb) |

Full install guide (shell menus, Homebrew, updates):  
**[docs site → Download & install](https://tejashvi-kumawat.github.io/DocumentStudio/#/install)**

### Homebrew

```bash
# macOS
brew tap tejashvi-kumawat/tap
brew install --cask document-studio

# Linux (formula)
brew tap tejashvi-kumawat/tap
brew install document-studio
```

Tap: [tejashvi-kumawat/homebrew-tap](https://github.com/tejashvi-kumawat/homebrew-tap)

### First launch: security prompts

Releases are not code-signed yet, so the systems ask once before the first
launch. This is not a malware finding:

- **Windows** ("Windows protected your PC"): click **More info → Run anyway**.
- **macOS** ("cannot verify … free of malware"): in Applications, right-click
  **Document Studio → Open → Open**, or System Settings → Privacy & Security →
  **Open Anyway**.

Maintainers: signing is wired into the release build; see
[packaging/CODE_SIGNING.md](packaging/CODE_SIGNING.md).

### CLI quick checks

```bash
document_studio --version
document_studio --help
document_studio --check-update
```

---

## Features (summary)

| Category | Examples |
| --- | --- |
| **Home & library** | Open / create PDF, images↔PDF, pinned & recent, searchable tools hub |
| **Organize** | Merge, split, extract, insert, replace, reorder, rotate, crop, resize, blank pages |
| **Optimize** | Compress, watermark, batch, metadata edit/remove, repair |
| **Protect** | Encrypt / decrypt, headers & footers, page numbers, redact |
| **Sign & forms** | Visual signatures & stamps, certificate / digital sign, fill AcroForms |
| **Edit & markup** | Edit text, highlight, shapes, comments, links, compare PDFs |
| **Capture & OCR** | Insert scan, searchable PDF (Tesseract), image OCR |
| **Convert** | Office → PDF on desktop via bundled LibreOffice |

Step-by-step for every tool:  
**[How to use tools](https://tejashvi-kumawat.github.io/DocumentStudio/#/how-to)** ·  
**[Feature list](https://tejashvi-kumawat.github.io/DocumentStudio/#/features)**

---

## Architecture (high level)

```text
Flutter UI (Riverpod + go_router)
        │
        ▼
Domain / jobs (organize, protect, OCR, convert, …)
        │
        ▼
Local engines on desktop builds (qpdf, Tesseract, LibreOffice, signing helpers, PDFium via pdfrx)
```

There is **no** Document Studio backend for document bytes. Optional network use is limited to things like update checks against release channels you already trust.

Deeper engineering notes live under [`docs/`](docs/) (architecture, engines, privacy, security threat model). The **public user site** is the SPA in [`docs/`](docs/) served by GitHub Pages (`/docs` on `main`).

---

## Build from source

Requirements: a current [Flutter](https://docs.flutter.dev/get-started/install) SDK matching [`pubspec.yaml`](pubspec.yaml), plus platform toolchains (Linux GTK deps, Visual Studio on Windows, Xcode on macOS).

```bash
git clone https://github.com/tejashvi-kumawat/DocumentStudio.git
cd DocumentStudio
flutter pub get
flutter run -d linux          # or windows / macos / chrome / android …
make test-fast                # fast smoke subset during iteration
flutter test                  # full suite before you propose a change
flutter build linux --release # example desktop release build
```

Packaging scripts and release CI live under `scripts/` and [`.github/workflows/`](.github/workflows/). Release installer builds are **manual** (`workflow_dispatch`) so docs-only pushes do not rebuild binaries.

Corpus / encrypted fixtures: [`tests/corpus/README.md`](tests/corpus/README.md).  
Local developer loop: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

### Preview the docs site locally

```bash
cd docs
python3 -m http.server 8080
# open http://127.0.0.1:8080/
```

Do not open `index.html` as `file://` — the SPA fetches Markdown over HTTP.

---

## Repository layout

| Path | Purpose |
| --- | --- |
| [`lib/`](lib/) | Flutter application |
| [`docs/`](docs/) | Public GitHub Pages site + engineering markdown |
| [`docs/pages/`](docs/pages/) | User-facing guides (overview, install, how-to, …) |
| [`scripts/`](scripts/) | Packaging and helper scripts |
| [`test/`](test/) · [`tests/`](tests/) | Automated tests and corpus |
| [`THIRD_PARTY_LICENSES/`](THIRD_PARTY_LICENSES/) | Bundled third-party license texts |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Community standards |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to propose changes |
| [`SECURITY.md`](SECURITY.md) | Vulnerability reporting |

Private planning notes belong in `docs-local/` (gitignored), not in the published Pages tree.

---

## Contributing & community

- Read **[CONTRIBUTING.md](CONTRIBUTING.md)** before opening a PR.
- Follow the **[Code of Conduct](CODE_OF_CONDUCT.md)**.
- Report security issues via **[SECURITY.md](SECURITY.md)** — not public issues for exploit details.
- Bugs and feature ideas: [GitHub Issues](https://github.com/tejashvi-kumawat/DocumentStudio/issues).

---

## Privacy & security (product)

- Core document tools run **offline** on the machine that opened the file.
- The app does **not** crack PDF passwords.
- Prefer real **redaction** over covering text with opaque shapes.
- Keep encryption passwords outside the PDF — lost passwords cannot be recovered by Document Studio.

User-facing pages: [Privacy](https://tejashvi-kumawat.github.io/DocumentStudio/#/privacy) · [Security](https://tejashvi-kumawat.github.io/DocumentStudio/#/security).

---

## Links

- [Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases)
- [Documentation site](https://tejashvi-kumawat.github.io/DocumentStudio/)
- [Author portfolio](https://tejashvi-kumawat.github.io)
- [Homebrew tap](https://github.com/tejashvi-kumawat/homebrew-tap)
