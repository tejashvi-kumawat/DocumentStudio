# Engines

Desktop releases ship an `engines/` tree next to the app so users don’t hunt for dependencies.

| Engine | Role |
| --- | --- |
| **qpdf** | PDF structure, encryption, compression, page operations |
| **Tesseract** | OCR / searchable PDF |
| **LibreOffice** | Office → PDF conversion |
| **Poppler tools** | Helpers such as `pdfsig` where used |
| **NSS / OpenSSL** | Certificate / crypto helpers |
| **ffmpeg** | Media-related helpers when needed |

## Licensing

Bundled third-party components keep their own licenses. See [Licenses](#/licenses) and the `THIRD_PARTY_LICENSES` folder in release packages.

## Custom builds

Advanced builders can set environment overrides (for example skipping LibreOffice) when producing slim artifacts. Official GitHub Release installers are the full engine set.
