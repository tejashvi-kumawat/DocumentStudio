# Office conversion

On **Windows, macOS, and Linux** release builds, Document Studio bundles **LibreOffice** for high-fidelity Office → PDF conversion.

## Supported direction (desktop)

- Word / Excel / PowerPoint-style documents → PDF  
- Related import paths exposed in the convert tools

## Why desktop-only for Office

LibreOffice is large. Mobile packages stay smaller and avoid shipping a full office stack. Convert on a desktop build, or create a PDF before opening on mobile.

## Fidelity

Bundled LibreOffice is chosen for layout fidelity versus thin “export as PDF” shortcuts. Complex macros or exotic fonts may still differ from Microsoft Office — always preview important filings.

## Troubleshooting

| Symptom | Try |
| --- | --- |
| Convert missing | Confirm you installed a full desktop release (not a stripped custom build) |
| Convert fails | Re-run from a local path without sync-locker files; check the file opens in LibreOffice |
| macOS Gatekeeper | Right-click app → Open once after install |
