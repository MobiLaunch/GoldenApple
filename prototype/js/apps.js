// App registry, launching and per-app menu-bar menus.
import { h, appIcon, animate, bus, state } from "./util.js";
import { createWindow, windowsOf, activeWindow } from "./wm.js";

export const APPS = {
  files:      { name: "Files",           linux: "Nautilus (themed) → native Files app on the roadmap" },
  browser:    { name: "Web",             linux: "Firefox with the Golden Gate userChrome" },
  mail:       { name: "Mail",            linux: "Thunderbird / Geary" },
  messages:   { name: "Messages",        linux: "Matrix client (Fractal)" },
  music:      { name: "Music",           linux: "Amberol / Elisa" },
  photos:     { name: "Photos",          linux: "Loupe + Shotwell library" },
  notes:      { name: "Notes",           linux: "Native GTK4 app" },
  calendar:   { name: "Calendar",        linux: "GNOME Calendar" },
  maps:       { name: "Maps",            linux: "GNOME Maps" },
  weather:    { name: "Weather",         linux: "GNOME Weather" },
  store:      { name: "Software",        linux: "GNOME Software + Flathub" },
  settings:   { name: "System Settings", linux: "Native settings app (shell/settings)" },
  terminal:   { name: "Terminal",        linux: "Ghostty with the Golden Gate theme" },
  calculator: { name: "Calculator",      linux: "GNOME Calculator" },
  launcher:   { name: "Apps",            linux: "Shell launcher (Spotlight in Apps mode)" },
};

const openers = {};
export const registerApp = (id, open, menus) => { openers[id] = open; if (menus) APPS[id].menus = menus; };

export async function launch(id, arg) {
  const wins = windowsOf(id);
  if (wins.length && arg != null && wins[0].showPane) {
    wins[0].minimized ? await wins[0].restore() : wins[0].focus();
    return wins[0].showPane(arg);
  }
  if (wins.length && arg == null) {
    const front = wins.find((w) => !w.minimized);
    if (front) return front.focus();
    return wins[0].restore();
  }
  const tile = document.querySelector(`.dock-item[data-app="${id}"] img`);
  if (tile && !wins.length && id !== "launcher") {
    animate(tile, [
      { transform: "translateY(0)" }, { transform: "translateY(-22px)", offset: 0.3 },
      { transform: "translateY(0)", offset: 0.6 }, { transform: "translateY(-8px)", offset: 0.8 }, { transform: "translateY(0)" },
    ], "smooth", { duration: 640, easing: "ease-in-out" });
  }
  (openers[id] ?? openGeneric)(id, arg);
}

function openGeneric(id) {
  const a = APPS[id];
  createWindow({
    app: id, w: 520, h: 360, noToolbar: true,
    content: h("div", { style: { height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "10px", textAlign: "center", padding: "30px" }, "data-drag": "" },
      appIcon(id, "big-icon"),
      h("div", { style: { fontSize: "22px", fontWeight: 700, letterSpacing: "-.02em" } }, a.name),
      h("div", { style: { color: "var(--secondary-label)", maxWidth: "340px", lineHeight: 1.45 } },
        "This app is a placeholder in the reference shell. On the Linux build it maps to ", h("b", a.linux), "."),
    ),
  }).el.querySelector(".big-icon").style.cssText = "width:96px;height:96px;filter:drop-shadow(0 6px 12px rgba(0,0,0,.2))";
}

// ------------------------------------------------------------------ menu bar menus
const K = "⌘";
export function menusFor(id) {
  const a = APPS[id] ?? APPS.files;
  const w = () => activeWindow();
  const std = {
    [a.name]: [
      { label: `About ${a.name}`, action: () => launch("settings", "general") }, "-",
      { label: "Settings…", kbd: `${K},`, action: () => launch("settings") }, "-",
      { label: "Services", submenu: [{ label: "No Services Apply", disabled: true }] }, "-",
      { label: `Hide ${a.name}`, kbd: `${K}H` }, { label: "Hide Others", kbd: `⌥${K}H` }, "-",
      { label: `Quit ${a.name}`, kbd: `${K}Q`, action: () => windowsOf(id).forEach((x) => x.close()) },
    ],
    File: [
      { label: "New Window", kbd: `${K}N`, action: () => launch(id, "new") },
      { label: "New Folder", kbd: `⇧${K}N`, disabled: id !== "files" },
      { label: "Open…", kbd: `${K}O` }, "-",
      { label: "Close Window", kbd: `${K}W`, action: () => w()?.close() },
    ],
    Edit: [
      { label: "Undo", kbd: `${K}Z`, disabled: true }, { label: "Redo", kbd: `⇧${K}Z`, disabled: true }, "-",
      { label: "Cut", kbd: `${K}X` }, { label: "Copy", kbd: `${K}C` }, { label: "Paste", kbd: `${K}V` }, { label: "Select All", kbd: `${K}A` }, "-",
      { label: "Writing Tools", icon: "sparkles", submenu: [{ label: "Proofread" }, { label: "Rewrite" }, { label: "Summarize" }] },
      { label: "Emoji & Symbols", kbd: "fn E" },
    ],
    View: [
      { label: "as Icons", kbd: `${K}1` }, { label: "as List", kbd: `${K}2` }, { label: "as Columns", kbd: `${K}3` }, { label: "as Gallery", kbd: `${K}4` }, "-",
      { label: "Show Sidebar", kbd: `⌃${K}S` }, { label: "Enter Full Screen", kbd: "fn F", action: () => w()?.zoom() },
    ],
    Window: [
      { label: "Minimize", kbd: `${K}M`, action: () => w()?.minimize() }, { label: "Zoom", action: () => w()?.zoom() },
      { label: "Tile Window to Left of Screen", action: () => tile(w(), "left") }, { label: "Tile Window to Right of Screen", action: () => tile(w(), "right") }, "-",
      { label: "Bring All to Front" },
    ],
    Help: [{ label: `${a.name} Help` }, { label: "Keyboard Shortcuts", action: () => bus.emit("notify", { app: "settings", title: "Keyboard Shortcuts", body: "⌘Space Spotlight · ⌘Tab switch apps · ⌘W close · ⌘M minimize · ⌘, Settings" }) }],
  };
  const { Window, Help, ...rest } = std;
  return { ...rest, ...(a.menus ?? {}), Window, Help };
}

function tile(w, side) {
  if (!w) return;
  const half = innerWidth / 2;
  const to = { left: side === "left" ? "6px" : `${half + 3}px`, top: "36px", width: `${half - 9}px`, height: `${innerHeight - 130}px` };
  const from = { left: w.el.style.left, top: w.el.style.top, width: w.el.style.width, height: w.el.style.height };
  Object.assign(w.el.style, to);
  animate(w.el, [from, to], "window");
}

bus.on("launch", ({ id, arg }) => launch(id, arg));
export { state };
