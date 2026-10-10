// Mission Control (⌃↑ or F3): every window glides into a non-overlapping grid
// under a Spaces bar; hover to highlight, click to pick, Esc to leave.
import { h, sym, animate, bus } from "./util.js";
import { windows, focus } from "./wm.js";
import { APPS } from "./apps.js";

let active = null;

function layout(ws, area) {
  // Choose the column count that gives the largest thumbnails.
  let best = null;
  for (let cols = 1; cols <= ws.length; cols++) {
    const rows = Math.ceil(ws.length / cols);
    const cw = area.w / cols, ch = area.h / rows;
    const s = Math.min(...ws.map((w) => Math.min((cw - 40) / w.el.offsetWidth, (ch - 50) / w.el.offsetHeight, 0.8)));
    if (!best || s > best.s) best = { cols, rows, s, cw, ch };
  }
  return ws.map((w, i) => {
    const r = Math.floor(i / best.cols), c = i % best.cols;
    const inRow = Math.min(best.cols, ws.length - r * best.cols);
    const offset = (area.w - inRow * best.cw) / 2;
    const s = best.s, ww = w.el.offsetWidth * s, wh = w.el.offsetHeight * s;
    return { w, s, x: area.x + offset + c * best.cw + (best.cw - ww) / 2, y: area.y + r * best.ch + (best.ch - wh) / 2 - 10 };
  });
}

export function toggleMissionControl() { active ? exit() : enter(); }

function enter() {
  const ws = windows.filter((w) => !w.minimized);
  bus.emit("overlays:close");
  const desk = document.getElementById("desktop");
  const veil = h("div#mc-veil");
  const spaces = h("div#mc-spaces", h("button.space.on", h("span.thumb"), h("small", "Desktop 1")), h("button.space", h("span.thumb"), h("small", "Desktop 2")), h("button.space.add.glass-regular", sym("plus")));
  desk.append(veil, spaces);
  desk.classList.add("mission");
  animate(veil, [{ opacity: 0 }, { opacity: 1 }], "smooth");
  animate(spaces, [{ opacity: 0, transform: "translateY(-30px)" }, { opacity: 1, transform: "none" }], "window");
  const slots = layout(ws, { x: 40, y: 150, w: innerWidth - 80, h: innerHeight - 250 });
  const labels = [];
  for (const { w, s, x, y } of slots) {
    const t = `translate(${x - w.el.offsetLeft}px, ${y - w.el.offsetTop}px) scale(${s})`;
    w.el.style.transformOrigin = "0 0";
    w._z = w.el.style.zIndex;
    w.el.style.zIndex = String(9200 + slots.indexOf(slots.find((z) => z.w === w)));
    w._mc = w.el.animate([{ transform: "none" }, { transform: t }], { duration: 560, easing: getComputedStyle(document.documentElement).getPropertyValue("--spring-window").trim(), fill: "forwards" });
    w.el.classList.add("mc-item");
    const label = h("div.mc-label.glass-menu", APPS[w.app]?.name ?? "", w.title && w.title !== APPS[w.app]?.name ? ` — ${w.title}` : "");
    label.style.left = `${x + (w.el.offsetWidth * s) / 2}px`;
    label.style.top = `${y + w.el.offsetHeight * s + 10}px`;
    desk.append(label);
    labels.push(label);
    w._mcPick = (e) => { e.stopPropagation(); e.preventDefault(); exit(w); };
    w.el.addEventListener("mousedown", w._mcPick, true);
  }
  veil.addEventListener("mousedown", () => exit());
  active = { ws, veil, spaces, labels };
}

function exit(pick) {
  if (!active) return;
  const { ws, veil, spaces, labels } = active;
  active = null;
  document.getElementById("desktop").classList.remove("mission");
  labels.forEach((l) => l.remove());
  for (const w of ws) {
    w.el.removeEventListener("mousedown", w._mcPick, true);
    w.el.classList.remove("mc-item");
    const a = w._mc; if (!a) continue;
    a.reverse();
    a.finished.then(() => { a.cancel(); w.el.style.transformOrigin = ""; });
  }
  veil.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 300, fill: "forwards" }).finished.then(() => veil.remove());
  spaces.animate([{ opacity: 1 }, { opacity: 0, transform: "translateY(-30px)" }], { duration: 260, fill: "forwards" }).finished.then(() => spaces.remove());
  // Restore stacking, then raise the chosen window.
  ws.forEach((w) => (w.el.style.zIndex = w._z));
  if (pick) focus(pick);
}

addEventListener("keydown", (e) => {
  if ((e.ctrlKey && e.key === "ArrowUp") || e.key === "F3") { toggleMissionControl(); e.preventDefault(); }
  else if (e.key === "Escape" && active) exit();
});
bus.on("mission", toggleMissionControl);
