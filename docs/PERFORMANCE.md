# Performance — Document Studio

Targets are guidance until Phase 1 benchmarks exist. Update this file with measured numbers.

## Principles

1. UI thread never blocked on OCR, merge, or full-document encode.
2. Bound memory with LRU caches and page streaming.
3. User can cancel long jobs.
4. Degrade gracefully on low-RAM devices.

## Targets (initial)

| Scenario | Phone (mid) | Desktop |
| --- | --- | --- |
| Cold start to home | < 3 s | < 2 s |
| Open 10 MB / 50 pp PDF, first page | < 2 s | < 1 s |
| Cached page pan/zoom | 60 fps target | 60 fps |
| Merge 500 pages | background | < 60 s guidance |
| OCR 20 pages @ 300 DPI | background, minutes OK | faster |
| Compress 100 MB image-heavy | background | background |

## PDF rendering

- Tile pages above zoom threshold
- LRU cache: default 30–80 MB budget phone, 200+ MB desktop (settings advanced)
- Progressive page load (`loadPagesProgressively` when available)
- Thumbnails: lower DPI separate cache

## Isolates / workers

| Work | Executor |
| --- | --- |
| Image encode/decode | Dart isolate |
| OCR page | Native thread pool or isolate per page |
| qpdf merge | Native FFI async wrapper |
| LO convert | Separate process (already isolated) |

## Mobile constraints

- iOS: suspend OCR on background; checkpoint progress
- Android: use foreground service for batch > 30 s
- Avoid holding full PDF bytes in Dart `Uint8List` > 32 MB

## Disk

- Temp on fast app storage; preflight free space > 1.5× input size for merge/OCR

## Benchmark harness (Phase 0+)

- `benchmark/open_pdf.dart` — time to first raster
- `benchmark/merge_100.dart` — qpdf path
- Store results in `docs/perf/` JSON for CI regression (optional)

## Profiling

- Flutter DevTools for UI jank
- Native profilers for PDFium/qpdf hot paths
- Log slow ops > threshold in debug only (no content)

## User settings (advanced)

- Render quality / max cache MB
- OCR DPI cap
- Disable animations on low power mode (optional)
