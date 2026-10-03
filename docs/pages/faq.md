# FAQ

## Why don’t I see Document Studio in Start / Spotlight / Activities?

The terminal launcher can exist without a desktop registration. Install via **Setup.exe**, **.dmg → Applications**, or the **.deb** / Homebrew packages so the OS gets a Start Menu shortcut or `.desktop` / `.app` bundle. Then search for **“Document Studio”** (space), not only `document-studio`.

## Is my PDF uploaded anywhere?

No. Core tools run locally. Update checks do not send document contents.

## Can it unlock a PDF without the password?

No. That is intentionally unsupported.

## Where do I download builds?

[github.com/tejashvi-kumawat/DocumentStudio/releases](https://github.com/tejashvi-kumawat/DocumentStudio/releases)

## Homebrew?

```bash
brew tap tejashvi-kumawat/tap
brew install --cask document-studio   # macOS
brew install document-studio         # Linux
```

## How do I update?

`document_studio --update`, or your package manager / a newer installer from Releases.

## macOS says the app can’t be opened

Use **right-click → Open** once for ad-hoc signed builds, or wait for a notarized release if you require Gatekeeper-clean defaults.
