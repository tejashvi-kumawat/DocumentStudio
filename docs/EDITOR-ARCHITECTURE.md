# Editor Architecture — Document Studio

## Modes

| Mode | Domain enum | Persists as |
| --- | --- | --- |
| View | `DocumentMode.view` | — |
| Annotate | `DocumentMode.annotate` | PDF annotations |
| Edit | `DocumentMode.edit` | Page content objects |
| Organize | `DocumentMode.organize` | Page tree rewrite |
| Redact | `DocumentMode.redact` | Content removal |

Only one **destructive** mode active at a time; switching prompts save/discard.

## Session model

```text
EditSession
  documentId
  undoStack: List<EditCommand>
  redoStack
  dirty: bool
  autosaveCheckpoint: File? (temp)
```

Commands implement:

- `execute(EditContext ctx)`
- `revert(EditContext ctx)`
- `describe()` for undo menu (optional)

## Coordinate system

Central `PdfViewportTransform`:

- `pdfPointToFlutter(Offset pdf)`
- `flutterToPdfPoint(Offset ui)`
- Account for page rotation, crop box, zoom, scroll offset

All hit-testing for annotations/edit uses this transform.

## Object model

| Type | Wrapper |
| --- | --- |
| Text markup | `TextMarkupAnnotation` |
| Note | `TextAnnotation` |
| Ink | `InkAnnotation` |
| Page text object | `PageTextObject` (edit) |
| Image object | `PageImageObject` |

Engine IDs opaque (`ObjectHandle`).

## Commit flow

1. In-memory / incremental engine edits during session
2. **Save:** normalize via qpdf optional pass → atomic write
3. **Discard:** reload document from last committed path

## True edit vs overlay

| User action | Implementation |
| --- | --- |
| Add text box | New `FPDF_PAGEOBJ_TEXT` |
| Edit existing glyph run | `FPDFText_SetText` only if font supports Unicode |
| Highlight | Annotation quad points |
| “Whiteout” without redact | **Forbidden** for security tool—use redact mode |

## Flatten

- Annotations → page content (raster or vector) via engine
- Irreversible—confirm dialog

## Related specs

[DS-ANN-ANNOTATION.md](../features/DS-ANN-ANNOTATION.md), [DS-EDIT-CONTENT.md](../features/DS-EDIT-CONTENT.md), [PDF-ENGINE.md](PDF-ENGINE.md)
