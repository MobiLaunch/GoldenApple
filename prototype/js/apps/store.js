// Software: Discover page with an auto-advancing hero carousel, "Get" buttons
// that become a filling progress ring then "Open", categories and Updates.
import { h, sym, appIcon, genArt, genIcon, animate, bus } from "../util.js";
import { createWindow, pill, tb } from "../wm.js";
import { registerApp, launch } from "../apps.js";

const APPS = [
  ["Tern", "Fast, native terminal", "code", "#3a3a3c", "#0b0b0d", "Develop"], ["Lumen", "Beautiful image viewer", "photo", "#ff9f0a", "#ff375f", "Create"],
  ["Amber", "Plays music, and nothing else", "music", "#ffcc00", "#ff9f0a", "Play"], ["Harbor", "Chat with everyone", "bubble", "#5e5ce6", "#0a84ff", "Work"],
  ["Forge 3D", "3D creation for everyone", "layers", "#ff9f0a", "#e0620b", "Create"], ["Canvas", "Painting, reimagined", "brush", "#bf5af2", "#ff375f", "Create"],
  ["Notebook", "Your second brain", "book", "#8e2de2", "#4a00e0", "Work"], ["Nearby", "Share files with devices near you", "broadcast", "#30d158", "#0b8f3a", "Work"],
  ["Quill", "Code at the speed of thought", "code", "#0a84ff", "#0040dd", "Develop"], ["Dockyard", "Containers made simple", "briefcase", "#bf5af2", "#5e5ce6", "Develop"],
  ["Kart Rally", "Race your friends", "game", "#ff453a", "#ff9f0a", "Play"], ["Vitals", "See what your system is doing", "gauge", "#30d158", "#0a84ff", "Develop"],
  ["Courier", "Send big files securely", "paperplane", "#64d2ff", "#0a84ff", "Work"], ["Headlines", "All your feeds in one place", "doc", "#ff9f0a", "#ff453a", "Work"],
  ["Tidepool", "Relaxing puzzle game", "drop", "#64d2ff", "#30d158", "Play"],
];
const HERO = [
  ["NEW RELEASE", "CitronOS 27", "Liquid Glass comes to Linux.", "hero-a"],
  ["BEHIND THE DESIGN", "One set of springs", "How every animation shares the same physics.", "hero-b"],
  ["THE BASICS", "Make it yours", "Custom icons, accent colours and wallpapers.", "hero-c"],
];
const installed = new Set();

function getButton(name) {
  const b = h("button.get", installed.has(name) ? "Open" : "Get");
  b.addEventListener("click", async (e) => {
    e.stopPropagation();
    if (installed.has(name)) { const own = { Tern: "terminal", Lumen: "photos", Amber: "music" }[name]; own ? launch(own) : bus.emit("notify", { app: "store", title: name, body: "Opens in the Linux build." }); return; }
    if (b.classList.contains("loading")) return;
    b.classList.add("loading");
    b.replaceChildren(h("span.ring"), h("i.stop"));
    animate(b, [{ width: "68px" }, { width: "30px" }], "snappy");
    const ring = b.firstChild;
    const t0 = performance.now(), dur = 2200;
    await new Promise((res) => {
      const tick = (t) => { const p = Math.min(1, (t - t0) / dur); ring.style.setProperty("--p", (1 - (1 - p) ** 2).toFixed(3)); p < 1 ? requestAnimationFrame(tick) : res(); };
      requestAnimationFrame(tick);
    });
    installed.add(name);
    b.classList.remove("loading");
    b.replaceChildren("Open");
    animate(b, [{ width: "30px" }, { width: "68px" }], "bouncy");
  });
  return b;
}
const appRow = ([name, sub, icon, a, c]) => h("div.s-app", genIcon(icon, a, c, 58), h("div.s-meta", h("b", name), h("span", sub)), getButton(name));

