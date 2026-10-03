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
    pinRail: document.getElementById("pinRail"),
    pinProgressBar: document.getElementById("pinProgressBar"),
    pinImgA: document.getElementById("pinImgA"),
    pinImgB: document.getElementById("pinImgB"),
  };

  /** @type {any} */
  let nav = null;
  /** @type {Map<string, {section:string,title:string,file:string,id:string}>} */
  const byId = new Map();
  /** @type {Map<string, string>} */
  const mdCache = new Map();
  /** @type {Map<string, Promise<string>>} */
  const imageCache = new Map();
  /** @type {Array<{id:string,title:string,section:string,text:string}>} */
  let searchIndex = [];

  let pinIndex = 0;
  let pinUsingA = true;
  let pinIo = null;
  let pinBound = false;

  function asset(path) {
    return `${base}${path.replace(/^\//, "")}`;
  }

  function preloadImage(src) {
    const url = asset(src);
    if (imageCache.has(url)) return imageCache.get(url);
    const p = new Promise((resolve, reject) => {
      const img = new Image();
      img.decoding = "async";
      img.onload = () => resolve(url);
      img.onerror = reject;
      img.src = url;
    }).catch(() => url);
    imageCache.set(url, p);
    return p;
  }

  async function loadNav() {
    const res = await fetch(asset("nav.json"));
    if (!res.ok) throw new Error("Failed to load nav.json");
    nav = await res.json();
    if (el.repoLink) el.repoLink.href = nav.site.repo;
    if (el.releaseLink) el.releaseLink.href = nav.site.releases;
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
    if (!el.heroCards) return;
    const picks = [
      ["install", "Download & install", "Setup.exe, macOS DMG, Linux deb — step by step."],
      ["how-to", "How to use every tool", "Merge, compress, encrypt, OCR, sign, Office convert."],
      ["features", "Full feature list", "Everything available offline, by category."],
      ["privacy", "Privacy", "No uploads. No account. Documents stay on your device."],
      ["updates", "Stay updated", "CLI --update, Homebrew, or a newer installer."],
      ["about", "About", "Product story, author, and project links."],
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

  const COPY_ICON =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M16 1H4c-1.1 0-2 .9-2 2v12h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>';
  const CHECK_ICON =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>';

  function setActive(id) {
    el.navRoot.querySelectorAll("a").forEach((a) => {
      a.classList.toggle("active", a.dataset.id === id);
    });
    document.querySelectorAll(".top-nav a").forEach((a) => {
      const href = a.getAttribute("href") || "";
      a.classList.toggle("is-active", id && href === `#/${id}`);
    });
  }

  function show(view) {
    el.homeView.hidden = view !== "home";
    el.docView.hidden = view !== "doc";
    el.searchView.hidden = view !== "search";
    document.body.classList.toggle("view-home", view === "home");
    document.body.classList.toggle("view-docs", view !== "home");
    const topDl = document.getElementById("topDownload");
    if (topDl) topDl.href = view === "home" ? "#downloadPanel" : "#/install";
    if (view === "home") {
      initPinShowcase();
      initCarousel();
      initFadeUps();
      initCopyBlocks(document);
    }
  }

  function paintCopyBtn(btn, copied) {
    btn.innerHTML = copied ? CHECK_ICON : COPY_ICON;
    btn.classList.toggle("is-copied", !!copied);
    btn.setAttribute("aria-label", copied ? "Copied" : "Copy");
  }

  function initCopyBlocks(root) {
    (root || document).querySelectorAll("[data-copy]").forEach((block) => {
      const btn = block.querySelector(".copy-btn");
      const code = block.querySelector("code, pre");
      if (!btn || !code) return;
      if (!btn.dataset.iconReady) {
        paintCopyBtn(btn, false);
        btn.dataset.iconReady = "1";
      }
      if (btn.dataset.bound) return;
      btn.dataset.bound = "1";
      btn.addEventListener("click", async () => {
        const text = code.textContent || "";
        try {
          await navigator.clipboard.writeText(text);
          paintCopyBtn(btn, true);
          setTimeout(() => paintCopyBtn(btn, false), 1400);
        } catch {
          paintCopyBtn(btn, false);
        }
      });
    });
  }

  function wrapProseCodeBlocks(container) {
    container.querySelectorAll("pre > code").forEach((code) => {
      const pre = code.parentElement;
      if (!pre || pre.closest("[data-copy]")) return;
      const wrap = document.createElement("div");
      wrap.className = "code-block";
      wrap.setAttribute("data-copy", "");
      const bar = document.createElement("div");
      bar.className = "code-block-bar";
      bar.innerHTML = `<span>CLI</span><button type="button" class="copy-btn" aria-label="Copy"></button>`;
      pre.replaceWith(wrap);
      wrap.appendChild(bar);
      wrap.appendChild(pre);
    });
    initCopyBlocks(container);
  }

  function initFadeUps() {
    const nodes = document.querySelectorAll(".fade-up:not(.is-in)");
    if (!nodes.length) return;
    if (!("IntersectionObserver" in window)) {
      nodes.forEach((n) => n.classList.add("is-in"));
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        });
      },
      { threshold: 0.14, rootMargin: "0px 0px -8% 0px" }
    );
    nodes.forEach((n) => io.observe(n));
  }

  let carouselBound = false;
  let carouselTimer = null;
  let carouselIndex = 0;

  function initCarousel() {
    const track = document.getElementById("carouselTrack");
    const dots = document.getElementById("carouselDots");
    const prev = document.getElementById("carouselPrev");
    const next = document.getElementById("carouselNext");
    if (!track || !dots) return;
    const slides = [...track.querySelectorAll(".carousel-slide")];
    if (!slides.length) return;

    const rel = (src) => {
      if (!src) return "";
      if (src.startsWith(base)) return src.slice(base.length);
      return src.replace(/^\.?\/?/, "");
    };

    const go = async (i) => {
      const nextIndex = (i + slides.length) % slides.length;
      const img = slides[nextIndex].querySelector("img");
      if (img) {
        await preloadImage(rel(img.getAttribute("src")));
        try {
          if (typeof img.decode === "function") await img.decode();
        } catch {
          /* ignore */
        }
      }
      carouselIndex = nextIndex;
      slides.forEach((s, idx) => s.classList.toggle("is-active", idx === carouselIndex));
      dots.querySelectorAll("button").forEach((b, idx) => b.classList.toggle("is-active", idx === carouselIndex));
      const neighbor = slides[(carouselIndex + 1) % slides.length]?.querySelector("img");
      if (neighbor) preloadImage(rel(neighbor.getAttribute("src")));
    };

    const restart = () => {
      clearInterval(carouselTimer);
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      carouselTimer = setInterval(() => go(carouselIndex + 1), 5200);
    };

    if (!carouselBound) {
      carouselBound = true;
      dots.innerHTML = slides
        .map((_, i) => `<button type="button" aria-label="Go to slide ${i + 1}"></button>`)
        .join("");
      dots.querySelectorAll("button").forEach((b, i) => b.addEventListener("click", () => { go(i); restart(); }));
      prev?.addEventListener("click", () => { go(carouselIndex - 1); restart(); });
      next?.addEventListener("click", () => { go(carouselIndex + 1); restart(); });
      track.addEventListener("mouseenter", () => clearInterval(carouselTimer));
      track.addEventListener("mouseleave", restart);
      let touchX = null;
      track.addEventListener("touchstart", (e) => { touchX = e.changedTouches[0].clientX; }, { passive: true });
      track.addEventListener("touchend", (e) => {
        if (touchX == null) return;
        const dx = e.changedTouches[0].clientX - touchX;
        if (Math.abs(dx) > 40) go(carouselIndex + (dx < 0 ? 1 : -1));
        touchX = null;
        restart();
      }, { passive: true });
    }

    go(carouselIndex);
    restart();
  }

  function steps() {
    return el.pinRail ? [...el.pinRail.querySelectorAll(".pin-step")] : [];
  }

  function injectMobileShots() {
    steps().forEach((step) => {
      if (step.querySelector(".pin-step-mobile-shot")) return;
      const src = step.dataset.shot;
      if (!src) return;
      const wrap = document.createElement("figure");
      wrap.className = "pin-step-mobile-shot";
      const img = document.createElement("img");
      img.src = asset(src);
      img.alt = step.dataset.label || "";
      img.loading = "lazy";
      img.decoding = "async";
      wrap.appendChild(img);
      step.appendChild(wrap);
    });
  }

  async function setPinImage(src, label) {
    const url = await preloadImage(src);
    const current = pinUsingA ? el.pinImgA : el.pinImgB;

    if (current && current.classList.contains("is-active") && current.getAttribute("src") === url) {
      const list = steps();
      const i = pinIndex;
      [list[i + 1], list[i + 2], list[i - 1]]
        .filter(Boolean)
        .forEach((s) => s.dataset.shot && preloadImage(s.dataset.shot));
      return;
    }

    const next = pinUsingA ? el.pinImgB : el.pinImgA;
    const prev = pinUsingA ? el.pinImgA : el.pinImgB;
    if (!next || !prev) return;

    // Wait for decode before crossfading to avoid blink
    next.hidden = false;
    next.removeAttribute("hidden");
    next.src = url;
    next.alt = label || "";
    try {
      if (typeof next.decode === "function") await next.decode();
    } catch {
      /* ignore decode errors */
    }
    next.classList.add("is-active");
    prev.classList.remove("is-active");
    pinUsingA = !pinUsingA;

    const list = steps();
    const i = pinIndex;
    [list[i + 1], list[i + 2], list[i - 1]]
      .filter(Boolean)
      .forEach((s) => s.dataset.shot && preloadImage(s.dataset.shot));
  }

  function activateStep(index) {
    const list = steps();
    if (!list.length) return;
    const next = Math.max(0, Math.min(list.length - 1, index));
    if (next === pinIndex && list[next].classList.contains("is-active")) {
      // still update progress
    } else {
      pinIndex = next;
      list.forEach((step, i) => {
        step.classList.toggle("is-active", i === pinIndex);
        step.classList.toggle("is-passed", i < pinIndex);
      });
      const active = list[pinIndex];
      const title = active.querySelector("h3")?.textContent?.trim() || "";
      setPinImage(active.dataset.shot, active.dataset.label || title);
    }
    if (el.pinProgressBar) {
      const pct = list.length <= 1 ? 100 : (pinIndex / (list.length - 1)) * 100;
      el.pinProgressBar.style.width = `${pct}%`;
    }
  }

  function pickActiveFromScroll() {
    const list = steps();
    if (!list.length) return;
    const focusY = window.innerHeight * 0.38;
    let best = 0;
    let bestDist = Infinity;
    list.forEach((step, i) => {
      const rect = step.getBoundingClientRect();
      const mid = rect.top + rect.height * 0.35;
      const dist = Math.abs(mid - focusY);
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    });
    activateStep(best);
  }

  function initPinShowcase() {
    if (!el.pinRail) return;
    injectMobileShots();

    const list = steps();
    if (list[0]?.dataset.shot) preloadImage(list[0].dataset.shot);
    if (list[1]?.dataset.shot) preloadImage(list[1].dataset.shot);

    if (!pinBound) {
      pinBound = true;
      let ticking = false;
      const onScroll = () => {
        if (el.homeView.hidden) return;
        if (window.matchMedia("(max-width: 980px)").matches) return;
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => {
          pickActiveFromScroll();
          ticking = false;
        });
      };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll, { passive: true });

      list.forEach((step, i) => {
        step.addEventListener("click", () => {
          step.scrollIntoView({ behavior: "smooth", block: "center" });
          activateStep(i);
        });
      });
    }

    // IntersectionObserver as secondary trigger for smoother enter/leave
    if (pinIo) pinIo.disconnect();
    if ("IntersectionObserver" in window && !window.matchMedia("(max-width: 980px)").matches) {
      pinIo = new IntersectionObserver(
        () => pickActiveFromScroll(),
        { root: null, threshold: [0.2, 0.45, 0.7], rootMargin: "-20% 0px -35% 0px" }
      );
      list.forEach((step) => pinIo.observe(step));
    }

    activateStep(0);
    pickActiveFromScroll();
  }

  async function fetchMarkdown(file) {
    if (mdCache.has(file)) return mdCache.get(file);
    const res = await fetch(asset(`pages/${file}`));
    if (!res.ok) throw new Error(`Missing ${file}`);
    const text = await res.text();
    mdCache.set(file, text);
    return text;
  }

  function rewriteDocLinks(html) {
    const tmp = document.createElement("div");
    tmp.innerHTML = html;
    tmp.querySelectorAll("a[href]").forEach((a) => {
      const href = a.getAttribute("href") || "";
      if (href.startsWith("http") || href.startsWith("#/") || href.startsWith("mailto:")) return;
      if (href.startsWith("../") && !href.includes("images/")) {
        a.setAttribute("href", nav.site.repo);
        return;
      }
      const clean = href.split("#")[0].replace(/^\.\//, "");
      const hit = [...byId.values()].find((x) => x.file === clean || x.file.endsWith("/" + clean));
      if (hit) a.setAttribute("href", `#/${hit.id}`);
    });
    tmp.querySelectorAll("img[src]").forEach((img) => {
      const src = img.getAttribute("src") || "";
      if (src.startsWith("http") || src.startsWith("data:")) return;
      const cleaned = src.replace(/^\.\.\//, "").replace(/^\.\//, "");
      const url = asset(cleaned);
      img.setAttribute("src", url);
      img.setAttribute("loading", "lazy");
      img.setAttribute("decoding", "async");
      preloadImage(cleaned);
      if (!img.closest("figure")) {
        const fig = document.createElement("figure");
        fig.className = "doc-shot";
        img.replaceWith(fig);
        fig.appendChild(img);
        if (img.alt) {
          const cap = document.createElement("figcaption");
          cap.textContent = img.alt;
          fig.appendChild(cap);
        }
      }
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
      wrapProseCodeBlocks(el.docBody);
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
      document.title = "Document Studio — Download, Features & Docs";
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
