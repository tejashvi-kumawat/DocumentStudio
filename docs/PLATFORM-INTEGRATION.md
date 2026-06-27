# Platform Integration — Document Studio

## Android

| Integration | Implementation |
| --- | --- |
| Min SDK | 24 recommended (qpdf/Tesseract alignment) |
| Storage | SAF via `file_picker`; persistable URI permission |
| Share in | `ACTION_SEND` / `ACTION_VIEW` intent filters for PDF, images |
| Share out | `share_plus` |
| Camera | `CAMERA` permission; CameraX in scan plugin |
| Long jobs | Foreground service + notification (OCR/batch) when required by OS |
| Scoped storage | Never assume `/sdcard` raw paths for user files |
| Tablets | Two-pane layout; stylus as touch with pressure optional later |
| File associations | Intent filters; optional `assetlinks` not required |

**MainActivity:** must call `super.onActivityResult` if overriding (file picker).

## iOS / iPadOS

| Integration | Implementation |
| --- | --- |
| Min iOS | 14+ picker; 15+ if optional ML Kit |
| Documents | `UIDocumentPicker`; security-scoped access |
| Share | `UIActivityViewController` |
| Open in | Document types UTType PDF, images |
| Camera / scan | VisionKit document camera (ADR-007) |
| iPad | Multitasking safe layouts; pointer/hover for toolbar |
| Pencil | Apple Pencil drawing in annotate mode |
| Background | OCR must pause/resume; save state |

**Entitlements:** document picker, camera usage strings in Info.plist.

## macOS

| Integration | Implementation |
| --- | --- |
| Sandbox | App sandbox with user-selected read/write entitlements for pickers |
| Menu bar | Native menus for Open/Save/Print where idiomatic |
| Drag-drop | Register drop target on window |
| Print | `printing` package entitlements |
| Finder | UTType exports; “Open with” via Info.plist |
| LibreOffice | Detect `/Applications/LibreOffice.app` or PATH |

## Windows

| Integration | Implementation |
| --- | --- |
| File assoc | Registry/progids at install (MSIX/Inno—see RELEASE.md) |
| Drag-drop | `DropTarget` via Flutter desktop |
| Developer Mode | pdfrx build note for symlinks if applicable |
| Print | Win32 print dialog via `printing` |
| LO | Program Files detection |

## Linux

| Integration | Implementation |
| --- | --- |
| File picker | GTK portal via file_picker |
| MIME | `.desktop` file `MimeType=application/pdf` |
| Print | CUPS via `printing` |
| LO | `soffice` on PATH |
| musl | PDFium prebuilt may differ—best effort |

## Cross-platform deep links

- Custom scheme `documentstudio://open` optional
- Primary: OS “Open with Document Studio”

## Platform channel map

| Channel | Android | iOS | macOS | Win | Linux |
| --- | --- | --- | --- | --- | --- |
| scan | ✓ | ✓ | — | — | — |
| storage_helper | ✓ | ✓ | ✓ | ✓ | ✓ |
| file_association | ✓ | ✓ | ✓ | ✓ | ✓ |
| lo_detector | — | — | ✓ | ✓ | ✓ |

## Testing

- Manual matrix checklist per release
- Integration tests on Linux CI; device farm for mobile quarterly
