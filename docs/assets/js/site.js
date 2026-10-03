(() => {
  const base = (() => {
    const { pathname } = window.location;
    if (pathname.endsWith("/")) return pathname;
    if (pathname.endsWith(".html")) return pathname.replace(/[^/]+$/, "");
    return pathname.replace(/\/?$/, "/");
  })();

  const el = {
    navRoot: document.getElementById("navRoot"),
    homeView: document.getElementById("homeView"),
    docView: document.getElementById("docView"),
    searchView: document.getElementById("searchView"),
    docBody: document.getElementById("docBody"),
    docTitle: document.getElementById("docTitle"),
    docCrumb: document.getElementById("docCrumb"),
    heroCards: document.getElementById("heroCards"),
    searchInput: document.getElementById("searchInput"),
    searchList: document.getElementById("searchList"),
    searchMeta: document.getElementById("searchMeta"),
    navToggle: document.getElementById("navToggle"),
    repoLink: document.getElementById("repoLink"),
    releaseLink: document.getElementById("releaseLink"),
  };

  /** @type {any} */
  let nav = null;
  /** @type {Map<string, {section:string,title:string,file:string,id:string}>} */
  const byId = new Map();
  /** @type {Map<string, string>} */
  const cache = new Map();
  /** @type {Array<{id:string,title:string,section:string,text:string}>} */
  let searchIndex = [];

  function asset(path) {
    return `${base}${path.replace(/^\//, "")}`;
  }

  async function loadNav() {
    const res = await fetch(asset("nav.json"));
    if (!res.ok) throw new Error("Failed to load nav.json");
    nav = await res.json();
    el.repoLink.href = nav.site.repo;
    el.releaseLink.href = nav.site.releases;
    renderNav();
    renderHeroCards();
  }

  function renderNav() {
    el.navRoot.innerHTML = "";
    for (const section of nav.sections) {
      const wrap = document.createElement("div");
      wrap.className = "nav-section";
      const h = document.createElement("h2");
      h.textContent = section.title;
      wrap.appendChild(h);
      for (const item of section.items) {
        byId.set(item.id, { ...item, section: section.title });
        const a = document.createElement("a");
        a.href = `#/${item.id}`;
        a.textContent = item.title;
        a.dataset.id = item.id;
        wrap.appendChild(a);
      }
      el.navRoot.appendChild(wrap);
    }
  }

  function renderHeroCards() {
    const picks = [
      ["install", "Install on every OS", "Windows Setup, macOS DMG, Linux deb, Homebrew & winget."],
      ["privacy", "Privacy by design", "Documents stay on device. No accounts. No cloud OCR."],
      ["features", "Features", "Merge, compress, protect, OCR, Office convert — offline."],
      ["engines", "Local engines", "qpdf, Tesseract, LibreOffice, and friends — bundled."],
      ["architecture", "Architecture", "Flutter UI → jobs → domain → engine ports → local files."],
      ["faq", "FAQ", "App search, updates, Gatekeeper, and more."],
    ];
    el.heroCards.innerHTML = picks
      .map(
        ([id, title, blurb]) => `
      <a class="hero-card" href="#/${id}">
        <strong>${title}</strong>
        <span>${blurb}</span>
      </a>`
      )
      .join("");
  }

  function setActive(id) {
    el.navRoot.querySelectorAll("a").forEach((a) => {
      a.classList.toggle("active", a.dataset.id === id);
    });
  }

  function show(view) {
    el.homeView.hidden = view !== "home";
    el.docView.hidden = view !== "doc";
    el.searchView.hidden = view !== "search";
  }

  async function fetchMarkdown(file) {
    if (cache.has(file)) return cache.get(file);
    const res = await fetch(asset(`pages/${file}`));
    if (!res.ok) throw new Error(`Missing ${file}`);
    const text = await res.text();
    cache.set(file, text);
    return text;
  }

  function rewriteDocLinks(html) {
    const tmp = document.createElement("div");
    tmp.innerHTML = html;
    tmp.querySelectorAll("a[href]").forEach((a) => {
      const href = a.getAttribute("href") || "";
      if (href.startsWith("http") || href.startsWith("#/") || href.startsWith("mailto:")) return;
      if (href.startsWith("../")) {
        a.setAttribute("href", nav.site.repo);
        return;
      }
      const clean = href.split("#")[0].replace(/^\.\//, "");
      const hit = [...byId.values()].find((x) => x.file === clean || x.file.endsWith("/" + clean));
      if (hit) a.setAttribute("href", `#/${hit.id}`);
    });
    return tmp.innerHTML;
  }

  async function renderDoc(id) {
    const item = byId.get(id);
    if (!item) {
      location.hash = "#/";
      return;
    }
    document.title = `${item.title} · Document Studio Docs`;
    setActive(id);
    show("doc");
    el.docCrumb.textContent = item.section;
    el.docTitle.textContent = item.title;
    el.docBody.innerHTML = "<p>Loading…</p>";
    try {
      const md = await fetchMarkdown(item.file);
      const html = marked.parse(md, { mangle: false, headerIds: true });
      el.docBody.innerHTML = rewriteDocLinks(html);
      window.scrollTo({ top: 0, behavior: "instant" in window ? "instant" : "auto" });
    } catch (err) {
      el.docBody.innerHTML = `<p>Could not load <code>${item.file}</code>.</p>`;
      console.error(err);
    }
  }

  async function ensureSearchIndex() {
    if (searchIndex.length) return;
    const jobs = [...byId.values()].map(async (item) => {
      try {
        const text = await fetchMarkdown(item.file);
        searchIndex.push({
          id: item.id,
          title: item.title,
          section: item.section,
          text: text.toLowerCase(),
        });
      } catch {
        /* skip */
      }
    });
    await Promise.all(jobs);
  }

  async function runSearch(q) {
    const query = q.trim().toLowerCase();
    if (!query) {
      location.hash = "#/";
      return;
    }
    show("search");
    setActive("");
    document.title = `Search · Document Studio Docs`;
    el.searchMeta.textContent = "Searching…";
    el.searchList.innerHTML = "";
    await ensureSearchIndex();
    const hits = searchIndex
      .map((item) => {
        const inTitle = item.title.toLowerCase().includes(query) ? 5 : 0;
        const count = item.text.split(query).length - 1;
        return { item, score: inTitle + Math.min(count, 10) };
      })
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 40);

    el.searchMeta.textContent = hits.length
      ? `${hits.length} result${hits.length === 1 ? "" : "s"} for “${q.trim()}”`
      : `No results for “${q.trim()}”`;
    el.searchList.innerHTML = hits
      .map(
        ({ item }) => `
      <li>
        <a href="#/${item.id}">
          <strong>${item.title}</strong>
          <span>${item.section}</span>
        </a>
      </li>`
      )
      .join("");
  }

  function route() {
    document.body.classList.remove("nav-open");
    const raw = (location.hash || "#/").replace(/^#\/?/, "");
    if (!raw) {
      document.title = "Document Studio Docs";
      setActive("");
      show("home");
      return;
    }
    if (raw.startsWith("search?q=")) {
      const q = decodeURIComponent(raw.slice("search?q=".length));
      el.searchInput.value = q;
      runSearch(q);
      return;
    }
    renderDoc(raw);
  }

  el.navToggle.addEventListener("click", () => {
    document.body.classList.toggle("nav-open");
  });

  let searchTimer = null;
  el.searchInput.addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      const q = el.searchInput.value.trim();
      if (!q) {
        location.hash = "#/";
        return;
      }
      location.hash = `#/search?q=${encodeURIComponent(q)}`;
    }, 180);
  });

  window.addEventListener("hashchange", route);

  loadNav()
    .then(route)
    .catch((err) => {
      document.getElementById("homeView").innerHTML =
        `<p class="lede">Docs failed to load. Open this site via GitHub Pages or a local static server.</p><pre>${String(err)}</pre>`;
      console.error(err);
    });
})();
