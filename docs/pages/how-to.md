# How to use tools

Exact labels can vary slightly by platform, but the flow is always: **open → choose tool → options → Apply / Save**.

![Tools hub](../images/tools-home.png)

---

## Before any tool

1. Install Document Studio ([Download & install](#/install)).
2. Open a PDF from Home, drag-and-drop, Browse, or “Open with”.
3. Save exports to a folder you control.
4. Keep passwords ready for encrypted PDFs.

---

## Home dashboard

![Home — Open, Create, Images to PDF, All tools](../images/image.png)

1. Launch **Document Studio**.
2. Use **Open PDF**, **Create PDF**, **Images to PDF**, or **All tools**.
3. Or drop files on the drop zone / Browse.
4. Pin important files with the star; they stay local.

---

## Organize pages

![Organize panel](../images/organize.png)

1. Open a PDF → **Organize**.
2. Click pages to select · drag to reorder.
3. Use Left / Right rotate, Duplicate, Delete, Reverse.
4. **Apply**.

---

## Merge

![Merge](../images/merge.png)

1. Open **Merge** (tools or organize hub).
2. **+ Add PDFs** in the order you want.
3. **Save** or **Save as**.

Encrypted sources need the password first (lock icon means protected).

---

## Split

![Split](../images/split.png)

1. Open PDF → **Split**.
2. Choose: Every N pages · After pages · Custom ranges · Odd/even · Each page.
3. Check the **Result** list.
4. **Split** — the open document stays as it is.

---

## Extract pages

![Extract pages](../images/extract-pages.png)

1. **Extract pages**.
2. This page / Selected / All / Range.
3. Optional: **Delete after extract**.
4. **Extract**.

---

## Insert pages

![Insert pages](../images/insert-pages.png)

1. **Insert pages**.
2. Pick another PDF (every page inserts after the chosen page).
3. **Insert**.

---

## Crop

![Crop](../images/crop.png)

1. **Crop**.
2. Pick preset (Full page / Small margins / Wide margins) or drag the box.
3. Scope: This page / Selected / All / Range.
4. **Crop**.

---

## Resize pages

![Resize pages](../images/resize-pages.png)

1. **Resize page**.
2. Choose LETTER / A4 / LEGAL (sets MediaBox & CropBox — content is not scaled).
3. Scope → **Apply**.

---

## Header & footer

![Header and footer](../images/header-footer.png)

1. **Header and footer**.
2. Pick a template (Minimal page number, Page X of Y, Corporate, Legal Bates, …).
3. Click a position on the 2×3 grid.
4. Edit text; insert variables: Page, Date, File, Title, Bates.
5. Font / bold / size → **Apply** (or Save as template).

---

## Page numbers

![Page numbers](../images/page-numbers.png)

1. **Page numbers**.
2. All or From–to range.
3. Style, prefix, start number, section options.
4. **Apply**.

---

## Watermark

![Watermark](../images/watermark.png)

1. **Watermark**.
2. Text or Image tab.
3. Enter text (or tokens `{page}` `{date}` …) · font · size · color · opacity · rotation · position grid.
4. Optional: replace existing watermark.
5. **Apply**.

---

## Encrypt

![Encrypt](../images/encrypt.png)

1. **Encrypt**.
2. Password to open · optional owner password.
3. Toggle Allow printing / copying / modifying / annotating.
4. **Encrypt**.
5. Store the password — Document Studio cannot recover it.

---

## Decrypt

1. **Decrypt** / Unlock.
2. Enter the correct password.
3. Export an unprotected copy if needed.

No password → no unlock. The app will not crack encryption.

---

## Visual sign (signatures & initials)

![Visual Sign](../images/sign-visual.png)

1. Open **Sign PDF** → **Sign** tab.
2. **+ New** signature or initials (draw / type).
3. Tap a card, drag a box on the page (or long-press and drag).
4. Move / resize / rotate → Apply.

---

## Digital / certificate signature

![Digital Sign](../images/sign-digital.png)

1. **Sign PDF** → **Digital** tab.
2. Review validation status of existing signatures.
3. **Draw new signature field** if needed.
4. Pick a Digital ID from USB token / smart card / browser & system (NSS) stores.
5. Or **Import .p12** / **Create self-signed**.
6. Complete the sign flow and save.

Stamps live under the **Stamps** tab (Approved, dates, custom).

---

## Edit & markup

![Edit markup](../images/edit-markup.png)

1. Click **Edit** on the ribbon (or markup tools).
2. Select text to change fonts, size, bold/italic, alignment, line spacing.
3. Use Highlight / Underline / Strikethrough / Squiggly.
4. Draw, erase, add shapes, text boxes, comments, images, links, digital sign from Insert.
5. Changes save in the PDF (“Saved in the PDF” status).

---

## Insert scan

![Insert scan](../images/insert-scan.png)

1. **Insert scan**.
2. **Open camera** or **Choose images…**.
3. Place the new page(s) into the PDF and save.

---

## Compress

1. Open PDF → **Compress**.
2. Pick a quality / size preset.
3. Run → save the smaller file. Keep the original until you verify.

---

## Searchable PDF (OCR)

1. Open a scanned PDF → **Searchable PDF**.
2. Pick language if prompted.
3. Run OCR (CPU-heavy on long books).
4. Export and try Find (Ctrl/Cmd+F).

Details: [OCR guide](#/ocr).

---

## Office → PDF (desktop)

1. **From Office** / Office convert.
2. Pick `.docx` / `.xlsx` / `.pptx` (etc.).
3. Convert → open the PDF to verify layout.

Needs bundled LibreOffice (official Setup / DMG / deb). See [Office conversion](#/office-conversion).

---

## Images → PDF / PDF → images

1. **Images to PDF** — add images, reorder, export.
2. **PDF to images** — choose PNG/JPEG (and DPI if offered), export to a folder.

---

## Fill form

1. **Fill PDF form**.
2. Click fields and type values.
3. Save so filled values persist.

---

## Compare PDFs

1. **Compare PDFs**.
2. Choose document A and B.
3. Review differences → export if offered.

---

## Batch / metadata

1. **Batch** — pick an operation and a file list/folder → run.
2. **Edit metadata** / **Remove metadata** — update or strip Info & XMP.

---

## From the command line

```bash
document_studio ~/file.pdf
document_studio --tool compress ~/file.pdf
document_studio --tool merge a.pdf b.pdf
document_studio --update
```

More: [CLI & Windows shell](#/cli).

---

## If something fails

| Problem | Try |
| --- | --- |
| Tool missing | Reinstall full release (not a slim skip-engines build) |
| Office convert missing | Desktop only · confirm LibreOffice bundled |
| OCR slow | Normal on large scans |
| App not in menu | Reinstall Setup / deb / DMG — [FAQ](#/faq) |
| Password errors | Caps-lock / correct password |

Still stuck? [Open an issue](https://github.com/tejashvi-kumawat/DocumentStudio/issues).
