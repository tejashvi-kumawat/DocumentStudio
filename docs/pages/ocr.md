# OCR & searchable PDF

## What OCR does here

Document Studio runs **Tesseract locally** (bundled on desktop releases). Pages are analyzed on your machine and a **searchable PDF** (text layer) can be produced — without uploading scans to a cloud OCR API.

## Searchable PDF — steps

1. Open a scanned or image-based PDF.  
2. Choose **Searchable PDF**.  
3. Select language if prompted (English ships with desktop engines).  
4. Start OCR and wait. Large books take minutes.  
5. Export. Try Ctrl/Cmd+F to confirm text is findable.

## Image OCR

Use **Image OCR** when the input is a standalone image rather than a multi-page PDF. Export text or a PDF depending on the tool options shown.

## Tips for better accuracy

- Prefer 300 DPI scans when you control the capture  
- Straighten skewed pages first when possible  
- Avoid heavy JPEG artifacts  
- Match the OCR language to the document script  

## Languages

Desktop bundles include base English data. Extra languages may be offered as optional downloads; those require an explicit user action and are blocked when **strict offline mode** is on.

## Performance

OCR is CPU-bound. Prefer desktop for long documents. Keep the app in the foreground on mobile for long jobs so the OS doesn’t suspend work.