function openStore() {
  let page = "discover", heroIdx = 0, heroTimer = 0;
  const sidebar = h("div");
  const body = h("div.store-body");
  const win = createWindow({ app: "store", w: 1080, h: 700, sidebar, sidebarWidth: 210, className: "store", content: body, toolbar: [h("div.grow"), pill(tb("person", { title: "Account" }))] });
  const PAGES = [["discover", "Discover", "sparkles"], ["play", "Play", "game"], ["create", "Create", "brush"], ["work", "Work", "briefcase"], ["develop", "Develop", "code"], ["categories", "Categories", "grid"], ["updates", "Updates", "download"]];

  function renderSide() {
    sidebar.replaceChildren(h("label.side-search", sym("search"), h("input", { placeholder: "Search" })),
      ...PAGES.map(([k, label, icon]) => h("div.side-row", { className: `side-row ${page === k ? "sel" : ""}`, on: { click: () => { page = k; render(); } } }, sym(icon), label,
        k === "updates" ? h("span.badge", "3") : null)),
      h("div.store-account", h("span.avatar", { style: { background: "linear-gradient(135deg,#ffb347,#ff5e7e 60%,#7b61ff)" } }, "GG"), h("div", h("b", "Golden User"), h("small", "View account"))));
  }

  function hero() {
    const slides = HERO.map(([eyebrow, title, sub, seed], i) => h("div.slide", { className: `slide ${i === heroIdx ? "on" : ""}`, style: { backgroundImage: `url("${genArt(seed, { w: 900, h: 360 })}")` } },
      h("div.shade"), h("div.copy", h("small", eyebrow), h("h2", title), h("p", sub))));
    const dots = h("div.dots", HERO.map((_, i) => h("i", { className: i === heroIdx ? "on" : "", on: { click: () => show(i) } })));
    const wrap = h("div.hero", ...slides, dots,
      h("button.arrow.l.glass-regular", { on: { click: () => show(heroIdx - 1) } }, sym("chevron-left")),
      h("button.arrow.r.glass-regular", { on: { click: () => show(heroIdx + 1) } }, sym("chevron-right")));
    function show(i) {
      const prev = slides[heroIdx];
      heroIdx = (i + HERO.length) % HERO.length;
      const next = slides[heroIdx];
      if (prev === next) return;
      prev.classList.remove("on"); next.classList.add("on");
      animate(next, [{ opacity: 0, transform: "scale(1.04)" }, { opacity: 1, transform: "none" }], "smooth");
      [...dots.children].forEach((d, j) => d.classList.toggle("on", j === heroIdx));
    }
    clearInterval(heroTimer);
    heroTimer = setInterval(() => document.body.contains(wrap) && show(heroIdx + 1), 6000);
    return wrap;
  }

  function render() {
    renderSide();
    const title = PAGES.find((p) => p[0] === page)[1];
    if (page === "discover") {
      body.replaceChildren(h("h1.large-title", "Discover"), hero(),
        h("div.s-head", h("h2", "Apps We Love"), h("button.link", "See All")), h("div.s-grid", APPS.slice(0, 9).map(appRow)),
        h("div.s-head", h("h2", "Essentials")), h("div.essentials",
          h("div.ess", { style: { background: "linear-gradient(135deg,#1e3c72,#2a5298)" } }, h("small", "GET STARTED"), h("b", "Set up your new desktop"), appIcon("settings")),
          h("div.ess", { style: { background: "linear-gradient(135deg,#ff9966,#ff5e62)" } }, h("small", "COLLECTION"), h("b", "Creative tools, open source"), appIcon("photos"))),
        h("div.s-head", h("h2", "Top Free Games")), h("div.s-grid", APPS.filter((a) => a[5] === "Play").concat(APPS.slice(9, 12)).map(appRow)));
    } else if (page === "updates") {
      body.replaceChildren(h("div.s-head.big", h("h1.large-title", "Updates"), h("button.btn.primary", { on: { click: () => body.querySelectorAll(".get").forEach((b) => b.click()) } }, "Update All")),
        h("div.updates", [APPS[0], APPS[5], APPS[8]].map((a) => h("div.update", genIcon(a[2], a[3], a[4], 58), h("div.s-meta", h("b", a[0]), h("span", "Version 2.4 · Yesterday"), h("p", "Smoother scrolling, a refreshed icon and many fixes for fractional scaling.")), getButton(a[0])))));
    } else {
      const list = page === "categories" ? APPS : APPS.filter((a) => a[5].toLowerCase() === page);
      body.replaceChildren(h("h1.large-title", title), h("div.s-grid", list.map(appRow)));
    }
    win.content.scrollTop = 0;
    animate(body, [{ opacity: 0 }, { opacity: 1 }], "smooth");
  }
  win.onClose = () => clearInterval(heroTimer);
  render();
  return win;
}

registerApp("store", openStore, { Store: [{ label: "Reload Page", kbd: "⌘R" }, "-", { label: "Updates", icon: "download" }, { label: "Account", icon: "person" }] });
