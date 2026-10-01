# Conversion Engine — Document Studio

## Fidelity classes

Display in UI before running (see [UI-UX.md](UI-UX.md)):

| Class | Meaning | Examples |
| --- | --- | --- |
| A | Visual fidelity | PDF ↔ PNG |
| B | Structural best effort | Office → PDF, PDF → DOCX |
| C | Text only | PDF → TXT |
| D | New layout | MD → PDF |

## ConversionPort (conceptual)

```dart
Future<ConversionResult> convert(ConversionRequest request, CancelToken cancel);
```

## Implemented pipelines

| From | To | Engine | Platforms |
| --- | --- | --- | --- |
| JPEG/PNG/… | PDF | pdfrx_engine / PDFium | All |
| PDF | PNG/JPEG | PDFium render + encode | All |
| TXT/MD | PDF | Dart layout (Phase 3+) | All |
| HTML | PDF | TBD (WebView snapshot or print) | Investigate |
| DOC/XLS/PPT | PDF | LibreOffice subprocess | Desktop only |
| PDF | DOCX/XLSX | Extraction heuristics | Desktop partial |

## LibreOffice integration (desktop)

```
ConversionService.detectLibreOffice() → path | null
ConversionService.convert(inputPath, format, profileDir, timeout)
```

- Isolated `--env:UserInstallation=file:///.../lo_profile_<uuid>`
- Timeout default 120s
- Kill process tree on cancel

If LO missing: guide user to install (D-06 pending)—no silent download without approval.

## Mobile gap

Office tools **hidden** on Android/iOS v1 (ADR-005). Show import PDF / scan instead.

## Error handling

`CONVERSION_FAILED`, `TIMEOUT`, `UNSUPPORTED_PLATFORM`, `ENGINE_UNAVAILABLE` (LO not found).

## Tests

- Round-trip smoke where class A
- LO: convert sample DOCX if LO present in CI (optional job)

See [features/DS-CNV-IMAGE-PDF.md](../features/DS-CNV-IMAGE-PDF.md).
