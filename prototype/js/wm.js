// Window manager: creation, focus/stacking, drag, resize, zoom, minimise to the
// Dock and spring-animated open/close. Mirrors what the compositor + shell do on Linux.
import { h, sym, animate, bus, clamp } from "./util.js";

const layer = () => document.getElementById("windows");
export const windows = [];
let z = 10;
let cascade = 0;
let winSeq = 0;

export function createWindow(o) {
  const w = {
    id: ++winSeq, app: o.app, title: o.title ?? "", minimized: false, zoomed: false, onClose: o.onClose,
    sidebarWidth: o.sidebar ? (o.sidebarWidth ?? 212) : 0,
  };
  const width = o.w ?? 900, height = o.h ?? 560;
  const x = o.x ?? Math.round((innerWidth - width) / 2 + cascade * 28 - 60);
  const y = o.y ?? Math.round(Math.max(44, (innerHeight - height) / 2 - 40 + cascade * 26));
  cascade = (cascade + 1) % 6;

  const lights = h("div.lights",
    h("button.close", { title: "Close", on: { click: () => w.close() } }, sym("xmark")),
    h("button.min", { title: "Minimize", on: { click: () => w.minimize() } }, sym("minus")),
    h("button.zoom", { title: "Zoom", on: { click: () => w.zoom() } }, sym("plus")));
  lights.addEventListener("mousedown", (e) => e.stopPropagation());

  w.toolbar = h("div.toolbar", o.toolbar ?? []);
  w.content = h("div.win-content", { className: `win-content ${o.noToolbar ? "no-toolbar" : ""}` }, o.content ?? []);
  w.edge = h("div.scroll-edge");
  // overlaySidebar: content runs full-bleed underneath the floating sidebar (Maps, Weather).
  w.main = h("div.win-main", { style: { "--main-left": o.sidebar && !o.overlaySidebar ? `${w.sidebarWidth + 8}px` : "0px" } },
    o.noToolbar ? null : w.toolbar, w.edge, w.content, o.statusbar ?? null);
  if (!o.sidebar) w.toolbar.style.paddingLeft = "92px";
  else if (o.overlaySidebar) w.toolbar.style.paddingLeft = `${w.sidebarWidth + 22}px`;
  w.sidebar = o.sidebar ? h("aside.win-sidebar", { style: { "--sidebar-w": `${w.sidebarWidth}px` } }, o.sidebar) : null;

  w.el = h("section.win", { className: `win ${o.className ?? ""}`, style: { left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${height}px` } },
    lights, w.sidebar, w.main,
    ["r", "b", "br", "l"].map((d) => h(`div.resize.${d}`, { on: { mousedown: (e) => startResize(e, w, d) } })));
  w.el._win = w;

  w.content.addEventListener("scroll", () => w.main.classList.toggle("scrolled", w.content.scrollTop > 2), { passive: true });
  w.el.addEventListener("mousedown", () => focus(w), true);
  const dragStart = (e) => {
    if (e.button !== 0 || e.target.closest("button, input, .pill, .side-row, [data-nodrag]")) return;
    startDrag(e, w);
  };
  w.toolbar.addEventListener("mousedown", dragStart);
  w.toolbar.addEventListener("dblclick", (e) => { if (!e.target.closest("button, input, .pill")) w.zoom(); });
  w.sidebar?.addEventListener("mousedown", (e) => { if (e.offsetY < 44 && e.target === w.sidebar) dragStart(e); });
  if (o.noToolbar) w.el.addEventListener("mousedown", (e) => { if (e.target === w.el || e.target.dataset.drag != null) dragStart(e); });

  w.focus = () => focus(w);
  w.close = () => close(w);
  w.minimize = () => minimize(w);
  w.restore = () => restore(w);
  w.zoom = () => zoom(w);
  w.setTitle = (t) => { w.title = t; bus.emit("windows"); };

  layer().append(w.el);
  windows.push(w);
  focus(w);
  animate(w.el, [{ opacity: 0, transform: "scale(.9) translateY(10px)" }, { opacity: 1, transform: "none" }], "window");
  bus.emit("windows");
  return w;
}

export function focus(w) {
  if (!w || w.minimized) return;
  const was = activeWindow();
  w.el.style.zIndex = ++z;
  windows.forEach((o) => o.el.classList.toggle("inactive", o !== w));
  if (was !== w) bus.emit("focus", w);
}
export const activeWindow = () =>
  windows.filter((w) => !w.minimized).sort((a, b) => (+b.el.style.zIndex || 0) - (+a.el.style.zIndex || 0))[0] ?? null;
export const windowsOf = (app) => windows.filter((w) => w.app === app);

async function close(w) {
  const i = windows.indexOf(w);
  if (i < 0) return;
  windows.splice(i, 1);
  w.el.style.pointerEvents = "none";
  await w.el.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(.94)" }], { duration: 170, easing: "cubic-bezier(.4,0,1,1)", fill: "forwards" }).finished;
  w.el.remove();
  w.onClose?.();
  const next = activeWindow();
  if (next) focus(next); else bus.emit("focus", null);
  bus.emit("windows");
}

// Minimise: a genie. The window's outline funnels towards its Dock tile (a
// clip-path polygon whose bottom edge pinches to the tile), then the whole
// shape pours down into it. Minimised windows get their own tile in the Dock.
function dockTarget(w) {
  const tile = document.querySelector(`.dock-item[data-win="${w.id}"]`) ?? document.querySelector(`.dock-item[data-app="${w.app}"]`) ?? document.getElementById("dock");
  return tile.getBoundingClientRect();
}
function genieFrames(w) {
  const r = w.el.getBoundingClientRect(), t = dockTarget(w);
  const cx = t.left + t.width / 2;
  const tx = Math.max(6, Math.min(94, ((cx - r.left) / r.width) * 100));    // target x, % of window
  const dx = cx - (r.left + (tx / 100) * r.width);
  const dy = t.top + t.height * 0.55 - r.bottom;
  const lerp = (a, b, k) => a + (b - a) * k;
  const poly = (k1, k2) => {
    // Six points: corners plus mid-sides, so the sides can bow into a funnel.
    const top = [lerp(0, tx - 8, k2), lerp(100, tx + 8, k2)];
    const mid = [lerp(0, tx - 7, Math.min(1, k1 * 0.5 + k2 * 0.5)), lerp(100, tx + 7, Math.min(1, k1 * 0.5 + k2 * 0.5))];
    const bot = [lerp(0, tx - 3, k1), lerp(100, tx + 3, k1)];
    return `polygon(${top[0]}% 0%, ${top[1]}% 0%, ${mid[1]}% 50%, ${bot[1]}% 100%, ${bot[0]}% 100%, ${mid[0]}% 50%)`;
  };
  w.el.style.transformOrigin = `${tx}% 100%`;
  return [
    { clipPath: poly(0, 0), transform: "none", opacity: 1 },
    { clipPath: poly(0.85, 0.15), transform: `translate(${dx * 0.3}px, ${dy * 0.12}px)`, opacity: 1, offset: 0.4 },
    { clipPath: poly(1, 0.75), transform: `translate(${dx * 0.8}px, ${dy * 0.7}px) scale(.8, .45)`, opacity: 0.9, offset: 0.75 },
    { clipPath: poly(1, 1), transform: `translate(${dx}px, ${dy}px) scale(.16, .02)`, opacity: 0 },
  ];
}
async function minimize(w) {
  if (w.minimized) return;
  w.minimized = true;
  bus.emit("windows");                        // the Dock makes room for the window's tile
  await new Promise(requestAnimationFrame);
  w.el.classList.add("animating");
  await w.el.animate(genieFrames(w), { duration: 560, easing: "cubic-bezier(.5,0,.3,1)", fill: "forwards" }).finished;
  w.el.style.visibility = "hidden";
  w.el.getAnimations().forEach((a) => a.cancel());
  w.el.style.transformOrigin = "";
  w.el.classList.remove("animating");
  bus.emit("minimized", w);
  const next = activeWindow();
  if (next) focus(next); else bus.emit("focus", null);
}
async function restore(w) {
  if (!w.minimized) return focus(w);
  const frames = genieFrames(w).reverse();   // measured while the tile still exists
  w.minimized = false;
  w.el.style.visibility = "";
  focus(w);
  w.el.classList.add("animating");
  const a = w.el.animate(frames, { duration: 520, easing: "cubic-bezier(.2,.7,.3,1)" });
  bus.emit("windows");
  await a.finished;
  w.el.style.transformOrigin = "";
  w.el.classList.remove("animating");
}

function zoom(w) {
  const from = { left: w.el.style.left, top: w.el.style.top, width: w.el.style.width, height: w.el.style.height };
  let to;
  if (w.zoomed) to = w.saved;
  else {
    w.saved = from;
    const dock = document.getElementById("dock").getBoundingClientRect();
    to = { left: "6px", top: "36px", width: `${innerWidth - 12}px`, height: `${dock.top - 44}px` };
  }
  w.zoomed = !w.zoomed;
  Object.assign(w.el.style, to);
  animate(w.el, [from, to], "window");
}

// Edge tiling: drag a window to the left/right edge (halves) or the menu bar
// (fill) and a glass preview shows where it will land.
function snapZone(x, y) {
  const dock = document.getElementById("dock").getBoundingClientRect();
  const H = dock.top - 44, half = innerWidth / 2;
  if (x <= 4) return { left: 6, top: 36, width: half - 9, height: H };
  if (x >= innerWidth - 5) return { left: half + 3, top: 36, width: half - 9, height: H };
  if (y <= 31) return { left: 6, top: 36, width: innerWidth - 12, height: H };
  return null;
}
let preview = null;
function showPreview(zone, w) {
  if (!zone) { if (preview) { const p = preview; preview = null; p.animate([{ opacity: 1 }, { opacity: 0, transform: "scale(.96)" }], { duration: 160, fill: "forwards" }).finished.then(() => p.remove()); } return; }
  const px = (r) => ({ left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px` });
  if (!preview) {
    preview = h("div#snap-preview.glass");
    layer().append(preview);
    preview.style.zIndex = String(+w.el.style.zIndex - 1);
    const r = w.el.getBoundingClientRect();
    Object.assign(preview.style, px(zone));
    animate(preview, [{ ...px({ left: r.left, top: r.top, width: r.width, height: r.height }), opacity: 0 }, { ...px(zone), opacity: 1 }], "popover");
  } else if (preview.dataset.z !== JSON.stringify(zone)) {
    const from = { left: preview.style.left, top: preview.style.top, width: preview.style.width, height: preview.style.height };
    Object.assign(preview.style, px(zone));
    animate(preview, [from, px(zone)], "snappy");
  }
  preview.dataset.z = JSON.stringify(zone);
}

function startDrag(e, w) {
  e.preventDefault();
  const sx = e.clientX, sy = e.clientY, ox = w.el.offsetLeft, oy = w.el.offsetTop;
  let zone = null;
  const move = (ev) => {
    w.el.style.left = `${ox + ev.clientX - sx}px`;
    w.el.style.top = `${clamp(oy + ev.clientY - sy, 30, innerHeight - 60)}px`;
    zone = snapZone(ev.clientX, ev.clientY);
    showPreview(zone, w);
  };
  const up = () => {
    removeEventListener("mousemove", move); removeEventListener("mouseup", up);
    showPreview(null);
    if (zone) {
      const from = { left: w.el.style.left, top: w.el.style.top, width: w.el.style.width, height: w.el.style.height };
      const to = { left: `${zone.left}px`, top: `${zone.top}px`, width: `${zone.width}px`, height: `${zone.height}px` };
      if (!w.zoomed) w.saved = { ...from, left: `${ox}px`, top: `${oy}px` };
      Object.assign(w.el.style, to);
      animate(w.el, [from, to], "window");
    }
  };
  addEventListener("mousemove", move);
  addEventListener("mouseup", up);
}

function startResize(e, w, dir) {
  e.preventDefault(); e.stopPropagation();
  const sx = e.clientX, sy = e.clientY, r = { x: w.el.offsetLeft, w: w.el.offsetWidth, h: w.el.offsetHeight };
  const minW = parseInt(getComputedStyle(w.el).minWidth), minH = parseInt(getComputedStyle(w.el).minHeight);
  const move = (ev) => {
    const dx = ev.clientX - sx, dy = ev.clientY - sy;
    if (dir.includes("r")) w.el.style.width = `${Math.max(minW, r.w + dx)}px`;
    if (dir.includes("b")) w.el.style.height = `${Math.max(minH, r.h + dy)}px`;
    if (dir === "l") { const nw = Math.max(minW, r.w - dx); w.el.style.width = `${nw}px`; w.el.style.left = `${r.x + r.w - nw}px`; }
  };
  const up = () => { removeEventListener("mousemove", move); removeEventListener("mouseup", up); };
  addEventListener("mousemove", move);
  addEventListener("mouseup", up);
}

// Shared toolbar builders
export const pill = (...kids) => h("div.pill", kids);
export const tb = (icon, opts = {}) =>
  h("button.tb", { title: opts.title, className: `tb ${opts.on ? "on" : ""} ${opts.text ? "text" : ""}`, disabled: opts.disabled, on: { click: opts.click } },
    typeof icon === "string" && !opts.text ? sym(icon) : icon, opts.chev ? h("span.chev", sym("chevron-down")) : null);
export const div = () => h("span.div");
