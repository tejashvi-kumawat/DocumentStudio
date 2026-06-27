# Technology Stack — Document Studio

Summary of recommended stack. Authoritative detail: [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md) sections 11–16 and [DECISIONS.md](DECISIONS.md).

| Layer | Choice | Status |
| --- | --- | --- |
| Application framework | Flutter (Dart 3.x) | Accepted (ADR-001) |
| PDF render / viewer | PDFium via pdfrx ecosystem | Proposed (ADR-002) |
| PDF structure / crypto / repair | qpdf (FFI plugin) | Proposed (ADR-003) |
| OCR | Tesseract 5 | Proposed (ADR-004) |
| Images | `image` package (Dart isolates) | Planned |
| Office → PDF | LibreOffice headless (desktop) | Proposed (ADR-005) |
| Print | `printing` | Planned |
| Files | `file_picker`, platform channels for SAF | Planned |
| iOS scan | VisionKit | Proposed (ADR-007) |
| Android scan | CameraX + OpenCV-class pipeline | Proposed (ADR-007) |
| State management | Riverpod (recommended) | Pending (ADR-006) |

## Not in stack

Web as primary SKU, Node/Python backends, cloud convert/OCR, Syncfusion core, MuPDF/Ghostscript linked in app, local LLMs.

## Version pinning policy

Pin versions in `pubspec.lock` and native submodule tags at Phase 0 start; record in this file and [DEPENDENCIES.md](DEPENDENCIES.md).

## Build tooling (when Phase 0 starts)

- Flutter stable channel (exact version recorded at init)
- Rust or C++ toolchain only inside engine plugin packages (qpdf build)
- CMake for qpdf native builds
- CocoaPods / SPM for iOS PDFium XCFramework (via pdfium_flutter)
