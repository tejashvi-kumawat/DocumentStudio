# Flutter Architecture — Document Studio

## Package layout (target)

```
document_studio/                 # main app
  lib/
    app/                         # router, theme, localization bootstrap
    design_system/
    features/
      reader/
      organize/
      tools/
      settings/
    core/
      domain/
      ports/
      jobs/
    infrastructure/
    platform/
packages/
  document_studio_pdfium/        # PDFium + pdfrx wrapper (optional thin layer)
  document_studio_qpdf/          # qpdf FFI
  document_studio_ocr/           # Tesseract
  document_studio_scan/          # VisionKit + Android camera
```

Start with a single app repo; extract packages when FFI build pain justifies it (Phase 0 decision D-09).

## Routing

- **go_router** (or equivalent) with routes:
  - `/` home (recents, open)
  - `/doc/:id` viewer workspace
  - `/tools/:toolId` standalone tool flows
  - `/settings`

Deep links: `documentstudio://open?...` and platform file intents → same `/doc` route.

## State management

**Recommended:** Riverpod (ADR-006 pending).

| State type | Location |
| --- | --- |
| Open documents | `DocumentSessionNotifier` |
| Active job | `JobProgressProvider` |
| Settings / privacy | `SettingsRepository` |
| Theme | `ThemeMode` provider |

Avoid storing `Uint8List` of whole PDF in providers; hold engine handles + paths.

## Responsive layout

Use `LayoutBuilder` / breakpoints from master spec §18:

| Width | Shell |
| --- | --- |
| < 600 | Bottom nav, full-screen doc |
| 600–1024 | Navigation rail |
| > 1024 | Sidebar + workspace + inspector |

Shared `DocumentWorkspaceScaffold` parameterized by slot widgets.

## Platform channels

| Feature | Channel owner |
| --- | --- |
| Android SAF persistable URI | `platform/android/storage.dart` |
| iOS security-scoped bookmark | `platform/ios/storage.dart` |
| File associations | per-platform method channel |
| iOS VisionKit scanner | `document_studio_scan` |
| Android CameraX scan | `document_studio_scan` |

## FFI boundaries

- Load native libs once at startup (`pdfrxInitialize`, qpdf init).
- All FFI in `packages/*` or `infrastructure/ffi/`; expose only Dart ports to app.

## Testing hooks

- Inject fake `PdfRenderPort` / `PdfStructurePort` for widget tests.
- Golden tests for design system components only in `design_system/`.

## Forbidden patterns

- `import 'dart:ffi'` in `features/**/presentation`
- Direct `MethodChannel` calls from widgets (wrap in platform services)
- Multiple merge implementations
