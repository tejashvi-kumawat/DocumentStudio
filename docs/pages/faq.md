# FAQ

## Where do I download?

[GitHub Releases v1.1.0](https://github.com/tejashvi-kumawat/DocumentStudio/releases/tag/v1.1.0) — or the Download panel on the [home page](#/).

## Who built this?

**[Tejashvi Kumawat](https://tejashvi-kumawat.github.io)** — [GitHub](https://github.com/tejashvi-kumawat) · [Document Studio repo](https://github.com/tejashvi-kumawat/DocumentStudio).

## Why don’t I see it in Start / Spotlight / Activities?

Install with **Setup.exe**, **DMG → Applications**, or the **.deb**. Terminal-only copies without desktop registration won’t appear in app search. Search for **“Document Studio”** (with a space).

## Are my files uploaded?

No. Tools run locally. See [Privacy](#/privacy).

## Can it unlock a PDF without the password?

No.

## Homebrew?

```bash
brew tap tejashvi-kumawat/tap
brew install --cask document-studio   # macOS
brew install document-studio         # Linux
```

## How do I update?

```bash
document_studio --update
```

Or install a newer release / `brew upgrade`.

## macOS “app can’t be opened”

Right-click → **Open** once (ad-hoc signature). Notarized builds may come later.

## Something broken?

[Open an issue](https://github.com/tejashvi-kumawat/DocumentStudio/issues) with OS, version (`document_studio --version`), and what you tried.
