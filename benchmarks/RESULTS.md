# Document Studio engine times on this PC

Measured 1 Oct 2026 on this machine: Linux, 16 CPUs (Intel Core i7-13620H), 14 GiB RAM. A `flutter run` session was already running and was left alone. Each file was timed in its own `dart` process (`benchmarks/engine_bench.dart`) so that process's RAM is not the running app's RAM.

These are Document Studio engine times on this PC. They are not a claim that Document Studio is N times faster than Acrobat. Adobe Acrobat, SumatraPDF, Foxit, and Microsoft Edge are not installed here, so their advertised times were not measured on this machine and are not quoted.

## What was timed

The production open is `PdfDocumentCache.acquire` with `loadAllPages: false`. That calls `PdfDocument.openFile` with `useProgressiveLoading: true` and does not walk every page. This run calls that same `openFile`. It is the engine open, not a Flutter frame and not a click in the window. `pdfrxInitialize` ran first and is outside the open timer, because the app initializes pdfrx at startup.

Cold is the first `openFile` in a new process. Warm is a second `openFile` in that same process after the first document was disposed, so an in-process document cache cannot hand back the first open. Wall clock around `openFile` only, until `pages.length` is known. After each cold open, PDFium had loaded 1 page and left the rest as placeholders.

The files were downloaded earlier the same morning, so the kernel page cache may already have held them. The yearbook and the tax code each recorded 1 major page fault. These opens are not a cold read from disk.

Peak RSS is `/usr/bin/time -v` maximum resident set size for that process (it matches `VmHWM`). It includes the Dart VM and PDFium, plus the two opens, the six page renders, and (for the tax code) the search. The three files land in a narrow band, including the 155 MB scan, so this figure is the process high-water mark, not a full decode of the file.

Rendering used about 800 px on the long edge (white background). Pages that were not loaded yet were measured with `reloadPages` inside that page's render time. Each bitmap had non-white pixels. A full render of all pages was refused: it is not the open path, and rasterizing 1198 scanned pages or 4211 text pages would not answer how fast the file opens.

## Results

| File | Pages | Cold open | Warm open | Peak RSS | First-page render | Note |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| NZERTF-Architectural-Plans1-June2011.pdf | 20 | 54 ms | 38 ms | 522 MiB (534656 kB) | 60 ms | Vector sheets. Page 1 was 800×533 px. The next 5 pages took 501 ms (75–127 ms each). Full render of all 20 pages was refused. |
| yoa1936.pdf | 1198 | 20 ms | 4 ms | 520 MiB (532636 kB) | 5 ms | Scanned yearbook. Page 1 was 618×800 px. The next 5 pages took 329 ms. Full render of all 1198 pages was refused. |
| USCODE-2023-title26.pdf | 4211 | 22 ms | 5 ms | 529 MiB (541432 kB) | 14 ms | Text. Page 1 was 618×800 px. The next 5 pages took 39 ms. Full render of all 4211 pages was refused. Search is below. |
| Architectural Drawings.pdf | 477 | 17 ms | 5 ms | 519 MiB (531528 kB) | 5 ms | 340687335 bytes. Page 1 was 618×800 px (sampled pixels were white). The next 5 pages took 872 ms (26–285 ms each; 800×571 px). After open, 1 of 477 pages was loaded. Full render of all 477 pages was refused. |

## Text search (tax code only)

Query `income`, case-insensitive, on the already-open document, before the extra page renders. The loop is the one `PdfTextSearcher` uses: visit every page object and call `loadStructuredText`.

- 57 ms.
- Page objects visited: 4211.
- Pages whose text was actually read: 1 (the only loaded page).
- Pages still loaded after the search: 1. The search did not load the rest.
- Matches on that page: 0.

It did not walk every page's text. `loadText` returns null until that page is loaded, and this open does not load every page, so the other 4210 pages contributed no text. A separate check that loaded pages one at a time (not part of the timed search) found the first `income` on page 22. Page 1 is front matter ("TITLE 26—INTERNAL REVENUE CODE") and does not contain the word.
