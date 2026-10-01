# document_studio_ocr

Dart ports for **Tesseract 5** OCR and searchable-PDF generation in Document Studio ([ADR-004](../../docs/DECISIONS.md), [OCR-ENGINE.md](../../docs/OCR-ENGINE.md)).

## Status

| API | Inventory | Notes |
| --- | --- | --- |
| `OcrPort.recognizeText` | Desktop CLI + Android plugin | `BlockedOcrPort` only on web |
| `SearchablePdfPort.createSearchablePdf` | Desktop (qpdf + Tesseract) | Blocked on Android/iOS/web |

## Public API

- **`OcrPort`** — `Future<OcrTextResult> recognizeText(Uint8List imageBytes, {OcrOptions options})`
- **`SearchablePdfPort`** — `Future<Uint8List> createSearchablePdf(Uint8List pdfBytes, {OcrOptions options})`
- **`BlockedOcrPort` / `BlockedSearchablePdfPort`** — throw `OcrEngineBlockedException` with reason strings

Features must depend on these ports, not on Tesseract directly ([MASTER-SPEC](../../docs/MASTER-SPECIFICATION.md)).

## Tessdata bundling strategy

Aligned with [OCR-ENGINE.md](../../docs/OCR-ENGINE.md) **Language packs**:

1. **Default English (`eng`)**
   - **Mobile (Android/iOS):** ship `eng.traineddata` from `tessdata_fast` at app
     `assets/tessdata/` plus `assets/tessdata_config.json` (required by
     `flutter_tesseract_ocr`). First launch works offline.
   - **Desktop (Windows/macOS/Linux):** bundled under `engines/tessdata` or system
     packages; optional first-run download into app-private storage.

2. **Additional languages**
   - Not bundled by default. User-initiated download into **app private storage**
     (`StoragePaths` › `ocr-languages/`) via the existing free GitHub
     `tessdata_fast` URL (`downloadOcrLanguageData`). No paid / cloud OCR API.
   - On Android the packs are also copied into the plugin’s documents
     `tessdata/` folder so Tesseract4Android can see them.

3. **`tessdata_fast` vs `tessdata_best`**
   - **Default build:** `tessdata_fast` for smaller APK/IPA/desktop bundles and acceptable Latin accuracy.
   - **Settings toggle (future):** allow `tessdata_best` per language after explicit download (larger files, higher accuracy).

4. **Runtime path passed to Tesseract**
   - Desktop: `TESSDATA_PREFIX` / `--tessdata-dir` via CLI.
   - Android: `flutter_tesseract_ocr` reads `assets/tessdata` + app documents `tessdata/`.

5. **Platform limits**
   - **OCR (image → text):** works on desktop and Android (on-device Tesseract).
   - **Searchable PDF / qpdf / LibreOffice soffice:** desktop only — mobile shows an
     in-app blocked reason (no pretend support).

## Tests

```bash
cd packages/document_studio_ocr
dart pub get
dart test
dart analyze
```

Corpus tests (fixed PNG → expected substring, searchable PDF text extract) belong here once FFI is integrated.
