# Privacy — Document Studio

## Commitment (core product)

Document Studio processes documents **on the user's device**. Core features do not require an account or internet access.

## What we do not do (core)

- Upload PDFs, images, or extracted text to any server
- Use cloud OCR, cloud conversion, or cloud AI
- Send document content to analytics or crash reporters (default off; if crash reporting added later, must strip paths/content)
- Sync document libraries to a company cloud

## Data that stays local

- Source files (user-controlled paths/URIs)
- Output files
- Temp working copies in app sandbox
- Recent files list (local preferences only)
- User settings, signature images stored locally if user saves them
- OCR language `.traineddata` in app storage

## Optional network (future, not core)

If language packs are downloaded:

- User must tap **Download** explicitly
- **Strict offline mode** blocks even this when enabled
- Download URL and checksum documented; no document data in requests

## Telemetry

**Default:** none.

If optional opt-in diagnostics are ever added:

- Separate ADR + in-app opt-in
- Allowed: app version, OS, feature ID, error code, duration
- Forbidden: file names, paths, hashes of content, extracted text, thumbnails

## Third-party engines

PDFium, qpdf, Tesseract, LibreOffice (desktop) run locally. They do not define Document Studio's privacy policy but must not be wrapped with cloud APIs for core features.

## OS sharing

When user taps **Share**, the OS share sheet sends files to apps the user chooses—that is user-initiated export, not Document Studio upload.

## Android / iOS notes

- Use SAF and security-scoped URLs; do not copy entire libraries to server.
- Camera: frames processed locally for scan/OCR.

## Privacy review checklist (per feature)

- [ ] No HTTP client in feature code path
- [ ] Logs contain no document bytes or text
- [ ] Temp files deleted after job
- [ ] Feature works in airplane mode

See [SECURITY.md](SECURITY.md) for untrusted file handling.
