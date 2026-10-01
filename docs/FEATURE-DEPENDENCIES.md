# Feature Dependency Graph — Document Studio

Dependencies are **logical** (must exist before or during). Arrows read as “depends on”.

## Foundation stack

```mermaid
flowchart TB
  subgraph foundation [Phase 0 Foundation]
    FS[FileStoragePort]
    TR[Tool Registry]
    JR[Job Runner]
    DS[Design System]
    ERR[Error Model]
  end

  subgraph pdf_core [PDF Core]
    PR[PdfRenderPort PDFium]
    PS[PdfStructurePort qpdf]
    PM[PdfDocumentSession]
  end

  FS --> PM
  TR --> JR
  PR --> PM
  PS --> PM
```

## Viewer chain

```mermaid
flowchart LR
  V[PDF Viewer UI] --> PM
  PM --> PR
  V --> TH[Thumbnail Cache]
  TH --> PR
  V --> SRCH[Text Search]
  SRCH --> PR
  V --> SEL[Text Selection]
  SEL --> PR
```

## Organization chain

```mermaid
flowchart LR
  ORG[Page Organizer UI] --> PM
  ORG --> PS
  ORG --> PREV[Page Preview Render]
  PREV --> PR
  MERGE[Merge/Split] --> PS
```

## Creation chain

```mermaid
flowchart LR
  CR[PDF Creation Tools] --> PR
  CR --> PS
  IMG2PDF[Images to PDF] --> IM[ImagePort]
  IM --> CR
  SCAN[Scanner] --> IM
  SCAN --> CR
  OFF2PDF[Office to PDF] --> LO[LibreOffice Process]
  LO --> CR
```

## Edit & annotation chain

```mermaid
flowchart TB
  ANN[Annotation Tools] --> PA[PdfAnnotationPort]
  PA --> PR
  ED[Content Editor] --> PE[PdfEditPort]
  PE --> PR
  ED --> VT[PdfViewportTransform]
  ANN --> VT
  UNDO[Undo Stack] --> ED
  UNDO --> ANN
  SAVE[Save Pipeline] --> PS
  ED --> SAVE
  ANN --> SAVE
```

## OCR chain

```mermaid
flowchart LR
  OCR[OCR Tool] --> PRE[Image Preprocess]
  PRE --> IM
  OCR --> OP[OcrPort Tesseract]
  OP --> SL[Searchable PDF Merger]
  SL --> PR
  SL --> PS
  SCAN --> OCR
```

## Security chain

```mermaid
flowchart LR
  ENC[Encrypt/Permissions] --> PS
  RED[Redaction] --> PS
  RED --> PR
  RED --> VERIFY[Post-redact text extract test]
  VERIFY --> PR
  META[Metadata strip] --> PS
```

## Forms & signatures

```mermaid
flowchart LR
  FORM[Form Fill] --> PF[PdfFormPort]
  PF --> PR
  VSIG[Visual Signature] --> PE
  DSIG[Digital Signature] --> CRYPTO[Crypto CMS/PAdES lib]
  CRYPTO --> PS
  DSIG --> R[R]
```

## Conversion chain

```mermaid
flowchart TB
  CNV[ConversionPort] --> PR
  CNV --> PS
  CNV --> IM
  CNV --> LO
  CNV --> TXT[Text/HTML/MD layout]
```

## Advanced

```mermaid
flowchart LR
  CMP[Compare] --> PR
  CMP --> DIFF[Text diff engine]
  REP[Repair] --> PS
  PDFA[PDF/A] --> PS
  PDFA --> VERA[veraPDF CLI optional]
  ATT[Attachments] --> PS
  BMK[Bookmarks] --> PS
```

## Batch & workflow

```mermaid
flowchart LR
  BATCH[Batch Runner] --> TR
  BATCH --> JR
  FLOW[Workflow Engine] --> TR
  FLOW --> BATCH
```

## Cross-cutting dependencies

| Feature area | Hard depends on |
| --- | --- |
| All tools | FileStoragePort, Error model, JobRunner |
| Any PDF write | PdfStructurePort or PdfRenderPort save path |
| Desktop Office | LibreOffice detect + subprocess sandbox |
| Searchable OCR | PdfRenderPort + OcrPort + merge |
| Compare side-by-side | Two PdfDocumentSession + sync controller |
| Workflows | Stable tool IDs + serial temp dir |
| Accessibility check | Text extract + structure introspection (limited) |

## Parallel tracks (can develop concurrently after Phase 0)

- **Track A:** Viewer + File shell (Phase 1)
- **Track B:** qpdf plugin (Phase 2)
- **Track C:** Image + create PDF (Phase 3)
- **Track D:** OCR plugin (Phase 6)

Editing (Phase 5) must not start before Viewer transform + annotation port design (Phase 4 partial).

## Versioning

When a port API changes, update this graph and ADR in [DECISIONS.md](DECISIONS.md).
