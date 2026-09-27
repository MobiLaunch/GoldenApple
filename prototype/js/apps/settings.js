// System Settings: grouped inset panes. Appearance, Wallpaper, Desktop & Dock,
// Wi-Fi, Bluetooth, Sound, Displays and About are live; the rest are stubs.
import { h, sym, state, animate } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp } from "../apps.js";

const ACCENTS = { blue: "#0a84ff", purple: "#bf5af2", pink: "#ff375f", red: "#ff453a", orange: "#ff9f0a", yellow: "#ffd60a", green: "#30d158", graphite: "#8e8e93" };
const PANES = [
  ["wifi", "Wi-Fi", "wifi", "#0a84ff"], ["bluetooth", "Bluetooth", "bluetooth", "#0a84ff"], ["network", "Network", "globe", "#0a84ff"], null,
  ["notifications", "Notifications", "bell", "#ff453a"], ["sound", "Sound", "speaker-wave", "#ff375f"], ["focus", "Focus", "moon", "#5e5ce6"], null,
  ["general", "General", "gear", "#8e8e93"], ["appearance", "Appearance", "contrast", "#1c1c1e"], ["accessibility", "Accessibility", "people", "#0a84ff"],
  ["controlcenter", "Control Center", "control-center", "#8e8e93"], ["dock", "Desktop & Dock", "rectangle-fill", "#1c1c1e"], ["displays", "Displays", "sun-max", "#0a84ff"],
  ["wallpaper", "Wallpaper", "wallpaper", "#32ade6"], null,
  ["privacy", "Privacy & Security", "lock", "#0a84ff"], ["keyboard", "Keyboard", "keyboard", "#8e8e93"],
];
export const WALLPAPERS = { dynamic: "assets/wallpapers/tide.svg", tide: "assets/wallpapers/tide.svg", dusk: "assets/wallpapers/dusk.svg" };

const group = (...rows) => h("div.form-group", rows);
const row = (label, control, sub) => h("div.form-row", h("div.grow", label, sub ? h("small", sub) : null), control ?? null);
const toggle = (key) => { const s = h("button.switch", { className: `switch ${state[key] ? "on" : ""}`, on: { click: () => { state[key] = !state[key]; s.classList.toggle("on", state[key]); } } }); return s; };
const range = (key, min = 0, max = 1, step = 0.01, onInput) => {
  const r = h("input.range", { type: "range", min, max, step, value: state[key] });
  const paint = () => r.style.setProperty("--p", `${((r.value - min) / (max - min)) * 100}%`);
  r.addEventListener("input", () => { state[key] = +r.value; paint(); onInput?.(); });
  paint();
  return r;
};
// Segmented control bound to a state key (values are the lower-cased labels).
const seg = (key, labels) => {
  const el = h("div.seg", labels.map((l) => h("button", { className: state[key] === l.toLowerCase() ? "on" : "", on: { click: (e) => { state[key] = l.toLowerCase(); el.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === e.currentTarget)); } } }, l)));
  return el;
};
const heroCard = (icon, color, title, text) => h("div.form-group", h("div.hero-card", h("span.sq", { style: { "--c": color } }, sym(icon)), h("b", title), h("small", text)));

