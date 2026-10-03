# Updates

Keep Document Studio current without hunting for a new installer every time.

## Recommended: CLI

```bash
document_studio --version
document_studio --check-update
document_studio --update
```

`--update` picks the best path for how you installed:

1. **winget** / **Homebrew** / **Flatpak** if that channel owns the install  
2. Otherwise downloads the matching asset from [GitHub Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases) and upgrades **in place**

## Package managers

| Channel | Upgrade |
| --- | --- |
| winget | `winget upgrade --id DocumentStudio.DocumentStudio` |
| Homebrew (macOS) | `brew upgrade --cask document-studio` |
| Homebrew (Linux) | `brew upgrade document-studio` |
| Debian `.deb` | Install the newer `.deb` over the old one |

First-time Homebrew:

```bash
brew tap tejashvi-kumawat/tap
```

## Fresh installer

Download the new **Setup.exe** / **.dmg** / **.deb** from [v1.0.3 Releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.0.3) (or newer). Windows Setup replaces the previous install under the same app id.

## After updating

| Check | Command / action |
| --- | --- |
| Version | `document_studio --version` |
| App search | Still find “Document Studio” in Start / Spotlight / Activities |
| Engines | Office convert / OCR still available (full release builds) |
