# Product Requirements — Document Studio

Extracted from [MASTER-SPECIFICATION.md](MASTER-SPECIFICATION.md). For narrative spec, use the master document.

## Functional requirements (summary)

| Area | Requirement |
| --- | --- |
| Reader | Open, navigate, zoom, search, select, bookmarks view, print/share path |
| Organize | Merge, split, extract, delete, reorder, rotate, insert, duplicate |
| Convert | Image↔PDF all platforms; Office↔PDF desktop; fidelity labels |
| Compress | Profiles + stats; lossy opt-in |
| Annotate | Standard markup + list |
| Edit | Add content + limited true edit; undo/autosave |
| OCR/Scan | Tesseract; VisionKit/CameraX scan |
| Security | Encrypt, permissions, redaction, metadata strip |
| Forms/Sign | Fill/flatten; visual signature |
| Advanced | Compare, repair, PDF/A, bookmarks/links/attachments |
| Batch/Workflow | Local queue and saved steps |

## Non-functional requirements

| ID | Requirement |
| --- | --- |
| NFR-01 | Non-blocking UI for heavy work |
| NFR-02 | Memory-bounded PDF/image handling |
| NFR-03 | Lazy engine/language load |
| NFR-04 | Accessibility (Semantics, keyboard) |
| NFR-05 | UI i18n ready |
| NFR-06 | Atomic writes; crash recovery for editor |
| NFR-07 | Untrusted input handling |
| NFR-08 | Single tool registry |
| NFR-09 | License compliance |
| NFR-10 | Tests per feature |

## Constraints

See master spec NC-01 … NC-10: free, ad-free, local, offline, no backend, no AI, no document upload.

## Platform requirements

- Flutter app: Android, iOS, Windows, macOS, Linux
- Responsive layouts: phone / tablet / desktop
- Mobile: SAF, Files, camera, share, background limits
- Desktop: associations, DnD, shortcuts, LO

## Out of scope

Cloud collaboration, cloud e-sign routing, accounts, ads, web-primary product, password cracking, LLM features.

## Traceability

Feature IDs `DS-*` in master spec §6 map to `features/*.md` specs.
