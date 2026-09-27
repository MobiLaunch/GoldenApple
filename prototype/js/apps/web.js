// Web: start page (favourites, privacy report, reading list), an address field
// with the loading progress hairline, history, and one real page: golden-gate.dev.
import { h, sym, animate, genArt, wait } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp, launch } from "../apps.js";

const FAVS = [
  ["Golden Gate", "golden-gate.dev", "#f5a524", "#e0620b"], ["Arch Wiki", "wiki.archlinux.org", "#35a7e8", "#1263b0"],
  ["Hyprland", "hyprland.org", "#58e1ff", "#2e7df6"], ["Flathub", "flathub.org", "#6aa2e8", "#3b5fb8"],
  ["Wikipedia", "wikipedia.org", "#8e8e93", "#3a3a3c"], ["GitHub", "github.com", "#48484a", "#1c1c1e"],
  ["Quickshell", "quickshell.org", "#bf5af2", "#5e5ce6"], ["Inter", "rsms.me/inter", "#30d158", "#0b8f3a"],
];
const READING = [
  ["Designing for Liquid Glass", "A field guide to translucency, rims and lensing.", "glass"],
  ["Springs, not curves", "Why response and damping beat cubic-bezier.", "springs"],
  ["The case for continuous corners", "Superellipses, and where they came from.", "corners"],
];

function openWeb() {
  const st = { url: "", back: [], fwd: [] };
  const input = h("input", { placeholder: "Search or enter website name", spellcheck: false });
  const icon = h("span.addr-icon", sym("search"));
  const bar = h("i.addr-progress");
  const addr = h("label.pill.addr", icon, input, bar);
  const backBtn = tb("chevron-left", { title: "Back", click: () => go(st.back.pop(), "back") });
  const fwdBtn = tb("chevron-right", { title: "Forward", click: () => go(st.fwd.pop(), "fwd") });
  const page = h("div.web-page");
  const win = createWindow({
    app: "browser", w: 1080, h: 690, className: "web", content: page,
    toolbar: [pill(tb("sidebar", { title: "Show Sidebar" })), pill(backBtn, div(), fwdBtn), h("div.grow"), addr, h("div.grow"),
      pill(tb("share", { title: "Share" }), tb("plus", { title: "New Window", click: () => launch("browser", "new") }), tb("mirror", { title: "Tab Overview" }))],
  });

  input.addEventListener("focus", () => { input.value = st.url; input.select(); });
  input.addEventListener("blur", () => { input.value = pretty(st.url); });
  input.addEventListener("keydown", (e) => { if (e.key === "Enter") { go(normalise(input.value), "new"); input.blur(); } if (e.key === "Escape") input.blur(); });

  const normalise = (v) => { v = v.trim(); if (!v) return ""; if (/\s/.test(v) || !/\./.test(v)) return `search:${v}`; return v.replace(/^https?:\/\//, "").replace(/\/$/, ""); };
  const pretty = (u) => (u.startsWith("search:") ? u.slice(7) : u);

  async function go(url, how) {
    if (url == null) return;
    if (how === "new") { st.back.push(st.url); st.fwd = []; }
    if (how === "back") st.fwd.push(st.url);
    if (how === "fwd") st.back.push(st.url);
    st.url = url;
    backBtn.disabled = !st.back.length; fwdBtn.disabled = !st.fwd.length;
    input.value = pretty(url);
    icon.replaceChildren(sym(url ? (url.startsWith("search:") ? "search" : "lock") : "search"));
    // Loading hairline: races to ~80%, then completes when the page is in.
    bar.getAnimations().forEach((a) => a.cancel());
    if (url) {
      bar.animate([{ width: "0%", opacity: 1 }, { width: "78%", opacity: 1 }], { duration: 420, easing: "cubic-bezier(.2,.8,.2,1)", fill: "forwards" });
      await wait(380);
    }
    render();
    if (url) { await bar.animate([{ width: "78%", opacity: 1 }, { width: "100%", opacity: 1 }, { width: "100%", opacity: 0 }], { duration: 380, fill: "forwards" }).finished; }
    win.setTitle(url ? pretty(url) : "Start Page");
  }

  function render() {
    const u = st.url;
    page.className = "web-page";
    win.content.scrollTop = 0;
    if (!u) page.replaceChildren(startPage());
    else if (u.startsWith("golden-gate.dev")) { page.classList.add("site"); page.replaceChildren(landing()); }
    else page.replaceChildren(offline(u));
    animate(page, [{ opacity: 0 }, { opacity: 1 }], "smooth");
  }

  function startPage() {
    return h("div.start",
      h("section", h("h2", "Favourites"),
        h("div.favs", FAVS.map(([name, url, a, b]) => h("button.fav", { on: { click: () => go(url, "new") } },
          h("span.tile", { style: { background: `linear-gradient(180deg, ${a}, ${b})` } }, name[0]), h("span.name", name))))),
      h("section", h("h2", "Privacy Report"),
        h("div.card.privacy", h("span.shield", sym("shield")), h("b", "42"),
          h("p", "In the last seven days, Web has prevented ", h("b", "42 trackers"), " from profiling you and hidden your IP address from known trackers."))),
      h("section", h("h2", "Reading List"),
        h("div.reading", READING.map(([t, d, seed]) => h("button.card.read", { on: { click: () => go("golden-gate.dev/journal/" + seed, "new") } },
          h("img", { src: genArt(seed, { w: 320, h: 180 }), alt: "" }), h("b", t), h("span", d))))),
    );
  }

  function landing() {
    const feature = (icon, title, body) => h("div.feature", h("span.f-icon", sym(icon)), h("b", title), h("p", body));
    return h("div.landing",
      h("header.hero",
        h("div.hero-inner",
          h("span.eyebrow", "Golden Gate 27"),
          h("h1", "Liquid Glass.", h("br"), "Now on Linux."),
          h("p", "A desktop that refracts, springs and glows, built on Arch, Hyprland and Quickshell."),
          h("div.cta", h("button.btn.primary", { on: { click: () => launch("store") } }, "Download the ISO"), h("button.link", "Learn more ›")))),
      h("section.features",
        feature("sparkles", "Liquid Glass", "Translucent materials with a specular rim and lensing, shared by the shell, the apps and the compositor."),
        feature("arrow-clockwise", "Spring motion", "Every animation is a real spring defined once and reproduced in CSS, QML and Hyprland."),
        feature("brush", "Your icons", "Drop an SVG into icons/custom and it replaces the system artwork everywhere.")),
      h("footer", "golden-gate.dev · Built in the open"));
  }

  function offline(u) {
    return h("div.offline",
      h("span.big", sym("globe")),
      h("h2", u.startsWith("search:") ? `Search for “${u.slice(7)}”` : `Open “${u}”`),
      h("p", "Pages from the internet load in the Linux build (Firefox or WebKitGTK). This reference shell renders the start page and golden-gate.dev."),
      h("button.btn.primary", { on: { click: () => go("golden-gate.dev", "new") } }, "Open golden-gate.dev"));
  }

  go("", "init");
  return win;
}

registerApp("browser", openWeb, {
  History: [{ label: "Show All History", kbd: "⌘Y" }, "-", { label: "Back", kbd: "⌘[" }, { label: "Forward", kbd: "⌘]" }, { label: "Home", kbd: "⇧⌘H" }],
  Bookmarks: [{ label: "Show Bookmarks", icon: "bookmark", kbd: "⌥⌘B" }, { label: "Add Bookmark…", kbd: "⌘D" }, "-", { label: "Reading List", icon: "book" }],
});
