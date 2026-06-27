# Blocked Features — Implementation Status

| Feature | Status | Reason | Next step |
| --- | --- | --- | --- |
| Encrypted corpus fixture (`tests/corpus/encrypted-user-pass.pdf`) | `[B]` | Generator `tests/corpus/generators/generate_encrypted_user_pass.sh` requires **qpdf on PATH**; fixture not committed until script succeeds locally (password `testpass` documented in `tests/corpus/README.md` only — no secrets in filenames) | **CI:** `.github/workflows/flutter_ci.yml` installs qpdf and runs the generator before `flutter test` so `organize_encrypted_corpus_test.dart` executes in CI. **Local:** `sudo apt install qpdf` (or equivalent), run the script, commit the small PDF if policy allows |
| Page crop (CropBox margins) | `[I]` | qpdf CLI `--set-box=C=…` or `--crop` when supported; `/organize/crop` | Requires qpdf with page box flags; mock service tests for encrypted export password (`page_organize_service_page_box_export_test.dart`) |
| Page resize (MediaBox) | `[I]` | qpdf CLI `--set-box=M/C=letter|a4|legal`; `/organize/resize` | **No content scaling** (DS-ORG-013 scale path still blocked); same encrypted password service tests as crop |
| Merge / reorder (unencrypted) | `[I]` | pdfrx `assemble` / `encodePdf` via `/organize` workspace | Verify exit criteria; gaps: blank page, cancel token, SAF |
| Password protect (encrypt) | `[I]` | qpdf CLI via `/protect` when `qpdf` on PATH | Bundle qpdf FFI for mobile |
| Merge (encrypted) / advanced compress | `[B]` | qpdf FFI + CLI optional | `packages/document_studio_qpdf` |
| Linux print build | `[B]` | `printing` plugin expects bundled `libpdfium.so` | Investigate pdfium_flutter asset path |
| OCR / searchable PDF | `[B]` | `packages/document_studio_ocr` ports + blocked stubs; no Tesseract FFI | ADR-004 FFI + tessdata |
| Office conversion | `[B]` | LibreOffice headless not wired | Desktop Phase 9 |
| Annotations authoring | `[R]` | pdfrx 2.6.x has no public annot create/update/save APIs (`PdfrxAnnotationAdapter` read-only via `PdfPage.loadLinks`) | Custom PDFium FFI (`FPDFAnnot_*`) or pdfrx 3.x / upstream #545 |
| Annotations list (read) | `[I]` | Panel in viewer (wide layout); list via `loadLinks` | PDFium subtype scan for silent highlights/ink |
| Crypto digital signatures | `[R]` | MIT library TBD | ADR-010 |
| Split by bookmarks (`DS-ORG-002-B`) | `[B]` | No bookmark tree API in `PdfRenderPort` / pdfrx adapter yet | Add bookmark load + split plan, then UI |
| Visual crop box (`DS-ORG-012`) | `[B]` | Requires interactive crop rect + engine box update; qpdf margin presets shipped at `/organize/crop` | Custom crop UI + qpdf `--crop` coordinates |
| Favorites / pin (`DS-READ-001-C`) | `[I]` | `FavoriteFilesRepository` + home favorites section + recents star; paths in SharedPreferences only | SAF persistable URI, viewer pin, search/sort (`DS-FILE-002`) |
| Resize media box (`DS-ORG-013`) | `[B]` | Needs qpdf page geometry CLI wiring + validation | `QpdfCliRunner` + page tool |
| Workspace → crop/resize preload | `[B]` | qpdf edits one source PDF by original page index; `/organize/crop` and `/organize/resize` accept `PageBoxQpdfToolLaunch` (first `importedFiles` entry + selected pages on that file only) | Multi-PDF workspace order, pages from other sources, and reordered subsets are not passed — user re-selects in tool or opens source PDF |

Quick tools on home show **Coming soon** until real engines are wired — no fake success paths.
