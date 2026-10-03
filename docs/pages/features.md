# Feature list

Everything below runs **offline** on your device. Desktop release builds bundle the engines they need (qpdf, Tesseract, LibreOffice, signing helpers, …).

Screenshots below are from the real app. Tools without a screenshot are still available — see the text sections.

![Tools home — Create PDF, Organize, PDF to images, Compress, Encrypt, Scan](../images/tools-home.png)

![Full tools catalog — Optimize, Sign, Edit, Create](../images/tools-catalog.png)

---

## Home & library

| Feature | What it does |
| --- | --- |
| Open PDF | Open from disk, drag-and-drop, or Browse |
| Create PDF | Blank / from plain text |
| Images to PDF | Combine photos & scans into one PDF |
| PDF to images | Export pages as PNG or JPEG |
| Pinned & recent | Local library only — no cloud sync |
| Workspace | Multi-document desktop shell |
| Tools hub | Searchable grid of every tool |
| Strict offline | Blocks optional downloads when enabled |

![Document Studio home dashboard](../images/image.png)

---

## Organize pages

| Feature | Notes |
| --- | --- |
| Organize | Drag thumbnails · rotate · duplicate · delete · reverse · Apply |
| Merge | Add PDFs in order · Save / Save as |
| Split | Every N · after pages · custom ranges · odd/even · each page |
| Extract pages | This page / selected / all / range · optional delete after extract |
| Insert pages | Insert every page of another PDF after a chosen page |
| Crop | Full page / small / wide margins · live crop box |
| Resize pages | LETTER / A4 / LEGAL (MediaBox / CropBox; content not scaled) |
| Rotate | Ribbon rotate or organize actions |
| Add blank page | Insert empty pages |
| Move between docs | Dual-document move in Workspace |

![Organize — reorder and rotate pages](../images/organize.png)

![Merge PDFs](../images/merge.png)

![Split PDF with result preview](../images/split.png)

![Extract pages](../images/extract-pages.png)

![Crop pages](../images/crop.png)

![Resize pages](../images/resize-pages.png)

![Insert pages from another PDF](../images/insert-pages.png)

---

## Optimize

| Feature | Notes |
| --- | --- |
| Compress PDF | Reduce file size with quality tradeoffs |
| Watermark | Text or image · opacity · rotation · position grid · tokens |
| Batch | One operation on many files |
| Edit metadata | Title, author, properties |
| Remove metadata | Strip Info and XMP before sharing |
| Repair PDF | Structure repair via engines |

![Watermark — text, opacity, rotation, position](../images/watermark.png)

---

## Protect & stamp

| Feature | Notes |
| --- | --- |
| Encrypt | Open password · owner password · print/copy/modify/annotate permissions |
| Decrypt | Unlock when you know the password (no cracking) |
| Header & footer | Templates · position grid · `{page}` `{pages}` `{date}` `{file}` `{title}` `{bates}` |
| Page numbers | Style · prefix · start · sectioning |
| Redact | Remove underlying content — not paint-only |

![Encrypt with passwords and permissions](../images/encrypt.png)

![Header and footer templates](../images/header-footer.png)

![Page numbers](../images/page-numbers.png)

---

## Sign & forms

| Feature | Notes |
| --- | --- |
| Visual Sign | Draw / type signatures & initials · drag onto page · resize/rotate |
| Stamps | Approved, dates, custom stamps |
| Certificate signature | Digital IDs · import `.p12` · create self-signed · USB token / NSS stores · validate |
| Fill form | Fill AcroForm fields and save |

![Sign PDF — digital certificates and validation](../images/sign-digital.png)

![Sign PDF — visual signatures and initials](../images/sign-visual.png)

---

## Edit & markup

| Feature | Notes |
| --- | --- |
| Edit text | Select / replace existing text · font · size · alignment · line spacing |
| Highlight / underline / strikethrough / squiggly | Text markup |
| Freehand / eraser | Ink draw |
| Shapes | Rectangle, circle, line, arrow, pentagon, cloud, … |
| Comments | Sticky notes |
| Add image | Stamp an image onto a page |
| Link | URI or internal page links |
| Smart guides | Snap for clean alignment |
| Compare PDFs | Diff text, images, and pages |

![Edit & markup tools](../images/edit-markup.png)

![Pages tools list in the Tools panel](../images/tools-pages.png)

---

## Capture & OCR

| Feature | Notes |
| --- | --- |
| Insert scan | Open camera or choose images |
| Searchable PDF (OCR) | Local Tesseract — text layer for scans |
| Image OCR | OCR on standalone images |

![Insert scan — camera or choose images](../images/insert-scan.png)

---

## Convert & create

| Feature | Notes |
| --- | --- |
| From Office | Word / Excel / PowerPoint → PDF (desktop, bundled LibreOffice) |
| Images to PDF | Multi-image compose |
| PDF to images | PNG / JPEG export |
| Create PDF | From plain text |
| Place image | Stamp image into PDF |

---

## Platform extras

| Feature | Notes |
| --- | --- |
| CLI | `document_studio` open / `--tool` / `--update` |
| Windows shell | Start Menu · Open with · context menus after Setup.exe |
| App search | Start / Spotlight / Activities after proper install |

---

## Intentionally not included

| Not a feature | Why |
| --- | --- |
| Upload PDF to our cloud | Privacy — we don’t run that |
| Crack PDF passwords | Illegal / dishonest |
| Fake redaction | Leaves text in the file |
| Ads / account wall | Product principle |

Step-by-step for each major tool: [How to use tools](#/how-to).
