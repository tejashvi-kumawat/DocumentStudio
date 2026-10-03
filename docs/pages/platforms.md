# Platforms

## Desktop

| OS | Installer | Shows as app |
| --- | --- | --- |
| Windows 10/11 | Inno Setup `.exe` | Start Menu, Open with, context menus |
| macOS 12+ | `.dmg` / Homebrew cask | Applications + Spotlight |
| Linux (amd64) | `.deb` / Homebrew formula | `.desktop` entry + icons |

Desktop release builds **bundle engines** (qpdf, Tesseract, LibreOffice, and related tools) so users are not asked to “install qpdf first.”

## Mobile

| OS | Notes |
| --- | --- |
| Android | Play Store packaging; on-device tools |
| iOS / iPadOS | Supported in the Flutter project; distribution depends on your Apple program |

Office conversion on mobile is limited or unavailable by design (size and licensing). Use desktop for Word/Excel → PDF.

## Package managers

| Tool | Package |
| --- | --- |
| winget | `DocumentStudio.DocumentStudio` |
| Homebrew (macOS) | cask `document-studio` via `tejashvi-kumawat/tap` |
| Homebrew (Linux) | formula `document-studio` via the same tap |
| apt | install the release `.deb` |

Tap: [tejashvi-kumawat/homebrew-tap](https://github.com/tejashvi-kumawat/homebrew-tap).
