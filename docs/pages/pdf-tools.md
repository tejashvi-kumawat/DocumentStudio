# PDF tools deep dive

This page expands on PDF-centric tools. For click-by-click flows see [How to use tools](#/how-to).

## Organize family

These tools rewrite page order or membership using local PDF structure engines (primarily **qpdf** on desktop):

- Merge, split, extract, delete  
- Rotate, duplicate, reverse  
- Insert blank, insert/replace from another PDF  
- Move pages between two open documents  
- Crop (CropBox-style) and resize (MediaBox / paper size)

**Workspace** on desktop wraps many of these into a multi-document shell with a page ribbon — useful when you are assembling a packet from several sources.

## Compress

Compression balances file size and visual quality. Image-heavy scans usually benefit most. Always keep the original until you confirm the result.

## Protect

| Tool | Purpose |
| --- | --- |
| Encrypt | Add password + optional permission flags |
| Decrypt | Remove password when you know it |
| Watermark | Visible overlay for draft/confidential |
| Page numbers / header-footer | Navigation & branding |
| Redact | Permanent removal of marked content |

## Metadata

Edit fields (title, author, keywords, …) or strip metadata before sharing externally.

## Export images

Rasterize pages to PNG/JPG for slides, OCR prep, or archival previews. Watch DPI settings — higher DPI means larger images.

## Repair

Attempts to normalize broken PDF structure. Not a miracle for every corrupt file; if repair fails, try re-exporting from the original producer.
