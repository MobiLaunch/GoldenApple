// Dock: Liquid Glass shelf with cosine magnification, tooltips, running
// indicators, launch bounce and context menus.
import { h, sym, appIcon, state, bus, animate } from "./util.js";
import * as fs from "./vfs.js";
import { APPS, launch } from "./apps.js";
import { windows, windowsOf } from "./wm.js";
import { openMenu } from "./menus.js";

const PINNED = ["launcher", "files", "browser", "mail", "messages", "maps", "photos", "music", "calendar", "notes", "weather", "store", "settings", "terminal"];

export function initDock() {
  const dock = document.getElementById("dock");
  dock.classList.add("glass");
  const tip = h("div.dock-tip.glass-menu", { hidden: true });
  document.getElementById("desktop").append(tip);
  let base = [];          // un-magnified centres, captured on mouseenter
  let mouseX = null;
  let tipAnchor = null;
  let frame = 0;
  let trackTipUntil = 0;
  function schedule() {
    if (!frame) frame = requestAnimationFrame(() => { frame = 0; magnify(); });
  }

  function tile(id, key = id, label = APPS[id]?.name ?? id) {
    const el = h("div.dock-item", { "data-app": id }, appIcon(key), h("span.run"));
    el.addEventListener("click", () => {
      if (id === "downloads") stack(el);
      else if (id === "trash") launch("files", "@trash");
      else if (id === "launcher") bus.emit("spotlight", "", "apps");
      else launch(id);
    });
    el.addEventListener("mouseenter", () => showTip(el, label));
    el.addEventListener("mouseleave", () => (tip.hidden = true, tipAnchor = null));
    el.addEventListener("mousedown", (e) => e.stopPropagation());
    el.addEventListener("contextmenu", (e) => { e.preventDefault(); e.stopPropagation(); tip.hidden = true; menu(el, id); });
    return el;
  }

  function render() {
    tip.hidden = true; tipAnchor = null;
    const extra = [...new Set([...document.querySelectorAll(".win")].map((w) => w._win?.app))].filter((a) => a && !PINNED.includes(a));
    const minimized = windows.filter((w) => w.minimized);
    const before = new Set([...dock.querySelectorAll(".dock-item[data-win]")].map((e) => e.dataset.win));
    dock.replaceChildren(
      ...PINNED.map((id) => tile(id)), ...extra.map((id) => tile(id)),
      h("div.dock-sep"),
      tile("downloads", "folder", "Downloads"), ...minimized.map(miniTile), tile("trash", fs.TRASH.length ? "trash-full" : "trash", "Trash"),
    );
    // A new minimised tile grows in from zero width while the genie lands.
    dock.querySelectorAll(".dock-item[data-win]").forEach((el) => {
      if (!before.has(el.dataset.win)) animate(el, [{ width: "0px", opacity: 0 }, { width: `${size()}px`, opacity: 1 }], "snappy");
    });
    running();
  }
  // Minimised window: a live miniature of the window with its app badge.
  function miniTile(w) {
    const clone = w.el.cloneNode(true);
    clone.removeAttribute("id");
    clone.style.cssText = `position:absolute;left:0;top:0;width:${w.el.offsetWidth}px;height:${w.el.offsetHeight}px;transform-origin:0 0;visibility:visible;pointer-events:none;`;
    const s = (size() - 6) / Math.max(w.el.offsetWidth, w.el.offsetHeight);
    clone.style.transform = `translate(${(size() - w.el.offsetWidth * s) / 2}px, ${(size() - w.el.offsetHeight * s) / 2}px) scale(${s})`;
    clone.inert = true;
    const el = h("div.dock-item.mini", { "data-win": w.id, "data-app": `win-${w.id}` }, h("div.mini-shot", clone), h("span.mini-badge", appIcon(w.app)));
    el.addEventListener("click", () => w.restore());
    el.addEventListener("mouseenter", () => showTip(el, w.title || APPS[w.app]?.name));
    el.addEventListener("mouseleave", () => (tip.hidden = true, tipAnchor = null));
    el.addEventListener("mousedown", (e) => e.stopPropagation());
    return el;
  }

  // Downloads stack: a glass grid that springs up from the tile.
  let stackEl = null;
  function stack(tileEl) {
    if (stackEl) { closeStack(); return; }
    const items = fs.resolve("/Users/golden/Downloads")?.children ?? [];
    const r = tileEl.getBoundingClientRect();
    stackEl = h("div.dock-stack.glass-regular",
      h("div.ds-grid", items.map((n) => h("button.ds-item", { on: { click: () => { closeStack(); launch(n.kind === "image" ? "photos" : "files", n.kind === "image" ? undefined : "/Users/golden/Downloads"); } } }, appIcon(fs.iconFor(n)), h("span", n.name)))),
      h("button.ds-open", { on: { click: () => { closeStack(); launch("files", "/Users/golden/Downloads"); } } }, "Open in Files ", sym("chevron-right")));
    document.getElementById("desktop").append(stackEl);
    const sr = stackEl.getBoundingClientRect();
    stackEl.style.left = `${Math.min(innerWidth - sr.width - 8, r.left + r.width / 2 - sr.width / 2)}px`;
    // Sit above the Dock's magnified height, not the (possibly magnified) tile.
    const shelfTop = dock.getBoundingClientRect().top - (Math.max(size() * 1.6, 86) - size());
    stackEl.style.top = `${shelfTop - sr.height - 12}px`;
    tip.hidden = true;
    stackEl.style.transformOrigin = `${r.left + r.width / 2 - parseFloat(stackEl.style.left)}px 100%`;
    animate(stackEl, [{ opacity: 0, transform: "scale(.4) translateY(40px)" }, { opacity: 1, transform: "none" }], "popover");
    [...stackEl.querySelectorAll(".ds-item")].forEach((it, i) => animate(it, [{ opacity: 0, transform: "translateY(24px) scale(.7)" }, { opacity: 1, transform: "none" }], "bouncy", { delay: 40 + i * 30 }));
    stackEl.addEventListener("mousedown", (e) => e.stopPropagation());
  }
  function closeStack() {
    if (!stackEl) return;
    const el = stackEl; stackEl = null;
    el.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(.6) translateY(30px)" }], { duration: 180, easing: "ease-in", fill: "forwards" }).finished.then(() => el.remove());
  }
  addEventListener("mousedown", closeStack);
  bus.on("overlays:close", closeStack);
  bus.on("trash", render);

  function running() {
    dock.querySelectorAll(".dock-item").forEach((el) => el.classList.toggle("running", windowsOf(el.dataset.app).length > 0));
  }

  function showTip(el, label) {
    tipAnchor = el;
    tip.textContent = label; tip.hidden = false;
    trackTipUntil = performance.now() + 160;
    schedule();
  }
  function positionTip() {
    if (tip.hidden || !tipAnchor?.isConnected) return;
    const r = tipAnchor.getBoundingClientRect();
    const half = tip.offsetWidth / 2;
    tip.style.left = `${Math.max(half + 8, Math.min(innerWidth - half - 8, r.left + r.width / 2))}px`;
    tip.style.top = `${Math.max(8, r.top - tip.offsetHeight - 10)}px`;
  }

  function menu(el, id) {
    const r = el.getBoundingClientRect();
    if (id === "trash") return openMenu([{ label: "Open", action: () => launch("files", "@trash") }, "-",
      { label: "Empty Trash…", disabled: !fs.TRASH.length, action: () => { fs.TRASH.length = 0; bus.emit("trash"); } }], { x: r.left, y: r.top - 90 });
    const open = windowsOf(id).length > 0;
    openMenu([
      ...(open ? windowsOf(id).map((w) => ({ label: w.title || APPS[id].name, action: () => w.restore() })).concat("-") : []),
      { label: "Options", icon: "gear", submenu: [{ label: "Keep in Dock", checked: PINNED.includes(id) }, { label: "Open at Login" }, { label: "Show in Files", icon: "folder", action: () => launch("files", "/Applications") }] },
      "-",
      { label: "Show All Windows", icon: "grid", disabled: !open, action: () => bus.emit("mission") },
      { label: open ? "Hide" : "Open", icon: open ? "eye" : "doc", action: () => launch(id) },
      ...(open ? [{ label: "Quit", icon: "xmark", action: () => windowsOf(id).forEach((w) => w.close()) }] : []),
    ], { x: r.left + r.width / 2 - 20, y: r.top - 10 - 26 * 6 });
  }

  // Magnification: size follows a cosine falloff of the pointer distance,
  // measured against the resting layout so the Dock never chases itself.
  const size = () => Math.min(state.dockSize, Math.max(16, (innerWidth - 50) / (dock.querySelectorAll(".dock-item").length + 6) - 3));
  const reduced = () => state.reduceMotion || matchMedia("(prefers-reduced-motion: reduce)").matches;
  function restCenters() {
    const children = [...dock.children];
    const widths = children.map(el => el.classList.contains("dock-item") ? size() : 11);
    const total = widths.reduce((a, b) => a + b, 0) + 3 * (children.length - 1) + 14;
    let left = (innerWidth - total) / 2 + 7;
    base = [];
    children.forEach((el, i) => {
      if (el.classList.contains("dock-item")) base.push(left + widths[i] / 2);
      left += widths[i] + 3;
    });
  }
  function magnify() {
    const items = [...dock.querySelectorAll(".dock-item")];
    restCenters();
    const widths = items.map((_, i) => {
      const d = Math.abs(mouseX - base[i]);
      return mouseX != null && state.magnify && !reduced()
        ? size() + (Math.min(96, size() * 1.6) - size()) * (d < size() * 3.2 ? Math.cos(d / (size() * 3.2) * Math.PI / 2) ** 1.4 : 0)
        : size();
    });
    items.forEach((el, i) => {
      const value = `${widths[i]}px`;
      if (el.style.width !== value) el.style.width = el.style.height = value;
    });
    positionTip();
    if (!tip.hidden && performance.now() < trackTipUntil) schedule();
  }
  dock.addEventListener("mouseenter", () => {
    dock.querySelectorAll(".dock-item").forEach(el => el.style.transition = reduced() ? "none" : "width 110ms ease-out, height 110ms ease-out");
  });
  dock.addEventListener("mousemove", e => { mouseX = e.clientX; trackTipUntil = performance.now() + 160; schedule(); });
  dock.addEventListener("mouseleave", () => { mouseX = null; tip.hidden = true; tipAnchor = null; schedule(); });
  const applySize = () => { document.documentElement.style.setProperty("--dock-size", `${size()}px`); schedule(); };
  bus.on("state:dockSize", applySize);
  bus.on("state:magnify", schedule);
  bus.on("state:reduceMotion", schedule);
  addEventListener("resize", applySize);
  applySize();
  bus.on("windows", () => { const ids = [...dock.querySelectorAll(".dock-item")].map((e) => e.dataset.app).join(); render(); if (ids !== [...dock.querySelectorAll(".dock-item")].map((e) => e.dataset.app).join()) applySize(); });
  bus.on("state:theme", render);
  render();
}

