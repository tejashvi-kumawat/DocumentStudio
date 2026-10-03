# Document Studio — public docs site

This folder is the **GitHub Pages** site for Document Studio.

- Live site: project Pages URL for [tejashvi-kumawat/DocumentStudio](https://github.com/tejashvi-kumawat/DocumentStudio) (source = `/docs`)
- Author: [Tejashvi Kumawat](https://tejashvi-kumawat.github.io)

## Local preview

```bash
cd docs
python3 -m http.server 8080
# open http://127.0.0.1:8080/
```

Do not open `index.html` as a `file://` URL — the SPA fetches `nav.json` and Markdown pages.

## Content map

| Area | Pages |
| --- | --- |
| Start | overview, install, quick-start, updates |
| Product | features, how-to, platforms, privacy, security |
| Guides | pdf-tools, ocr, office-conversion, cli |
| About | author, licenses, faq |

Private planning notes belong in `docs-local/` (gitignored), not here.
