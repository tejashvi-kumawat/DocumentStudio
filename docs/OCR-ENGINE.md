# OCR Engine — Document Studio

Canonical engine: **Tesseract 5** (Apache-2.0), ADR-004.

## OcrPort interface (conceptual)

```dart
Future<OcrResult> recognizeImage(OcrInput input, OcrOptions options, CancelToken cancel);
Future<File> createSearchablePdf(PdfInput pdf, OcrOptions options, CancelToken cancel);
```

## Pipelines

**Image → text**

1. Optional preprocess (deskew, binarize) — OpenCV native or Dart `image`
2. `libtesseract` with `tessdata` language
3. Output: plain text, hOCR/TSV optional for debug

**Scanned PDF → searchable PDF**

1. For each page: render to bitmap (PDFium) at OCR DPI (e.g. 300)
2. Tesseract PDF output (invisible text layer) or text + bounds
3. Merge original image as visible layer + text layer (sandwich PDF)
4. Save via qpdf/PDFium

## Language packs

- Ship **eng** in app or first-run download
- Additional: user-initiated download to app private storage
- Config: `tessdata_fast` vs `tessdata_best` tradeoff (size vs accuracy)

## Platform adapters

| Platform | Implementation |
| --- | --- |
| Android / iOS | `flutter_tesseract_ocr` (Tesseract4Android / SwiftyTesseract); eng in `assets/tessdata/` |
| Windows / macOS / Linux | Bundled / PATH `tesseract` CLI with timeout |

Optional **ML Kit / Vision** (Latin only): separate code path; must not be required for offline compliance.

## UX

- Long jobs: foreground on mobile; notification on Android
- Progress: page `i` of `n`
- Cancel: cooperative between pages

## Tests

- Fixed PNG in corpus → contains expected substring
- Searchable PDF → PDFium text extract finds word

See [features/](features/) Phase 6 specs when added.
