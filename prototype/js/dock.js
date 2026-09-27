// Dock: Liquid Glass shelf with cosine magnification, tooltips, running
// indicators, launch bounce and context menus.
import { h, appIcon, state, bus } from "./util.js";
import { APPS, launch } from "./apps.js";
import { windowsOf } from "./wm.js";
import { openMenu } from "./menus.js";

const PINNED = ["launcher", "files", "browser", "mail", "messages", "maps", "photos", "music", "calendar", "notes", "weather", "store", "settings", "terminal"];

export function initDock() {
  const dock = document.getElementById("dock");
  dock.classList.add("glass");
  const tip = h("div.dock-tip.glass-menu", { hidden: true });
  document.getElementById("desktop").append(tip);
  let base = [];          // un-magnified centres, captured on mouseenter
  let mouseX = null;

  function tile(id, key = id, label = APPS[id]?.name ?? id) {
    const el = h("div.dock-item", { "data-app": id }, appIcon(key), h("span.run"));
    el.addEventListener("click", () => {
      if (id === "downloads") launch("files", `/Users/golden/Downloads`);
      else if (id === "trash") bus.emit("notify", { app: "files", title: "Trash", body: "The Trash is empty." });
      else if (id === "launcher") bus.emit("spotlight", "", "apps");
      else launch(id);
    });
    el.addEventListener("mouseenter", () => showTip(el, label));
    el.addEventListener("mouseleave", () => (tip.hidden = true));
    el.addEventListener("mousedown", (e) => e.stopPropagation());
    el.addEventListener("contextmenu", (e) => { e.preventDefault(); e.stopPropagation(); tip.hidden = true; menu(el, id); });
    return el;
  }

  function render() {
    const extra = [...new Set([...document.querySelectorAll(".win")].map((w) => w._win?.app))].filter((a) => a && !PINNED.includes(a));
    dock.replaceChildren(
      ...PINNED.map((id) => tile(id)), ...extra.map((id) => tile(id)),
      h("div.dock-sep"),
      tile("downloads", "folder", "Downloads"), tile("trash", "trash", "Trash"),
    );
    running();
  }
  function running() {
    dock.querySelectorAll(".dock-item").forEach((el) => el.classList.toggle("running", windowsOf(el.dataset.app).length > 0));
  }

  function showTip(el, label) {
    tip.textContent = label; tip.hidden = false;
    requestAnimationFrame(() => {
      const r = el.getBoundingClientRect();
      tip.style.left = `${r.left + r.width / 2}px`;
      tip.style.top = `${r.top - 38}px`;
    });
  }

  function menu(el, id) {
    const r = el.getBoundingClientRect();
    const open = windowsOf(id).length > 0;
    openMenu([
      ...(open ? windowsOf(id).map((w) => ({ label: w.title || APPS[id].name, action: () => w.restore() })).concat("-") : []),
      { label: "Options", submenu: [{ label: "Keep in Dock", checked: PINNED.includes(id) }, { label: "Open at Login" }, { label: "Show in Files", action: () => launch("files", "/Applications") }] },
      "-",
      { label: "Show All Windows", disabled: !open },
      { label: open ? "Hide" : "Open", action: () => launch(id) },
      ...(open ? [{ label: "Quit", action: () => windowsOf(id).forEach((w) => w.close()) }] : []),
    ], { x: r.left + r.width / 2 - 20, y: r.top - 10 - 26 * 6 });
  }

  // Magnification: size follows a cosine falloff of the pointer distance,
  // measured against the resting layout so the Dock never chases itself.
  const size = () => state.dockSize;
  const RANGE = () => size() * 3.2;
  function magnify() {
    const items = [...dock.querySelectorAll(".dock-item")];
    items.forEach((el, i) => {
      let s = size();
      if (mouseX != null && state.magnify) {
        const d = Math.abs(mouseX - base[i]);
        s = size() + (Math.max(size() * 1.6, 86) - size()) * (d < RANGE() ? Math.cos((d / RANGE()) * (Math.PI / 2)) ** 1.4 : 0);
      }
      el.style.width = el.style.height = `${s}px`;
    });
  }
  dock.addEventListener("mouseenter", () => {
    base = [...dock.querySelectorAll(".dock-item")].map((el) => { const r = el.getBoundingClientRect(); return r.left + r.width / 2; });
    dock.querySelectorAll(".dock-item").forEach((el) => (el.style.transition = "width 90ms linear, height 90ms linear"));
  });
  dock.addEventListener("mousemove", (e) => { mouseX = e.clientX; requestAnimationFrame(magnify); if (!tip.hidden) { const el = e.target.closest(".dock-item"); el && showTip(el, tip.textContent); } });
  dock.addEventListener("mouseleave", () => {
    mouseX = null;
    dock.querySelectorAll(".dock-item").forEach((el) => (el.style.transition = "width var(--spring-dock-duration) var(--spring-snappy), height var(--spring-dock-duration) var(--spring-snappy)"));
    magnify();
  });

  const applySize = () => document.documentElement.style.setProperty("--dock-size", `${size()}px`);
  bus.on("state:dockSize", () => { applySize(); magnify(); });
  applySize();
  bus.on("windows", () => { const ids = [...dock.querySelectorAll(".dock-item")].map((e) => e.dataset.app).join(); render(); if (ids !== [...dock.querySelectorAll(".dock-item")].map((e) => e.dataset.app).join()) magnify(); });
  bus.on("state:theme", render);
  render();
}
