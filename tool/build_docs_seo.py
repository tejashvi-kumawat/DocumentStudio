#!/usr/bin/env python3
"""Make the Document Studio website crawlable.

The site is a single-page app whose docs live behind `#/page` URLs, which search
engines treat as ONE page. This script writes a real, pre-rendered page per doc
(docs/<id>/index.html) plus docs/sitemap.xml. The SPA is
untouched; visitors still use it from the home page.

    pip install markdown pyyaml
    python tool/build_docs_seo.py
"""
import html
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SITE = "https://tejashvi-kumawat.github.io/DocumentStudio"
REPO = "https://github.com/tejashvi-kumawat/DocumentStudio"
OG_IMAGE = f"{SITE}/assets/img/logo.png"
FONTS = (
    "https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700&"
    "family=IBM+Plex+Mono:wght@400;500&family=Syne:wght@600;700;800&display=swap"
)


def esc(s):
    return html.escape(str(s), quote=True)


def plain(text, limit=300):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[#>*_`|-]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit].rsplit(" ", 1)[0] + "…" if len(text) > limit else text


def first_paragraph(md):
    for block in re.split(r"\n\s*\n", md):
        b = block.strip()
        if b and not b.startswith(("#", "<", "|", "-", "```", "!", ">")):
            return plain(b, 200)
    return plain(md, 200)


def fix_links(body, ids):
    def link(m):
        href = m.group(2)
        if href.startswith(("http", "mailto:")):
            return m.group(0)
        if href.startswith("#/"):
            return f'{m.group(1)}"../{href[2:].split("?")[0]}/"'
        if href.startswith("../") and "images/" not in href:
            return f'{m.group(1)}"{REPO}"'
        clean = href.split("#")[0].lstrip("./")
        hit = next((i for i, f in ids.items() if f == clean), None)
        return f'{m.group(1)}"../{hit}/"' if hit else m.group(0)

    return re.sub(r'(href=)"([^"]*)"', link, body)


def main():
    nav = json.loads((DOCS / "nav.json").read_text(encoding="utf-8"))
    items = [(s["title"], i) for s in nav["sections"] for i in s["items"]]
    ids = {i["id"]: i["file"] for _, i in items}
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    sidebar = "".join(
        f'<div class="nav-section"><h2>{esc(s["title"])}</h2>'
        + "".join(f'<a href="../{i["id"]}/" data-id="{i["id"]}">{esc(i["title"])}</a>' for i in s["items"])
        + "</div>"
        for s in nav["sections"]
    )
    urls = [(f"{SITE}/", "1.0")]
    for section, item in items:
        md = (DOCS / "pages" / item["file"]).read_text(encoding="utf-8")
        md_body = re.sub(r"^\s*# .*\n", "", md, count=1)  # the page header already shows the title
        body = markdown.markdown(md_body, extensions=["tables", "fenced_code", "sane_lists"])
        body = fix_links(body, ids)
        title = f'{item["title"]} · Document Studio'
        desc = first_paragraph(md)
        canonical = f'{SITE}/{item["id"]}/'
        ld = {
            "@context": "https://schema.org",
            "@type": "TechArticle",
            "headline": item["title"],
            "description": desc,
            "url": canonical,
            "inLanguage": "en",
            "isPartOf": {"@type": "WebSite", "name": "Document Studio", "url": SITE + "/"},
            "author": {"@type": "Person", "name": "Tejashvi Kumawat", "url": "https://tejashvi-kumawat.github.io/"},
        }
        nav_here = sidebar.replace(f'data-id="{item["id"]}"', f'data-id="{item["id"]}" class="active"')
        page = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{esc(title)}</title>
  <meta name="description" content="{esc(desc)}" />
  <meta name="robots" content="index, follow, max-image-preview:large" />
  <link rel="canonical" href="{canonical}" />
  <meta property="og:site_name" content="Document Studio" />
  <meta property="og:type" content="article" />
  <meta property="og:title" content="{esc(title)}" />
  <meta property="og:description" content="{esc(desc)}" />
  <meta property="og:url" content="{canonical}" />
  <meta property="og:image" content="{OG_IMAGE}" />
  <meta name="twitter:card" content="summary" />
  <meta name="theme-color" content="#0f1115" />
  <link rel="icon" href="../assets/img/icon.png" type="image/png" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="{FONTS}" rel="stylesheet" />
  <link rel="stylesheet" href="../assets/css/site.css" />
  <style>.prose img{{max-width:100%;height:auto}}</style>
  <script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
</head>
<body>
  <header class="topbar">
    <a class="brand" href="../">
      <img class="brand-logo" src="../assets/img/icon.png" width="36" height="36" alt="" />
      <span class="brand-text"><strong>Document Studio</strong><em>Offline PDF</em></span>
    </a>
    <nav class="top-nav" aria-label="Primary">
      <a href="../#downloadPanel">Download</a>
      <a href="../how-to/">How to</a>
      <a href="../overview/">Docs</a>
    </nav>
    <div class="topbar-actions">
      <a class="btn solid" href="../#downloadPanel">Download</a>
      <a class="btn ghost top-github" href="{REPO}" target="_blank" rel="noopener">GitHub</a>
    </div>
  </header>
  <div class="shell">
    <aside class="sidebar" id="sidebar"><nav id="navRoot" aria-label="Documentation">{nav_here}</nav></aside>
    <main class="main" id="main">
      <article class="doc">
        <header class="doc-head">
          <p class="crumb">{esc(section)}</p>
          <h1>{esc(item["title"])}</h1>
        </header>
        <div class="doc-body prose">
{body}
        </div>
      </article>
    </main>
  </div>
  <footer class="footer">
    <div class="footer-inner">
      <div class="footer-brand"><strong>Document Studio</strong><span>Offline PDF workspace · local engines · no account</span></div>
      <nav class="footer-links" aria-label="Footer">
        <a href="../">Home</a>
        <a href="../install/">Install</a>
        <a href="../privacy/">Privacy</a>
        <a href="{REPO}/releases" target="_blank" rel="noopener">Releases</a>
      </nav>
    </div>
  </footer>
</body>
</html>
"""
        out = DOCS / item["id"]
        out.mkdir(exist_ok=True)
        (out / "index.html").write_text(page, encoding="utf-8")
        urls.append((canonical, "0.8"))

    (DOCS / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"  <url><loc>{u}</loc><lastmod>{today}</lastmod><priority>{p}</priority></url>\n" for u, p in urls)
        + "</urlset>\n",
        encoding="utf-8",
    )
    # robots.txt is honoured only at the host root (tejashvi-kumawat.github.io/robots.txt);
    # the portfolio repo's robots.txt lists this sitemap.
    print(f"built {len(items)} doc pages, sitemap.xml")


if __name__ == "__main__":
    main()
