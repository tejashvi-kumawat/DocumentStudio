# Office conversion

## Desktop releases

Official **Windows Setup**, **macOS DMG**, and **Linux .deb** builds bundle **LibreOffice** so you can convert Office-style documents to PDF offline with strong layout fidelity.

## Convert Office → PDF

1. Open Document Studio on desktop.  
2. Open **Office convert**.  
3. Pick `.docx`, `.xlsx`, `.pptx`, or related formats the picker allows.  
4. Convert and save the PDF.  
5. Open the PDF to verify fonts and layout.

## Limits

| Topic | Reality |
| --- | --- |
| Mobile | Office stack not bundled — convert on desktop |
| Macros | Not a macro runtime; expect static layout export |
| Exotic fonts | Embed or substitute may differ from Microsoft Office |
| PDF → Office | Best-effort / limited compared to → PDF |

## If convert is missing

Reinstall the full release artifact from GitHub Releases. Custom builds that set `DS_SKIP_LIBREOFFICE=1` intentionally omit this engine.
