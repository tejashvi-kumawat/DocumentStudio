# Platforms

## Desktop

| OS | Installer | Appears as |
| --- | --- | --- |
| Windows 10/11 | [Setup.exe](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.3/DocumentStudio-1.0.3-Setup.exe) | Start Menu app + optional context menus |
| macOS 12+ | [DMG](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.3/DocumentStudio-1.0.3-macos.dmg) / Homebrew cask | Applications + Spotlight |
| Linux amd64 | [.deb](https://github.com/tejashvi-kumawat/DocumentStudio/releases/download/v1.0.3/document-studio_1.0.3_amd64.deb) / Homebrew formula | App menu via `.desktop` |

Desktop releases **bundle engines** so you are not asked to install qpdf/LibreOffice yourself.

## Mobile

| OS | Notes |
| --- | --- |
| Android | On-device tools; Play distribution when published |
| iOS / iPadOS | Flutter targets exist; store distribution needs Apple program |

Office conversion is a **desktop** strength because LibreOffice is large.

## Package managers

| Tool | Command |
| --- | --- |
| Homebrew macOS | `brew install --cask tejashvi-kumawat/tap/document-studio` |
| Homebrew Linux | `brew install tejashvi-kumawat/tap/document-studio` |

Tap repo: [tejashvi-kumawat/homebrew-tap](https://github.com/tejashvi-kumawat/homebrew-tap).
