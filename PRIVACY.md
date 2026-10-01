# Privacy Policy — Document Studio

**Effective date:** 30 September 2026

This policy describes how Document Studio (the "App") handles information when
you use the product. It is written for the shipped App as implemented in this
project.

## Summary

Document Studio is designed for **local, on-device** document work. The App does
**not** require an account, does **not** include advertising SDKs, and does
**not** include analytics or crash-reporting SDKs that send your document
content to Document Studio. Your PDFs and related files are processed on your
device; they are **not** uploaded to Document Studio servers for viewing,
editing, OCR, signing, or conversion.

## What the App processes on your device

- PDF and related files you open or create
- Optional passwords you enter to unlock protected PDFs (used locally to open
  the file; not sent to Document Studio)
- Digital signature credentials and signature marks you choose to apply (used
  locally on your device)
- Local preferences (for example theme and strict offline mode) stored with
  on-device settings APIs such as shared preferences
- Recent-file paths and similar workspace state kept on the device so the App
  can show your recent activity

Document Studio does **not** sell personal data.

## Network use (not document uploads)

By default the App prefers offline operation ("strict offline mode"). When
network access is allowed and you choose certain optional features, the App may
contact the public internet **without uploading your documents**:

1. **Optional OCR language files** — At your request, the App may download
   Tesseract `traineddata` language packs (for example from the public
   `tesseract-ocr/tessdata_fast` repository on GitHub) so OCR can run on your
   device. That download is language model data only; it is **not** an upload
   of the PDF or image you are processing.
2. **Optional desktop engine installers** — On some desktop builds, you may
   choose to download a LibreOffice (or similar) installer from the vendor so
   conversion can run locally. Your documents are still converted on the device;
   they are not sent to Document Studio.
3. **Links inside PDFs** — If you open a link in a document, the App may launch
   your system browser or another external handler. That destination is
   controlled by the link, not by Document Studio document processing.

Document Studio does not operate a cloud document-processing service for this
App. If a store, OS, or hosting platform collects install or crash statistics
outside the App, that is governed by that platform's policies, not by Document
Studio's local processing.

## Permissions

The App requests access only as needed to **open, read, write, and save** files
you choose (and related local capabilities such as printing). It does not use
those permissions to sync your library to Document Studio cloud storage.

## Children

The App is a general productivity tool. It is not directed at children and does
not knowingly collect personal information from children.

## Changes

If this policy changes in a material way, the effective date at the top will be
updated in a later release.

## Contact

Privacy questions: **tejashvikumawat@gmail.com**

Replace the placeholder with a real address before store listing if required by
the platform.
