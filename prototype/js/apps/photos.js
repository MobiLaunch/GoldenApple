// Photos: floating sidebar, glass toolbar with segmented control and zoom,
// procedurally generated library, and a shared-element zoom into the viewer.
import { h, sym, animate } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp } from "../apps.js";

// Deterministic PRNG so the library looks the same every launch.
function rng(seed) { return () => ((seed = (seed * 16807) % 2147483647) / 2147483647); }

const PALETTES = [
  ["#ffb35c", "#ff6f7d", "#6b3fa0", "#2a1f5c"],   // dusk
  ["#8fd3ff", "#4aa3f0", "#2f7d4f", "#1d4d33"],   // lake
  ["#ffe0a3", "#f7a35c", "#c0663a", "#7a3b24"],   // desert
  ["#a8e6ff", "#5ab0e8", "#1f6fb2", "#0d3b6e"],   // coast
  ["#1a1f4a", "#3b2f7a", "#ff9f5a", "#141629"],   // city night
  ["#d7f0c2", "#89c97a", "#3f8f4a", "#1f5a2c"],   // hills
];
function photo(seed) {
  const r = rng(seed * 9973 + 7), [a, b, c, d] = PALETTES[Math.floor(r() * PALETTES.length)];
  const hills = (y, amp, col, op = 1) => {
    let p = `M0 ${y}`;
    for (let x = 0; x <= 400; x += 50) p += ` Q${x + 25} ${y - amp * (r() - 0.3)} ${x + 50} ${y - amp * 0.4 * (r() - 0.5)}`;
    return `<path d="${p} V300 H0Z" fill="${col}" opacity="${op}"/>`;
  };
  const city = a === "#1a1f4a" ? Array.from({ length: 14 }, (_, i) => {
    const w = 18 + r() * 20, ht = 60 + r() * 120, x = i * 30;
    const lights = Array.from({ length: 8 }, () => `<rect x="${x + 3 + r() * (w - 6)}" y="${300 - ht + 6 + r() * (ht - 12)}" width="2.5" height="3" fill="#ffd27a" opacity="${0.4 + r() * 0.6}"/>`).join("");
    return `<rect x="${x}" y="${300 - ht}" width="${w}" height="${ht}" fill="#0c0f24"/>${lights}`;
  }).join("") : "";
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" preserveAspectRatio="xMidYMid slice">
    <defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${b}"/><stop offset="1" stop-color="${a}"/></linearGradient></defs>
    <rect width="400" height="300" fill="url(#s)"/><circle cx="${80 + r() * 240}" cy="${60 + r() * 70}" r="${16 + r() * 22}" fill="#fff6d5" opacity=".85"/>
    ${city || hills(170 + r() * 40, 80, c, 0.85) + hills(220 + r() * 30, 60, d)}</svg>`;
  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
}
const mask = (path) => `url("data:image/svg+xml;charset=utf-8,${encodeURIComponent(`<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'>${path}</svg>`)}")`;

function openPhotos() {
  const st = { cols: 4, scale: "all", sel: "library" };
  const photos = Array.from({ length: 48 }, (_, i) => ({ src: photo(i + 1), fav: i % 7 === 0, shared: i % 3 === 1 }));
  const side = (key, icon, label) => h("div.side-row", { className: `side-row ${st.sel === key ? "sel" : ""}`, on: { click: () => { st.sel = key; renderSide(); } } }, sym(icon), label);
  const sidebar = h("div");
  const renderSide = () => sidebar.replaceChildren(
    side("library", "photo", "Library"), side("collections", "rectangle-fill", "Collections"),
    h("div.sec", "Pinned"), side("fav", "heart", "Favorites"), side("recent", "clock", "Recently Saved"), side("map", "globe", "Map"), side("videos", "film", "Videos"), side("shots", "screenshot", "Screenshots"),
    h("div.sec", "Albums"), side("a1", "folder", "Golden Hour"), side("a2", "folder", "Bay Area"), side("a3", "folder", "Stadium Nights"));
  renderSide();

  const grid = h("div.grid");
  const seg = Object.fromEntries(["years", "months", "all"].map((k) => [k, tb({ years: "Years", months: "Months", all: "All Photos" }[k], { text: true, on: k === "all", click: () => { st.scale = k; Object.entries(seg).forEach(([kk, b]) => b.classList.toggle("on", kk === k)); layout(); } })]));
  const win = createWindow({
    app: "photos", w: 1040, h: 640, sidebar, sidebarWidth: 200, className: "photos", content: grid,
    toolbar: [
      h("div.title", h("div.stack", "Library", h("span.subtitle", "Jun 19 – Jul 1, 2026"))),
      h("div.grow"),
      pill(tb("photo", { chev: true, title: "Show" })),
      pill(tb("minus", { title: "Zoom out", click: () => { st.cols = Math.min(9, st.cols + 1); layout(); } }), div(), tb("plus", { title: "Zoom in", click: () => { st.cols = Math.max(2, st.cols - 1); layout(); } })),
      pill(seg.years, seg.months, seg.all),
      pill(tb("mirror", { title: "Compare" }), tb("list", { title: "Sort" }), tb("ellipsis", { title: "More" })),
    ],
  });
  grid.style.setProperty("--heart", mask(`<path d="M12 21s-8-4.7-8-10.7A4.6 4.6 0 0 1 12 7.2a4.6 4.6 0 0 1 8 3.1C20 16.3 12 21 12 21z"/>`));
  grid.style.setProperty("--people", mask(`<circle cx="9" cy="8" r="3.5"/><path d="M2 20c.6-4 3.4-6 7-6s6.4 2 7 6z"/><circle cx="17" cy="9" r="2.8"/><path d="M15.5 14.2c3.5-.6 6 1 6.5 4.8h-4.2c-.3-2-1-3.6-2.3-4.8z"/>`));

  function layout() {
    const cols = st.scale === "years" ? 9 : st.scale === "months" ? 6 : st.cols;
    grid.style.setProperty("--cols", cols);
    // FLIP so tiles glide to their new positions when the zoom level changes.
    const before = new Map([...grid.children].map((el) => [el, el.getBoundingClientRect()]));
    if (!grid.children.length) grid.append(...photos.map((p, i) => {
      const el = h("div.ph", { className: `ph ${p.fav ? "fav" : ""} ${p.shared ? "shared" : ""}`, style: { backgroundImage: `url("${p.src}")` }, on: { dblclick: () => view(el, p) } });
      el.title = `IMG_${1142 + i}.HEIC`;
      return el;
    }));
    for (const [el, r0] of before) {
      const r1 = el.getBoundingClientRect();
      if (!r1.width) continue;
      animate(el, [{ transform: `translate(${r0.left - r1.left}px, ${r0.top - r1.top}px) scale(${r0.width / r1.width})`, transformOrigin: "top left" }, { transform: "none", transformOrigin: "top left" }], "snappy");
    }
  }

  function view(tile, p) {
    const img = h("img", { src: p.src });
    const close = h("div.pill.close", tb("xmark", { title: "Close", click: () => shut() }));
    const v = h("div.viewer", img, close);
    win.main.append(v);
    const from = tile.getBoundingClientRect(), to = img.getBoundingClientRect();
    const t = `translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${from.width / to.width}, ${from.height / to.height})`;
    img.style.transformOrigin = "top left";
    animate(img, [{ transform: t, borderRadius: "0" }, { transform: "none" }], "bouncy");
    animate(v, [{ backgroundColor: "transparent" }, {}], "smooth");
    async function shut() {
      const back = tile.getBoundingClientRect(), now = img.getBoundingClientRect();
      close.remove();
      v.animate([{ backgroundColor: getComputedStyle(v).backgroundColor }, { backgroundColor: "transparent" }], { duration: 300, fill: "forwards" });
      await animate(img, [{ transform: "none" }, { transform: `translate(${back.left - now.left}px, ${back.top - now.top}px) scale(${back.width / now.width}, ${back.height / now.height})` }], "snappy", { keep: true });
      v.remove();
    }
  }

  layout();
  return win;
}

registerApp("photos", openPhotos, {
  Image: [{ label: "Rotate Clockwise", kbd: "⌘R" }, { label: "Favorite", icon: "heart", kbd: "." }, "-", { label: "Adjust Date and Time…" }, { label: "Show Edit", kbd: "↩" }],
});
