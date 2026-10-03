# OCR

Optical character recognition turns image-like pages into searchable / selectable text.

## How it works here

Desktop releases bundle **Tesseract** and language data so OCR runs offline. The app writes a searchable PDF (or related outputs) without sending pages to a cloud OCR API.

## Typical uses

- Scanned contracts → searchable PDF  
- Camera or image imports → text you can find later  
- Accessibility-minded archives (searchable text layer)

## Languages

English ships with the desktop engines bundle. Additional languages may be offered as optional downloads; those are explicit user actions and can be blocked by strict offline mode.

## Limits

- Handwriting and very low-quality scans may need cleaner input images.
- OCR is CPU-heavy on large books — prefer desktop for big batches.