const panes = {
  general: () => [heroCard("logo", "linear-gradient(135deg,#ffcc66,#f5a524)", "Golden Gate 27", "A Linux distribution with a Liquid Glass desktop."),
    group(row("Name", h("span", { style: { color: "var(--secondary-label)" } }, "golden-gate")), row("Kernel", h("span", { style: { color: "var(--secondary-label)" } }, "Linux 6.18 LTS")),
      row("Compositor", h("span", { style: { color: "var(--secondary-label)" } }, "Hyprland")), row("Shell", h("span", { style: { color: "var(--secondary-label)" } }, "Quickshell · Golden Gate 0.1")),
      row("Graphics", h("span", { style: { color: "var(--secondary-label)" } }, "Mesa 25.2 · Vulkan"))),
    group(row("Software Update", h("button.btn", "Check Now")), row("Storage", h("span", { style: { color: "var(--secondary-label)" } }, "62.2 GB available of 512 GB")))],
  appearance: () => {
    const modes = [["light", "Light", "#fff"], ["dark", "Dark", "#2a2a2e"], ["auto", "Auto", "linear-gradient(90deg,#fff 50%,#2a2a2e 50%)"]];
    const wrap = h("div.appearance", modes.map(([k, label, w]) => h("button", { className: state.theme === k || (k === "auto" && state.theme === "auto") ? "on" : "", on: { click: (e) => { state.theme = k; wrap.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === e.currentTarget)); } } },
      h("span.thumb", { style: { backgroundImage: `url(${WALLPAPERS[k === "dark" ? "dusk" : "tide"]})`, "--w": w } }), label)));
    const acc = h("div.accents", Object.entries(ACCENTS).map(([k, c]) => h("button", { title: k, className: state.accent === k ? "on" : "", style: { "--c": c }, on: { click: (e) => { state.accent = k; acc.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === e.currentTarget)); } } })));
    return [group(row("Appearance", wrap)), group(row("Accent colour", acc), row("Highlight colour", h("span", { style: { color: "var(--secondary-label)" } }, "Accent colour"))),
      group(row("Icon & widget style", seg("iconStyle", ["Default", "Dark", "Clear", "Tinted"])), row("Liquid Glass", seg("glass", ["Clear", "Tinted"]), "Tinted increases opacity for legibility.")),
      group(row("Show scroll bars", h("div.seg", ["Automatically", "When scrolling", "Always"].map((l, i) => h("button", { className: i === 0 ? "on" : "" }, l)))))];
  },
  wallpaper: () => {
    const walls = h("div.walls", Object.entries(WALLPAPERS).map(([k, src]) => h("div.wall-pick",
      h("button", { title: k, className: `${state.wallpaper === k ? "on" : ""} ${k === "dynamic" ? "dynamic" : ""}`, style: { backgroundImage: k === "dynamic" ? `url(${WALLPAPERS.tide}), url(${WALLPAPERS.dusk})` : `url(${src})` }, on: { click: (e) => { state.wallpaper = k; walls.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === e.currentTarget)); } } }),
      h("span", { dynamic: "Dynamic", tide: "Tide", dusk: "Dusk" }[k]))));
    return [h("div.form-group", walls), group(row("Show on all Spaces", toggle("wifi")))];
  },
  dock: () => [group(row("Size", range("dockSize", 36, 80, 1)), row("Magnification", toggle("magnify")), row("Position on screen", h("div.seg", ["Left", "Bottom", "Right"].map((l, i) => h("button", { className: i === 1 ? "on" : "" }, l)))),
    row("Minimise windows using", h("div.seg", ["Genie", "Scale"].map((l, i) => h("button", { className: i === 0 ? "on" : "" }, l))))),
    group(row("Stage Manager", toggle("stage"), "Arrange your recent windows in a single strip for reduced clutter."), row("Click wallpaper to reveal desktop", h("div.seg", ["Always", "Only in Stage Manager"].map((l, i) => h("button", { className: i === 1 ? "on" : "" }, l)))))],
  wifi: () => [group(row(h("b", "Wi-Fi"), toggle("wifi"))), h("h2", "Known Network"), group(row("Home", sym("wifi"), "Connected")), h("h2", "Other Networks"),
    group(...["Golden Gate Guest", "Presidio 5G", "Bay Bridge"].map((n) => row(n, h("span", { style: { display: "flex", gap: "8px", color: "var(--secondary-label)" } }, sym("lock"), sym("wifi")))))],
  bluetooth: () => [group(row(h("b", "Bluetooth"), toggle("bluetooth"), "This computer is discoverable as “golden-gate”.")), h("h2", "My Devices"),
    group(row("Studio Headphones", h("span", { style: { color: "var(--secondary-label)" } }, "Connected")), row("Magic Trackpad", h("span", { style: { color: "var(--secondary-label)" } }, "Connected")), row("Keyboard", h("span", { style: { color: "var(--secondary-label)" } }, "Not Connected")))],
  sound: () => [h("h2", "Output & Input"), group(row("Output volume", range("volume")), row("Alert sound", h("span", { style: { color: "var(--secondary-label)" } }, "Glass")), row("Play feedback when volume is changed", toggle("airdrop")))],
  notifications: () => [h("h2", "Notification Center"), group(row("Show previews", h("div.seg", ["Always", "When Unlocked", "Never"].map((l, i) => h("button", { className: i === 1 ? "on" : "" }, l)))), row("Allow notifications when the display is sleeping", toggle("airdrop"))),
    h("h2", "Application Notifications"), group(...["Calendar", "Mail", "Messages", "Music", "Software", "System Settings"].map((n) => row(n, h("span", { style: { color: "var(--secondary-label)" } }, "Banners, Sounds, Badges"))))],
  focus: () => [group(row(h("b", "Do Not Disturb"), toggle("focus"), "Silence notifications and calls.")), h("h2", "Focus modes"),
    group(...[["Personal", "person"], ["Work", "briefcase"], ["Sleep", "moon"]].map(([n, i]) => row(h("span", { style: { display: "flex", alignItems: "center", gap: "10px" } }, h("span.sq", { style: { "--c": "#5e5ce6" } }, sym(i)), n), sym("chevron-right")))),
    group(row("Share across devices", toggle("wifi")), row("Focus status", h("span", { style: { color: "var(--secondary-label)" } }, "On")))],
  controlcenter: () => [h("h2", "Control Center Modules"), group(...["Wi-Fi", "Bluetooth", "Nearby Share", "Focus", "Stage Manager", "Screen Mirroring", "Display", "Sound", "Now Playing"].map((n) => row(n, h("span", { style: { color: "var(--secondary-label)" } }, "Always Show in Control Center")))),
    h("h2", "Menu Bar Only"), group(row("Clock", h("button.btn", "Clock Options…")), row("Battery", toggle("wifi")), row("Spotlight", toggle("wifi")))],
  accessibility: () => [h("h2", "Vision"), group(row("Zoom", toggle("stage")), row("Display", h("span", { style: { color: "var(--secondary-label)" } }, "Reduce motion, contrast")), row("Reduce transparency", h("button.switch", { className: "switch", on: { click: (e) => { e.currentTarget.classList.toggle("on"); state.glass = e.currentTarget.classList.contains("on") ? "tinted" : "clear"; } } }), "Uses the Tinted Liquid Glass material everywhere.")),
    h("h2", "Motor"), group(row("Keyboard", h("span", { style: { color: "var(--secondary-label)" } }, "Sticky Keys off")), row("Pointer Control", h("span", { style: { color: "var(--secondary-label)" } }, "Default")))],
  privacy: () => [heroCard("lock", "#0a84ff", "Privacy & Security", "Apps request access to your location, camera, microphone and files through portals."),
    group(...[["Location Services", "location", "Off"], ["Camera", "video", "2 apps"], ["Microphone", "mic", "1 app"], ["Files & Folders", "folder", "4 apps"], ["Screen Recording", "screenshot", "None"]].map(([n, i, v]) => row(h("span", { style: { display: "flex", alignItems: "center", gap: "10px" } }, h("span.sq", { style: { "--c": "#0a84ff" } }, sym(i)), n), h("span", { style: { color: "var(--secondary-label)" } }, v)))),
    group(row("FileVault-style disk encryption (LUKS)", h("span", { style: { color: "var(--secondary-label)" } }, "On")), row("Firewall", h("span", { style: { color: "var(--secondary-label)" } }, "Active")))],
  keyboard: () => [group(row("Key repeat rate", range("volume")), row("Delay until repeat", range("brightness"))),
    h("h2", "Shortcuts"), group(...[["Spotlight", "⌘ Space"], ["App Switcher", "⌘ Tab"], ["Mission Control", "⌃ ↑"], ["Lock Screen", "⌃ ⌘ Q"], ["Screenshot of selection", "⇧ ⌘ 4"], ["Copy · Paste (keyd)", "⌘ C · ⌘ V"]].map(([n, k]) => row(n, h("span.kbd-chip", k)))),
    group(row("Use ⌘ for app shortcuts", toggle("wifi"), "keyd maps ⌘ + letter to Ctrl + letter, with Ctrl + Shift in terminals."))],
  network: () => [group(row(h("span", { style: { display: "flex", alignItems: "center", gap: "10px" } }, h("span.sq", { style: { "--c": "#0a84ff" } }, sym("wifi")), "Wi-Fi"), h("span", { style: { color: "var(--accent-green)" } }, "● Connected")),
    row(h("span", { style: { display: "flex", alignItems: "center", gap: "10px" } }, h("span.sq", { style: { "--c": "#8e8e93" } }, sym("globe")), "Ethernet"), h("span", { style: { color: "var(--secondary-label)" } }, "● Not Connected")),
    row(h("span", { style: { display: "flex", alignItems: "center", gap: "10px" } }, h("span.sq", { style: { "--c": "#30d158" } }, sym("shield")), "VPN"), h("span", { style: { color: "var(--secondary-label)" } }, "WireGuard · Off"))),
    group(row("Firewall", toggle("wifi")))],
  displays: () => [group(row("Brightness", range("brightness")), row("Automatically adjust brightness", toggle("wifi")), row("Night Shift", h("button.btn", "Schedule…")))],
};

