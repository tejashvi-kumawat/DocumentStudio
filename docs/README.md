# Document Studio — GitHub Pages

Public documentation site (not internal planning notes).

| Path | Role |
| --- | --- |
| `index.html` | Designed shell |
| `assets/` | CSS / JS |
| `nav.json` | Navigation |
| `pages/` | Public markdown guides |

Private planning docs live in **`docs-local/`** (gitignored) and are **not** published here.

## Preview

```bash
python3 -m http.server 8080 --directory docs
```

## GitHub Pages

Settings → Pages → Deploy from branch → `main` → `/docs`.
