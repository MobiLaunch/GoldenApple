// Boot: assemble the shell, apply appearance, global shortcuts, desktop menu.
import { SPRITE } from "../assets/icons.js";
import { h, sym, appIcon, refreshIcons, state, bus, animate, wait } from "./util.js";
import { initMenubar } from "./menubar.js";
import { initControlCenter } from "./controlcenter.js";
import { initDock } from "./dock.js";
import { initSpotlight } from "./spotlight.js";
import { initNotifications } from "./notifications.js";
import { initGlass } from "./glass.js";
import { openMenu } from "./menus.js";
import { boot, lock } from "./lock.js";
import "./mission.js";
import { launch, APPS } from "./apps.js";
import { activeWindow, windows } from "./wm.js";
import "./apps/files.js";
import "./apps/photos.js";
import "./apps/settings.js";
import "./apps/small.js";
import "./apps/web.js";
import "./apps/mail.js";
import "./apps/messages.js";
import "./apps/music.js";
import "./apps/calendar.js";
import "./apps/maps.js";
import "./apps/weather.js";
import "./apps/store.js";

document.body.insertAdjacentHTML("afterbegin", SPRITE);
const root = document.documentElement;
const ACCENTS = { blue: "#0a84ff", purple: "#bf5af2", pink: "#ff375f", red: "#ff453a", orange: "#ff9f0a", yellow: "#ffd60a", green: "#30d158", graphite: "#8e8e93" };
const WALL = { tide: "assets/wallpapers/tide.svg", dusk: "assets/wallpapers/dusk.svg" };
const darkQuery = matchMedia("(prefers-color-scheme: dark)");

// URL overrides make every state reproducible for screenshots: ?theme=dark&open=files,photos
const params = new URLSearchParams(location.search);
if (params.get("theme")) state.theme = params.get("theme");

function applyAppearance(animated) {
  const theme = state.theme === "auto" ? (darkQuery.matches ? "dark" : "light") : state.theme;
  const wall = WALL[state.wallpaper] ?? WALL.tide;
  const apply = () => {
    root.dataset.theme = theme;
    root.style.setProperty("--accent", ACCENTS[state.accent] ?? ACCENTS.blue);
    root.style.setProperty("--wallpaper", `url("${new URL(wall, location.href)}")`);
    refreshIcons();
    toneMenubar(wall);
  };
  // Appearance changes cross-fade the whole screen, like the system does.
  if (animated && document.startViewTransition) document.startViewTransition(apply); else apply();
}
// The menu bar has no material of its own, so each half picks light or dark text
// from the brightness of the wallpaper behind it (like the system does).
function toneMenubar(src) {
  const img = new Image();
  img.onload = () => {
    const W = 288, H = 180, c = document.createElement("canvas");
    c.width = W; c.height = H;
    const ctx = c.getContext("2d");
    const s = Math.max(W / img.width, H / img.height);
    ctx.drawImage(img, (W - img.width * s) / 2, (H - img.height * s) / 2, img.width * s, img.height * s);
    const lum = (x0, x1) => {
      const d = ctx.getImageData(x0, 0, x1 - x0, 7).data;
      let t = 0;
      for (let i = 0; i < d.length; i += 4) t += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255;
      return t / (d.length / 4);
    };
    const sides = document.querySelectorAll("#menubar .side");
    sides[0]?.classList.toggle("tone-dark", lum(0, W * 0.45) > 0.66);
    sides[1]?.classList.toggle("tone-dark", lum(W * 0.55, W) > 0.66);
  };
  img.src = src;
}
bus.on("state", ({ key }) => { if (["theme", "accent", "wallpaper"].includes(key)) applyAppearance(true); });
darkQuery.addEventListener("change", () => state.theme === "auto" && applyAppearance(true));
applyAppearance(false);

// Brightness dims the whole screen; volume shows the system HUD.
bus.on("state:brightness", (v) => (document.getElementById("desktop").style.filter = v < 0.98 ? `brightness(${0.45 + v * 0.55})` : ""));

// ------------------------------------------------------------------ shell
const cc = initControlCenter();
const spotlight = initSpotlight();
const notes = initNotifications();
initMenubar(document.getElementById("menubar"), { toggleCC: (b) => cc.toggle(b), toggleWidgets: (b) => notes.toggle(b), openSpotlight: (t, c) => spotlight.open(t, c) });
initDock();
initGlass();

