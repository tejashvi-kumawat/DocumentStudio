# Architecture

Document Studio is a **Flutter** application with a clear layering:

```text
Flutter UI
  → Application (tools / jobs)
    → Domain models
      → Engine ports (FFI / plugins / processes)
        → Local files
```

## PDF approach

- **Render / interact:** PDFium-based viewing (via Flutter PDF stack).
- **Structure jobs:** qpdf-backed operations for merge, encrypt, compress, page boxes, and repair-style work.

Jobs are orchestrated so long work can report progress and cancel where supported.

## Engines

Heavy lifting is delegated to **bundled local binaries** on desktop (qpdf, Tesseract, LibreOffice, ffmpeg helpers, signing tools). The UI never needs a Document Studio backend.

## Platforms

One codebase targets Android, iOS/iPadOS, Windows, macOS, and Linux. Distribution artifacts differ (Setup.exe, DMG, deb, store packages), but product rules stay the same: offline, private, honest.
