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
    mobileNav: document.getElementById("mobileNav"),
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

  let carouselBound = false;
  let carouselTimer = null;
  let carouselIndex = 0;
  let filmBound = false;
  let filmIndex = -1;

  const reduceMotion = () =>
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const isDesktopFilm = () => window.matchMedia("(min-width: 900px)").matches;

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
    '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="#0b1220" d="M16 1H4c-1.1 0-2 .9-2 2v12h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>';
  const CHECK_ICON =
    '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="#059669" d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17z"/></svg>';

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
      initFilmstrip();
      initReveals();
      initScrollMotion();
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
      bar.innerHTML = `<span>CLI</span><button type="button" class="copy-btn" aria-label="Copy">${COPY_ICON}</button>`;
      pre.replaceWith(wrap);
      wrap.appendChild(bar);
      wrap.appendChild(pre);
    });
    initCopyBlocks(container);
  }

  function initReveals() {
    const nodes = [...document.querySelectorAll(".fade-up:not(.is-in), .reveal:not(.is-in)")];
    if (!nodes.length) return;

    const groups = new Map();
    nodes.forEach((n) => {
      const parent = n.parentElement;
      if (!parent) return;
      if (!groups.has(parent)) groups.set(parent, []);
      groups.get(parent).push(n);
    });
    groups.forEach((list) => {
      list.forEach((n, i) => {
        if (!n.style.getPropertyValue("--fade-delay")) {
          n.style.setProperty("--fade-delay", `${Math.min(i, 6) * 90}ms`);
        }
      });
    });

    if (reduceMotion() || !("IntersectionObserver" in window)) {
      nodes.forEach((n) => n.classList.add("is-in"));
      return;
    }

    // Kick anything already near the top immediately (mobile first paint)
    const vh = window.innerHeight || 800;
    nodes.forEach((n) => {
      const r = n.getBoundingClientRect();
      if (r.top < vh * 0.92 && r.bottom > 40) n.classList.add("is-in");
    });

    const pending = new Set(nodes.filter((n) => !n.classList.contains("is-in")));
    if (!pending.size) return;

    let io;
    const mark = (n) => {
      n.classList.add("is-in");
      pending.delete(n);
      if (io) io.unobserve(n);
    };

    io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          mark(entry.target);
        });
      },
      { threshold: [0, 0.08, 0.16], rootMargin: "40px 0px -6% 0px" }
    );
    pending.forEach((n) => io.observe(n));

    // Fallback for mobile browsers that miss first IO pass
    const scan = () => {
      const h = window.innerHeight || 800;
      [...pending].forEach((n) => {
        const r = n.getBoundingClientRect();
        if (r.top < h * 0.94 && r.bottom > 24) mark(n);
      });
      if (!pending.size) {
        window.removeEventListener("scroll", onScroll);
        window.removeEventListener("resize", onScroll);
      }
    };
    let raf = 0;
    const onScroll = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(scan);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    requestAnimationFrame(scan);
  }

  let scrollMotionBound = false;

  function clamp(n, a, b) {
    return Math.min(b, Math.max(a, n));
  }

  function sceneProgress(el) {
    if (!el) return 0;
    const r = el.getBoundingClientRect();
    const vh = window.innerHeight || 800;
    // 0 before enter, 1 when section mid is near viewport mid
    const start = vh * 0.92;
    const end = vh * 0.28;
    return clamp((start - r.top) / (start - end), 0, 1);
  }

  function initScrollMotion() {
    const heroInner = document.querySelector("[data-hero-motion]");
    const scenes = [...document.querySelectorAll("[data-scroll-scene]")];
    if (!heroInner && !scenes.length) return;

    const tick = () => {
      if (el.homeView?.hidden) return;

      if (heroInner && !reduceMotion()) {
        const hero = heroInner.closest(".hero") || heroInner;
        const r = hero.getBoundingClientRect();
        // Gentle exit parallax — keep text fully readable
        const exit = clamp((-r.top) / Math.max(r.height * 1.1, 1), 0, 1) * 0.55;
        heroInner.style.setProperty("--hero-exit", exit.toFixed(4));
        const mesh = hero.querySelector(".hero-mesh");
        if (mesh) mesh.style.transform = `translate3d(0, ${exit * 28}px, 0)`;
      } else if (heroInner) {
        heroInner.style.setProperty("--hero-exit", "0");
      }

      scenes.forEach((scene) => {
        if (reduceMotion()) {
          scene.style.setProperty("--scene-p", "1");
          scene.style.setProperty("--scene-lift", "0");
          return;
        }
        const p = sceneProgress(scene);
        scene.style.setProperty("--scene-p", p.toFixed(4));
        scene.style.setProperty("--scene-lift", ((1 - p) * 14).toFixed(2));
        // Soft parallax on cards still in view
        scene.querySelectorAll(".reveal-card.is-in").forEach((card, i) => {
          const lift = (1 - p) * (8 + i * 2);
          card.style.setProperty("--scene-lift", lift.toFixed(2));
        });
      });
    };

    if (!scrollMotionBound) {
      scrollMotionBound = true;
      let raf = 0;
      const onScroll = () => {
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(tick);
      };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
    }
    tick();
  }

  /* ——— Feature filmstrip: vertical scroll → horizontal scrub ——— */
  function decodeBody(html) {
    const t = document.createElement("textarea");
    t.innerHTML = html || "";
    return t.value;
  }

  function setFilmCopy(card, index, total) {
    const title = document.getElementById("filmTitle");
    const summary = document.getElementById("filmSummary");
    const body = document.getElementById("filmBody");
    const idx = document.getElementById("filmIndex");
    if (!card || !title || !body) return;
    title.textContent = card.dataset.title || "";
    if (summary) summary.textContent = card.dataset.summary || "";
    body.innerHTML = decodeBody(card.dataset.body || "");
    if (idx) {
      idx.textContent = `${String(index + 1).padStart(2, "0")} / ${String(total).padStart(2, "0")}`;
    }
  }

  let mobileFilmBound = false;
  let mobileFilmIndex = -1;

  function buildFilmMobile(cards) {
    const mount = document.getElementById("filmMobile");
    if (!mount || mount.dataset.built === "1") return;
    mount.dataset.built = "1";
    const first = cards[0];
    mount.innerHTML = `
      <div class="film-mobile-runway" id="filmMobileRunway">
        <div class="film-mobile-sticky">
          <div class="film-mobile-top">
            <p class="section-label">Selected tools</p>
            <p class="film-index" id="filmMobileIndex">01 / ${String(cards.length).padStart(2, "0")}</p>
          </div>
          <div class="film-mobile-stage">
            <div class="film-mobile-rail" id="filmMobileRail">
              ${cards
                .map((card, i) => {
                  const img = card.querySelector("img");
                  const src = img?.getAttribute("src") || "";
                  const alt = img?.getAttribute("alt") || "";
                  const label = (card.dataset.title || "").split(" ")[0] || "Tool";
                  return `
                <article class="film-m-card" data-idx="${i}">
                  <div class="shot-frame">
                    <img src="${src}" alt="${alt}" width="1400" height="900" loading="${i < 2 ? "eager" : "lazy"}" decoding="async" />
                  </div>
                  <p class="film-card-cap">${String(i + 1).padStart(2, "0")} · ${label}</p>
                </article>`;
                })
                .join("")}
            </div>
          </div>
          <div class="film-mobile-progress" aria-hidden="true"><span id="filmMobileProgress"></span></div>
          <div class="film-mobile-copy" aria-live="polite">
            <h2 id="filmMobileTitle"></h2>
            <p class="film-summary" id="filmMobileSummary"></p>
            <div class="film-body" id="filmMobileBody"></div>
          </div>
        </div>
      </div>`;

    const railCards = [...mount.querySelectorAll(".film-m-card")];
    railCards.forEach((el, i) => {
      const src = cards[i];
      if (!src) return;
      el.dataset.title = src.dataset.title || "";
      el.dataset.summary = src.dataset.summary || "";
      el.dataset.body = src.dataset.body || "";
    });

    const title = document.getElementById("filmMobileTitle");
    const summary = document.getElementById("filmMobileSummary");
    const body = document.getElementById("filmMobileBody");
    if (title) title.textContent = first?.dataset.title || "";
    if (summary) summary.textContent = first?.dataset.summary || "";
    if (body) body.innerHTML = decodeBody(first?.dataset.body || "");

    initMobileFilmScrub(cards.length);
  }

  function initMobileFilmScrub(total) {
    const runway = document.getElementById("filmMobileRunway");
    const sticky = runway?.querySelector(".film-mobile-sticky");
    const track = document.getElementById("filmMobileRail");
    const title = document.getElementById("filmMobileTitle");
    const summary = document.getElementById("filmMobileSummary");
    const body = document.getElementById("filmMobileBody");
    const idxEl = document.getElementById("filmMobileIndex");
    const progress = document.getElementById("filmMobileProgress");
    if (!runway || !sticky || !track) return;

    const cards = [...track.querySelectorAll(".film-m-card")];
    if (!cards.length) return;

    const applyCopy = (i, animate = true) => {
      const card = cards[i];
      if (!card) return;
      if (idxEl) {
        idxEl.textContent = `${String(i + 1).padStart(2, "0")} / ${String(total).padStart(2, "0")}`;
      }
      const setCopy = () => {
        if (title) title.textContent = card.dataset.title || "";
        if (summary) summary.textContent = card.dataset.summary || "";
        if (body) body.innerHTML = decodeBody(card.dataset.body || "");
      };
      if (title && animate && !reduceMotion() && i !== mobileFilmIndex) {
        title.classList.add("is-swap");
        window.setTimeout(() => {
          setCopy();
          title.classList.remove("is-swap");
        }, 140);
      } else {
        setCopy();
      }
      cards.forEach((c, n) => c.classList.toggle("is-active", n === i));
      mobileFilmIndex = i;
      const img = card.querySelector("img");
      if (img) preloadImage(img.getAttribute("src") || "");
      const next = cards[i + 1]?.querySelector("img");
      if (next) preloadImage(next.getAttribute("src") || "");
    };

    const measure = () => {
      if (isDesktopFilm()) {
        runway.style.height = "";
        track.style.transform = "translate3d(0,0,0)";
        return { travel: 0, stickStart: 0 };
      }
      const stickyH = sticky.clientHeight || window.innerHeight;
      const stickyTop = parseFloat(getComputedStyle(sticky).top) || 0;
      const cardW = cards[0].offsetWidth || cards[0].getBoundingClientRect().width;
      const gap = 14;
      // Peek next card ~40% from the right
      const step = cardW * 0.6 + gap * 0.6;
      const travel = Math.max(0, (cards.length - 1) * step);
      const nextH = stickyH + travel + window.innerHeight * 0.08;
      if (runway.style.height !== `${nextH}px`) {
        runway.style.height = `${nextH}px`;
      }
      const runwayAbs = runway.getBoundingClientRect().top + window.scrollY;
      const stickStart = runwayAbs - stickyTop;
      return { travel, stickStart, step, cardW };
    };

    const sync = () => {
      if (isDesktopFilm() || el.homeView?.hidden) return;
      const { travel, stickStart } = measure();
      if (travel <= 0) return;

      if (reduceMotion()) {
        track.style.transform = "translate3d(0,0,0)";
        if (progress) progress.style.width = "0%";
        return;
      }

      const into = Math.min(travel, Math.max(0, window.scrollY - stickStart));
      const p = into / travel;
      track.style.transform = `translate3d(${-into}px, 0, 0)`;
      if (progress) progress.style.width = `${(p * 100).toFixed(2)}%`;

      const nextIdx = Math.min(cards.length - 1, Math.round(p * (cards.length - 1)));
      if (nextIdx !== mobileFilmIndex) applyCopy(nextIdx, true);
    };

    if (!mobileFilmBound) {
      mobileFilmBound = true;
      let raf = 0;
      const onScroll = () => {
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(sync);
      };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
      if ("ResizeObserver" in window) {
        const ro = new ResizeObserver(onScroll);
        ro.observe(track);
        ro.observe(runway);
      }
    }

    if (mobileFilmIndex < 0) applyCopy(0, false);
    sync();
  }

  function initFilmstrip() {
    const runway = document.getElementById("filmRunway");
    const track = document.getElementById("filmTrack");
    const progress = document.getElementById("filmProgressBar");
    if (!runway || !track) return;

    const cards = [...track.querySelectorAll(".film-card")];
    if (!cards.length) return;

    buildFilmMobile(cards);
    if (filmIndex < 0) {
      setFilmCopy(cards[0], 0, cards.length);
      filmIndex = 0;
    }

    const measure = () => {
      if (!isDesktopFilm()) {
        runway.style.height = "";
        track.style.transform = "translate3d(0,0,0)";
        return { travel: 0, stickyH: 0, stickStart: 0 };
      }
      const sticky = runway.querySelector(".film-sticky");
      const stickyH = sticky ? sticky.clientHeight : window.innerHeight;
      const stickyTop = sticky
        ? parseFloat(getComputedStyle(sticky).top) || 0
        : 0;
      const stage = runway.querySelector(".film-stage");
      const stageW = stage ? stage.clientWidth : window.innerWidth * 0.55;
      // Peek next card ~45%: each step moves by ~55% of a card width
      const cardW = cards[0].offsetWidth || cards[0].getBoundingClientRect().width;
      const gap = 16;
      const step = cardW * 0.55 + gap * 0.55;
      const travel = Math.max(0, (cards.length - 1) * step);
      const nextH = stickyH + travel + stageW * 0.12;
      if (runway.style.height !== `${nextH}px`) {
        runway.style.height = `${nextH}px`;
      }
      // Absolute Y where the panel sticks and scrub begins
      const runwayAbs = runway.getBoundingClientRect().top + window.scrollY;
      const stickStart = runwayAbs - stickyTop;
      return { travel, stickyH, step, cardW, stickStart };
    };

    let metrics = measure();

    const sync = () => {
      if (!isDesktopFilm()) return;
      metrics = measure();
      const { travel, stickStart } = metrics;
      if (travel <= 0) return;

      const into = Math.min(travel, Math.max(0, window.scrollY - stickStart));
      const p = into / travel;

      track.style.transform = `translate3d(${-into}px, 0, 0)`;
      if (progress) progress.style.width = `${(p * 100).toFixed(2)}%`;

      const idx = Math.min(cards.length - 1, Math.round(p * (cards.length - 1)));
      if (idx !== filmIndex) {
        filmIndex = idx;
        setFilmCopy(cards[idx], idx, cards.length);
        const img = cards[idx].querySelector("img");
        if (img) preloadImage(img.getAttribute("src") || "");
        const next = cards[idx + 1]?.querySelector("img");
        if (next) preloadImage(next.getAttribute("src") || "");
      }
    };

    if (!filmBound) {
      filmBound = true;
      let raf = 0;
      const onScroll = () => {
        if (el.homeView?.hidden) return;
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(sync);
      };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
      if ("ResizeObserver" in window) {
        const ro = new ResizeObserver(onScroll);
        ro.observe(track);
        ro.observe(runway);
      }
    }

    // Reduced motion: jump to start state, still allow scroll through height
    if (reduceMotion()) {
      metrics = measure();
      track.style.transform = "translate3d(0,0,0)";
      if (progress) progress.style.width = "0%";
      return;
    }

    sync();
  }

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
      if (reduceMotion()) return;
      carouselTimer = setInterval(() => go(carouselIndex + 1), 5200);
    };

    if (!carouselBound) {
      carouselBound = true;
      dots.innerHTML = slides
        .map((_, i) => `<button type="button" aria-label="Go to slide ${i + 1}"></button>`)
        .join("");
      dots.querySelectorAll("button").forEach((b, i) =>
        b.addEventListener("click", () => {
          go(i);
          restart();
        })
      );
      prev?.addEventListener("click", () => {
        go(carouselIndex - 1);
        restart();
      });
      next?.addEventListener("click", () => {
        go(carouselIndex + 1);
        restart();
      });
      track.addEventListener("mouseenter", () => clearInterval(carouselTimer));
      track.addEventListener("mouseleave", restart);
      let touchX = null;
      track.addEventListener(
        "touchstart",
        (e) => {
          touchX = e.changedTouches[0].clientX;
        },
        { passive: true }
      );
      track.addEventListener(
        "touchend",
        (e) => {
          if (touchX == null) return;
          const dx = e.changedTouches[0].clientX - touchX;
          if (Math.abs(dx) > 40) go(carouselIndex + (dx < 0 ? 1 : -1));
          touchX = null;
          restart();
        },
        { passive: true }
      );
    }

    go(carouselIndex);
    restart();
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
      if (img.closest("figure") || img.closest(".tool-guide-shot") || img.classList.contains("tool-thumb")) {
        return;
      }
      const fig = document.createElement("figure");
      fig.className = "doc-shot";
      img.replaceWith(fig);
      fig.appendChild(img);
      if (img.alt) {
        const cap = document.createElement("figcaption");
        cap.textContent = img.alt;
        fig.appendChild(cap);
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
    if (el.navToggle) el.navToggle.setAttribute("aria-expanded", "false");
    const raw = (location.hash || "#/").replace(/^#\/?/, "");

    if (raw && !raw.includes("/") && !raw.startsWith("search") && !byId.has(raw) && document.getElementById(raw)) {
      document.title = "Document Studio — Download, Features & Docs";
      setActive("");
      show("home");
      requestAnimationFrame(() => {
        document.getElementById(raw)?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
      return;
    }

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

  el.navToggle?.addEventListener("click", () => {
    const open = document.body.classList.toggle("nav-open");
    el.navToggle.setAttribute("aria-expanded", open ? "true" : "false");
  });

  el.mobileNav?.querySelectorAll("a").forEach((a) => {
    a.addEventListener("click", () => {
      document.body.classList.remove("nav-open");
      el.navToggle?.setAttribute("aria-expanded", "false");
    });
  });

  let searchTimer = null;
  el.searchInput?.addEventListener("input", () => {
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

  function initTopbarScroll() {
    const bar = document.querySelector(".topbar");
    if (!bar || bar.dataset.scrollBound) return;
    bar.dataset.scrollBound = "1";
    const sync = () => bar.classList.toggle("is-scrolled", window.scrollY > 8);
    sync();
    window.addEventListener("scroll", sync, { passive: true });
  }

  document.addEventListener("click", (e) => {
    const a = e.target.closest("a[href^='#']");
    if (!a) return;
    const href = a.getAttribute("href") || "";
    if (href.startsWith("#/")) return;
    const id = href.slice(1);
    if (!id) return;
    const target = document.getElementById(id);
    if (!target) return;
    e.preventDefault();
    if (el.homeView?.hidden) {
      location.hash = "#/";
      setTimeout(() => target.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
    } else {
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      history.replaceState(null, "", `#${id}`);
    }
    document.body.classList.remove("nav-open");
  });

  window.addEventListener("hashchange", route);
  initTopbarScroll();

  loadNav()
    .then(route)
    .catch((err) => {
      const home = document.getElementById("homeView");
      if (home) {
        home.innerHTML = `<p class="lede" style="padding:2rem">Docs failed to load. Open this site via GitHub Pages or a local static server.</p><pre>${String(err)}</pre>`;
      }
      console.error(err);
    });
})();
