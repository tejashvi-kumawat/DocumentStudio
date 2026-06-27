# Image Engine — Document Studio

## Role

Decode, transform, encode images for tools (convert, compress, scan post-process, PDF lossy compress, thumbnails).

## Primary library

**`image` package (Dart, MIT)** — run heavy work in isolates via `Command.executeThread()`.

## Supported formats (target)

| Format | Read | Write | Notes |
| --- | --- | --- | --- |
| JPEG | Yes | Yes | Quality slider |
| PNG | Yes | Yes | Alpha preserved |
| WebP | Yes | Lossless write | `image_webp` optional |
| TIFF | Yes | Limited | Multi-page → multi PDF pages |
| BMP | Yes | Yes | |
| SVG | Rasterize only | No | `resvg` FFI optional Phase 6+ (MIT/Apache) |
| GIF | Read | Optional | Animated → frames choice |

## ImagePort (conceptual)

```dart
Future<ImageDocument> decode(Uint8List bytes, CancelToken cancel);
Future<Uint8List> encode(ImageDocument doc, ImageFormat format, EncodeOptions opts);
Future<ImageDocument> transform(ImageDocument doc, TransformOps ops);
```

## Operations

- Resize (LANCzos / image package filters)
- Crop, rotate, flip
- Grayscale
- Compress JPEG with quality
- Strip EXIF/metadata where encoder allows

## Performance

- Max dimension guard (e.g. 8192 px) configurable
- Stream large TIFF pages one at a time

## Integration points

| Feature | Usage |
| --- | --- |
| DS-CNV-IMAGE-PDF | decode → PDF page |
| DS-OPT-COMPRESS | PDFium render → reencode JPEG |
| DS-SCAN | camera JPEG → enhance → PDF |
| DS-OCR | preprocess before Tesseract |

## Dependencies

- `image` (required)
- `image_webp` (optional)
- `fast_image_resize` — evaluate if pure Dart too slow on desktop batch

## Tests

- Resize 4000×3000 → 800 width maintains aspect
- PNG alpha survives round-trip

## Licensing

MIT stack only in default build.