// Desktop icons + wallpaper context menu
const deskIcons = document.getElementById("desktop-icons");
[["System HD", "disk", () => launch("files", "/")], ["Projects", "folder", () => launch("files", "/Users/golden/Desktop/Projects")], ["Wallpaper Draft.png", "image", () => launch("photos")]].forEach(([label, icon, open]) => {
  const el = h("div.desk-icon", appIcon(icon), h("span", label));
  el.addEventListener("mousedown", (e) => { e.stopPropagation(); deskIcons.querySelectorAll(".sel").forEach((x) => x.classList.remove("sel")); el.classList.add("sel"); });
  el.addEventListener("dblclick", open);
  deskIcons.append(el);
});
const wallpaper = document.getElementById("wallpaper");
// Rubber-band selection on the desktop.
wallpaper.addEventListener("mousedown", (e) => {
  deskIcons.querySelectorAll(".sel").forEach((x) => x.classList.remove("sel"));
  if (e.button !== 0) return;
  const sx = e.clientX, sy = e.clientY;
  const band = h("div#rubber");
  const move = (ev) => {
    if (!band.isConnected) { if (Math.hypot(ev.clientX - sx, ev.clientY - sy) < 4) return; document.getElementById("desktop").insertBefore(band, document.getElementById("windows")); }
    const r = { left: Math.min(sx, ev.clientX), top: Math.min(sy, ev.clientY), right: Math.max(sx, ev.clientX), bottom: Math.max(sy, ev.clientY) };
    Object.assign(band.style, { left: `${r.left}px`, top: `${r.top}px`, width: `${r.right - r.left}px`, height: `${r.bottom - r.top}px` });
    deskIcons.querySelectorAll(".desk-icon").forEach((ic) => {
      const b = ic.querySelector("img").getBoundingClientRect();
      ic.classList.toggle("sel", b.left < r.right && b.right > r.left && b.top < r.bottom && b.bottom > r.top);
    });
  };
  const up = () => { removeEventListener("mousemove", move); removeEventListener("mouseup", up); band.remove(); };
  addEventListener("mousemove", move); addEventListener("mouseup", up);
});
document.getElementById("desktop").addEventListener("contextmenu", (e) => {
  e.preventDefault();
  if (e.target !== wallpaper && e.target.id !== "windows") return;
  openMenu([
    { label: "New Folder" }, "-", { label: "Get Info" }, { label: "Change Wallpaper…", action: () => launch("settings", "wallpaper") }, { label: "Edit Widgets…" }, "-",
    { label: "Use Stacks" }, { label: "Sort By", submenu: [{ label: "None" }, { label: "Snap to Grid", checked: true }, "-", { label: "Name" }, { label: "Kind" }, { label: "Date Modified" }] },
    { label: "Clean Up" }, { label: "Show View Options" },
  ], { x: e.clientX, y: e.clientY });
});

// Screenshot flash + sleep veil
bus.on("screenshot", async () => {
  const f = document.getElementById("flash");
  await f.animate([{ opacity: 0 }, { opacity: 0.85, offset: 0.15 }, { opacity: 0 }], { duration: 420, easing: "ease-out" }).finished;
  bus.emit("notify", { app: "photos", title: "Screenshot", body: `Saved “Screenshot ${new Date().toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}.png” to Desktop.` });
});
// Sleep: the display fades to black; waking lands on the lock screen.
bus.on("sleep", async () => {
  const veil = h("div", { style: { position: "absolute", inset: 0, background: "#000", zIndex: 99999 } });
  document.getElementById("desktop").append(veil);
  await animate(veil, [{ opacity: 0 }, { opacity: 1 }], "smooth", { keep: true });
  const wake = async () => { removeEventListener("keydown", wake); lock(); await animate(veil, [{ opacity: 1 }, { opacity: 0 }], "smooth", { keep: true }); veil.remove(); };
  veil.addEventListener("click", wake, { once: true });
  addEventListener("keydown", wake);
});
bus.on("lock", () => lock());

// ------------------------------------------------------------------ app switcher (⌘/Alt + Tab)
const switcher = h("div#switcher", { hidden: true });
document.getElementById("desktop").append(switcher);
let swIdx = -1, swApps = [];
function showSwitcher(step) {
  if (swIdx < 0) {
    swApps = [...new Set(windows.slice().sort((a, b) => (+b.el.style.zIndex || 0) - (+a.el.style.zIndex || 0)).map((w) => w.app))];
    if (swApps.length < 1) return;
    swIdx = 0;
    switcher.replaceChildren(h("div.panel.glass-regular", swApps.map((id) => h("div.app", appIcon(id), APPS[id].name))));
    switcher.hidden = false;
    animate(switcher.firstChild, [{ opacity: 0, transform: "scale(.9)" }, { opacity: 1, transform: "none" }], "popover");
  }
  swIdx = (swIdx + step + swApps.length) % swApps.length;
  [...switcher.firstChild.children].forEach((c, i) => c.classList.toggle("sel", i === swIdx));
}
function commitSwitcher() {
  if (swIdx < 0) return;
  launch(swApps[swIdx]);
  swIdx = -1; switcher.hidden = true;
}

// ------------------------------------------------------------------ keyboard
addEventListener("keydown", (e) => {
  const mod = e.metaKey || e.ctrlKey;
  if (mod && e.code === "Space") { spotlight.toggle(); e.preventDefault(); return; }
  if ((mod || e.altKey) && e.key === "Tab") { showSwitcher(e.shiftKey ? -1 : 1); e.preventDefault(); return; }
  if (!mod || e.target.matches("input, textarea")) return;
  const w = activeWindow();
  const k = e.key.toLowerCase();
  if (k === "w" && w) { w.close(); e.preventDefault(); }
  else if (k === "m" && w) { w.minimize(); e.preventDefault(); }
  else if (k === "q" && w) { windows.filter((x) => x.app === w.app).forEach((x) => x.close()); e.preventDefault(); }
  else if (k === "n") { launch(w?.app ?? "files", "new"); e.preventDefault(); }
  else if (k === ",") { launch("settings"); e.preventDefault(); }
});
addEventListener("keyup", (e) => { if (["Meta", "Control", "Alt"].includes(e.key)) commitSwitcher(); });

// ------------------------------------------------------------------ boot
(async () => {
  // A plain URL plays the whole experience: boot, lock screen, desktop.
  const intro = [...params.keys()].length === 0 || params.has("boot");
  if (intro) { await boot(); await lock({ fromBoot: true }); }
  else if (params.has("lock")) await lock();
  const open = (params.get("open") ?? "files").split(",").filter(Boolean);
  for (const id of open) { launch(id); await wait(60); }
  if (params.get("cc")) cc.open(document.querySelector("#menubar .mb-item.icon:nth-child(4)"));
  if (!params.has("quiet")) { await wait(1400); bus.emit("notify", { app: "settings", title: "Welcome to Golden Gate", body: "Press ⌘Space for Spotlight, or open Control Center from the menu bar." }); }
})();
window.gg = { state, bus, launch, spotlight, cc };
