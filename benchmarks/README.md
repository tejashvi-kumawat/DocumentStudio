# Local PDF stress files

Downloaded for local viewer stress tests. The PDFs are gitignored. Sizes and page counts were checked after download (`%PDF` magic, then `pdfinfo`).

| File | Bytes | Pages | Stress | Source |
| --- | ---: | ---: | --- | --- |
| `NZERTF-Architectural-Plans1-June2011.pdf` | 8661300 | 20 | Vector / CAD geometry. Large-format sheets (1728×2592 pt). The file named in [pdf.js #4761](https://github.com/mozilla/pdf.js/issues/4761) and [Hacker News 7716022](https://news.ycombinator.com/item?id=7716022). | https://www.nist.gov/system/files/documents/2017/04/28/NZERTF-Architectural-Plans1-June2011.pdf |
| `yoa1936.pdf` | 161565366 | 1198 | Scanned / image-heavy. USDA National Agricultural Library scan of the 1936 *Yearbook of Agriculture* (U.S. government work). Page images are mostly 600 ppi JBIG2. | https://archive.org/download/yoa1936/yoa1936.pdf |
| `USCODE-2023-title26.pdf` | 16813001 | 4211 | Font-dense / structured text. United States Code, Title 26 (Internal Revenue Code), 2023 edition. U.S. government work, GPO/govinfo. | https://www.govinfo.gov/content/pkg/USCODE-2023-title26/pdf/USCODE-2023-title26.pdf |

Total: 187039667 bytes.

## Not downloaded

- `https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf` returned HTTP 404.
- Hugging Face `piushorn/pdf-parse-bench` is public and ungated, with direct PDF URLs, but the files are short synthetic formula/table samples (sample `2026-q1-formulas-only/pdfs/000.pdf` is 169543 bytes). They are not a long document, so Title 26 was used for the text stress instead.
- Multi-gigabyte archive scans (for example Internet Archive item `parkinsontheatrumbotanicum`, about 2.1 GB) were skipped. The 1936 yearbook PDF is the smaller public scan.
- `https://asc67.org/ASC_Previous_Problems/Open/IP/2018/Drawings/Architectural%20Drawings.pdf` (about 325 MB) was not downloaded. It is a competition drawing set, not the public NIST file.
