# Updates

Keep Document Studio current without hunting for a new installer every time.

## Latest: v1.2.0

Word and PowerPoint editors, a customizable Quick Tools bar, tool pages with a live preview pane, PDF files opening as tabs in the running app, faster PDF editing with better font identification, and qpdf-free watermark, header/footer, page-number and link tools.

- [Release v1.2.0](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.2.0)
- [Previous: v1.1.0](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.1.0)
- [Download & install](#/install)

## Recommended: CLI

```bash
document_studio --version
document_studio --check-update
document_studio --update
```

`--update` prefers **Homebrew** / **Flatpak** when that channel owns the install; otherwise it downloads the matching asset from [GitHub Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases) and upgrades **in place**.

## Package managers

| Channel | Upgrade |
| --- | --- |
| Homebrew (macOS) | `brew upgrade --cask document-studio` |
| Homebrew (Linux) | `brew upgrade document-studio` |
| Debian `.deb` | Install the newer `.deb` over the old one |

First-time Homebrew:

```bash
brew tap tejashvi-kumawat/tap
```

## Fresh installer

Download the new **Setup.exe** / **.dmg** / **.deb** from [Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases). Windows Setup replaces the previous install under the same app id.

## After updating

| Check | Command / action |
| --- | --- |
| Version | `document_studio --version` |
| App search | Still find “Document Studio” in Start / Spotlight / Activities |
| Engines | Office convert / OCR still available (full release builds) |
