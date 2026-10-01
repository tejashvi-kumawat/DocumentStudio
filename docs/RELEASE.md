# Release — Document Studio

Pre-release planning. No CI/CD in repo yet.

## Distribution channels (target)

| Platform | Channel |
| --- | --- |
| Android | Google Play + optional F-Droid (no proprietary GMS requirement for core) |
| iOS / iPadOS | App Store |
| Windows | MSIX or signed installer |
| macOS | Notarized .dmg or Mac App Store (sandbox entitlements) |
| Linux | Flatpak / AppImage / distro packages |

## Versioning

Semantic versioning: `MAJOR.MINOR.PATCH`

- MAJOR: breaking file format of saved workflows (if any)
- MINOR: new tools/platforms
- PATCH: fixes

## Build flavors

| Flavor | Purpose |
| --- | --- |
| `production` | Default; strict offline available |
| `dev` | Debug logging, corpus shortcuts (not shipped) |

No separate “pro” flavor.

## Signing

- Android: release keystore (owner-managed)
- Apple: Developer ID / App Store certs
- Windows: Authenticode
- macOS: Notarization required for Gatekeeper

## Native binaries

- PDFium: per-ABI from pdfium_flutter build
- qpdf: static libs per target in plugin
- Tesseract: per-platform tessdata in assets or split APK

## Store listings

Messaging: free, offline, no account, privacy-first. Screenshots per form factor (phone, tablet, desktop).

## File associations

Register during install:

- PDF primary
- Images for image tools
- Optional `.docx` open → convert on desktop only

## Update strategy

- Store updates; no forced remote kill switch in app
- Engine security patches via app updates

## Pre-release checklist

- [ ] LICENSES screen complete
- [ ] Privacy policy URL (owner-hosted) if stores require
- [ ] No API keys in repo
- [ ] Corpus tests pass on CI
- [ ] Performance smoke on reference devices
- [ ] Strict offline mode tested

## LibreOffice

Not bundled by default (size/licensing simplicity)—document user install in help.