function openSettings(_id, pane = "appearance") {
  let cur = PANES.find((p) => p?.[0] === pane) ? pane : "appearance";
  const sidebar = h("div");
  const content = h("div.pane");
  const title = h("div.title");
  const win = createWindow({ app: "settings", w: 780, h: 600, sidebar, sidebarWidth: 220, className: "settings", content, toolbar: [pill(tb("chevron-left"), div(), tb("chevron-right")), title] });
  const renderSide = () => sidebar.replaceChildren(
    h("label.side-search", sym("search"), h("input", { placeholder: "Search" })),
    h("div.account", h("span.avatar", "GU"), h("div", h("b", "Golden User"), h("small", "Account & Sync"))),
    ...PANES.map((p) => p ? h("div.side-row", { className: `side-row ${p[0] === cur ? "sel" : ""}`, on: { click: () => show(p[0]) } }, h("span.sq", { style: { "--c": p[3] } }, sym(p[2])), p[1]) : h("div.gap")));
  function show(k) {
    cur = k; renderSide();
    const p = PANES.find((x) => x?.[0] === k);
    title.textContent = p[1];
    content.replaceChildren(...(panes[k]?.() ?? [heroCard(p[2], p[3], p[1], "This pane is part of the roadmap for the native settings app."), group(row("Coming soon", null))]));
    win.content.scrollTop = 0;
    animate(content, [{ opacity: 0, transform: "translateY(4px)" }, { opacity: 1, transform: "none" }], "snappy");
  }
  show(cur);
  win.showPane = show;
  return win;
}

registerApp("settings", openSettings);
