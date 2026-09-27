#!/usr/bin/env node
// Writes the freedesktop icon theme (icons/GoldenGate) and the prototype bundle
// (prototype/assets/icons.js) from icons/source.mjs.
import { writeFileSync, mkdirSync, rmSync, symlinkSync, existsSync, readFileSync, copyFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { symbols as baseSymbols, apps as baseApps, places as basePlaces } from "./source.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "GoldenGate");

// ---------------------------------------------------------------- your own icons
// Anything in icons/custom/ replaces the built-in artwork with the same key:
//   custom/apps/<key>.svg|png        app icon (e.g. files.svg, terminal.png)
//   custom/apps/<key>-dark.svg|png   optional dark-appearance version
//   custom/places/<key>.svg|png      folder, document, trash, ...
//   custom/symbols/<key>.svg         small monochrome glyph; use currentColor
// Run `node icons/build.mjs --list` to print every key.
const custom = join(here, "custom");
function findCustom(kind, key) {
  for (const ext of ["svg", "png"]) {
    const f = join(custom, kind, `${key}.${ext}`);
    if (existsSync(f)) return { path: f, ext };
  }
  return null;
}
const cleanSvg = (txt) => txt.replace(/<\?xml[^>]*>\s*/, "").replace(/<!DOCTYPE[^>]*>\s*/i, "").trim();
const customUsed = [];
function override(kind, table) {
  const outTable = {}, pngs = {};
  for (const key of Object.keys(table)) {
    const c = findCustom(kind, key);
    if (!c) { outTable[key] = table[key]; continue; }
    customUsed.push(`${kind}/${key}.${c.ext}`);
    if (c.ext === "svg") outTable[key] = cleanSvg(readFileSync(c.path, "utf8"));
    else { outTable[key] = null; pngs[key] = c.path; }
  }
  return { table: outTable, pngs };
}
const A = override("apps", baseApps), P = override("places", basePlaces), Y = override("symbols", baseSymbols);
const apps = A.table, places = P.table, symbols = Y.table;
if (process.argv.includes("--list")) {
  console.log("apps:    " + Object.keys(baseApps).join(", "));
  console.log("places:  " + Object.keys(basePlaces).join(", "));
  console.log("symbols: " + Object.keys(baseSymbols).join(", "));
  process.exit(0);
}
const darkBg = `<linearGradient id="dark-bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3a3f"/><stop offset="1" stop-color="#141416"/></linearGradient>`;

// Dark icon appearance: graphite body, white glyphs take the icon's accent colour.
function darkVariant(svg) {
  const m = svg.match(/data-accent="([^"]+)"/);
  if (!m) return svg;
  const accent = m[1];
  return svg
    .replace("<defs>", `<defs>${darkBg}`)
    .replace(/class="bg" fill="[^"]*"/g, 'class="bg" fill="url(#dark-bg)"')
    .replace(/class="tint" fill="[^"]*"/g, `class="tint" fill="${accent}"`)
    .replace(/class="tint-stroke"([^>]*?)stroke="#fff"/g, `class="tint-stroke"$1stroke="${accent}"`)
    .replace(/class="tint-text"([^>]*?)fill="[^"]*"/g, `class="tint-text"$1fill="#f2f2f7"`);
}

// freedesktop names each artwork is published under (first entry is canonical).
const appNames = {
  files: ["system-file-manager", "org.gnome.Nautilus", "org.kde.dolphin", "thunar"],
  browser: ["web-browser", "firefox", "org.mozilla.firefox", "chromium", "google-chrome"],
  mail: ["internet-mail", "thunderbird", "org.mozilla.Thunderbird", "org.gnome.Evolution"],
  messages: ["internet-chat", "org.gnome.Fractal", "signal-desktop"],
  music: ["multimedia-audio-player", "org.gnome.Music", "rhythmbox", "elisa"],
  photos: ["multimedia-photo-viewer", "org.gnome.Loupe", "shotwell", "gthumb"],
  settings: ["preferences-system", "org.gnome.Settings", "systemsettings"],
  terminal: ["utilities-terminal", "org.gnome.Console", "com.mitchellh.ghostty", "kitty", "foot", "Alacritty"],
  notes: ["accessories-text-editor", "org.gnome.TextEditor", "gnome-notes"],
  calendar: ["office-calendar", "org.gnome.Calendar"],
  calculator: ["accessories-calculator", "org.gnome.Calculator"],
  maps: ["maps", "org.gnome.Maps"],
  store: ["system-software-install", "org.gnome.Software", "org.kde.discover"],
  launcher: ["view-app-grid", "start-here"],
  weather: ["weather", "org.gnome.Weather"],
};
const placeNames = { trash: ["user-trash"], "trash-full": ["user-trash-full"], folder: ["folder"], document: ["text-x-generic"], audio: ["audio-x-generic"], image: ["image-x-generic"], disk: ["drive-harddisk"] };
const symbolNames = {
  wifi: "network-wireless-symbolic", bluetooth: "bluetooth-active-symbolic", moon: "weather-clear-night-symbolic",
  search: "system-search-symbolic", "speaker-wave": "audio-volume-high-symbolic", speaker: "audio-volume-low-symbolic",
  sun: "display-brightness-symbolic", play: "media-playback-start-symbolic", pause: "media-playback-pause-symbolic",
  backward: "media-skip-backward-symbolic", forward: "media-skip-forward-symbolic", "chevron-left": "go-previous-symbolic",
  "chevron-right": "go-next-symbolic", "chevron-down": "pan-down-symbolic", grid: "view-grid-symbolic", list: "view-list-symbolic",
  share: "send-to-symbolic", ellipsis: "view-more-symbolic", clock: "document-open-recent-symbolic", house: "user-home-symbolic",
  doc: "folder-documents-symbolic", download: "folder-download-symbolic", photo: "folder-pictures-symbolic",
  music: "folder-music-symbolic", film: "folder-videos-symbolic", trash: "user-trash-symbolic", plus: "list-add-symbolic",
  minus: "list-remove-symbolic", sidebar: "sidebar-show-symbolic", screenshot: "applets-screenshooter-symbolic",
  gear: "emblem-system-symbolic", power: "system-shutdown-symbolic", lock: "system-lock-screen-symbolic",
  bell: "preferences-system-notifications-symbolic", xmark: "window-close-symbolic", checkmark: "object-select-symbolic",
  folder: "folder-symbolic", drive: "drive-harddisk-symbolic", cloud: "folder-remote-symbolic", headphones: "audio-headphones-symbolic",
  logo: "start-here-symbolic", people: "system-users-symbolic", globe: "web-browser-symbolic",
};

rmSync(root, { recursive: true, force: true });
for (const d of ["scalable/apps", "scalable/places", "scalable/mimetypes", "scalable/devices", "symbolic/actions"]) mkdirSync(join(root, d), { recursive: true });

const link = (target, path) => { try { symlinkSync(target, path); } catch {} };
const hasPng = Object.keys(A.pngs).length + Object.keys(P.pngs).length > 0;
if (hasPng) for (const d of ["512x512/apps", "512x512/places", "512x512/mimetypes", "512x512/devices"]) mkdirSync(join(root, d), { recursive: true });
for (const [key, svg] of Object.entries(apps)) {
  const [canon, ...aliases] = appNames[key];
  const ext = svg == null ? "png" : "svg";
  const dir = ext === "png" ? "512x512/apps" : "scalable/apps";
  if (ext === "png") copyFileSync(A.pngs[key], join(root, dir, `${canon}.png`));
  else writeFileSync(join(root, dir, `${canon}.svg`), svg);
  aliases.forEach((a) => link(`${canon}.${ext}`, join(root, dir, `${a}.${ext}`)));
}
const placeDir = { trash: "places", "trash-full": "places", folder: "places", document: "mimetypes", audio: "mimetypes", image: "mimetypes", disk: "devices" };
for (const [key, svg] of Object.entries(places)) {
  if (svg == null) copyFileSync(P.pngs[key], join(root, "512x512", placeDir[key], `${placeNames[key][0]}.png`));
  else writeFileSync(join(root, "scalable", placeDir[key], `${placeNames[key][0]}.svg`), svg);
}
for (const [key, svg] of Object.entries(symbols)) {
  const name = symbolNames[key] ?? `goldengate-${key}-symbolic`;
  // GTK recolours symbolic icons that use #bebebe / currentColor-free fills; keep currentColor-compatible stroke.
  writeFileSync(join(root, "symbolic/actions", `${name}.svg`), svg.replace(/currentColor/g, "#2e3436"));
}
writeFileSync(join(root, "index.theme"), `[Icon Theme]
Name=Golden Gate
Comment=Original icon theme for the Golden Gate desktop
Inherits=Adwaita,hicolor
Directories=scalable/apps,scalable/places,scalable/mimetypes,scalable/devices,symbolic/actions${hasPng ? ",512x512/apps,512x512/places,512x512/mimetypes,512x512/devices" : ""}

[scalable/apps]
Size=128
MinSize=16
MaxSize=512
Type=Scalable
Context=Applications

[scalable/places]
Size=128
MinSize=16
MaxSize=512
Type=Scalable
Context=Places

[scalable/mimetypes]
Size=128
MinSize=16
MaxSize=512
Type=Scalable
Context=MimeTypes

[scalable/devices]
Size=128
MinSize=16
MaxSize=512
Type=Scalable
Context=Devices

[symbolic/actions]
Size=16
MinSize=8
MaxSize=512
Type=Scalable
Context=Actions
${hasPng ? ["apps", "places", "mimetypes", "devices"].map((c) => `\n[512x512/${c}]\nSize=512\nType=Threshold\nContext=${c[0].toUpperCase() + c.slice(1)}\n`).join("") : ""}`);

// ---------------------------------------------------------------- Quickshell assets
// White symbols for the shell (tinted at runtime with MultiEffect when needed).
const shellSyms = join(here, "..", "shell", "assets", "symbols");
rmSync(shellSyms, { recursive: true, force: true });
mkdirSync(shellSyms, { recursive: true });
for (const [key, svg] of Object.entries(symbols)) {
  const sized = svg.replace(/^<svg/, '<svg width="48" height="48"').replace(/\s(width|height)="\d+"(?=[^>]*width="48")/g, "");
  // Pre-tinted variants: the shell never needs a shader just to colour a glyph.
  for (const [tone, color] of Object.entries({ "": "#ffffff", "@accent": "#0a84ff", "@dark": "#1d1d1f", "@gray": "#8e8e93" }))
    writeFileSync(join(shellSyms, `${key}${tone}.svg`), sized.replace(/currentColor/g, color));
}

// ---------------------------------------------------------------- prototype bundle
const uri = (svg) => "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg.replace(/\s*\n\s*/g, " "));
const pngUri = (f) => "data:image/png;base64," + readFileSync(f).toString("base64");
// Symbols become <symbol> elements; keep viewBox and drawing attributes, drop sizing.
const toSymbol = (k, svg) => svg.replace(/^<svg([^>]*)>/, (_, attrs) => {
  const vb = attrs.match(/viewBox="([^"]+)"/)?.[1] ?? "0 0 24 24";
  const keep = attrs.replace(/\s(xmlns(:\w+)?|viewBox|width|height|class|id|version)="[^"]*"/g, "");
  return `<symbol id="sym-${k}" viewBox="${vb}"${keep}>`;
}).replace(/<\/svg>\s*$/, "</symbol>");
const sprite = Object.entries(symbols).map(([k, svg]) => toSymbol(k, svg)).join("");
function appEntry(k, v) {
  const light = v == null ? pngUri(A.pngs[k]) : uri(v);
  const dark = findCustom("apps", `${k}-dark`);
  if (dark) { customUsed.push(`apps/${k}-dark.${dark.ext}`); return { light, dark: dark.ext === "png" ? pngUri(dark.path) : uri(cleanSvg(readFileSync(dark.path, "utf8"))) }; }
  return { light, dark: v == null ? light : uri(darkVariant(v)) };
}
const bundle = {
  apps: Object.fromEntries(Object.entries(apps).map(([k, v]) => [k, appEntry(k, v)])),
  places: Object.fromEntries(Object.entries(places).map(([k, v]) => [k, v == null ? pngUri(P.pngs[k]) : uri(v)])),
};
const protoAssets = join(here, "..", "prototype", "assets");
mkdirSync(protoAssets, { recursive: true });
writeFileSync(join(protoAssets, "icons.js"),
  `// Generated by icons/build.mjs. Do not edit.
export const ICONS = ${JSON.stringify(bundle)};
export const SPRITE = ${JSON.stringify(`<svg xmlns="http://www.w3.org/2000/svg" style="display:none">${sprite}</svg>`)};
`);
if (customUsed.length) console.log(`custom icons: ${customUsed.join(", ")}`);
console.log(`icons: ${Object.keys(apps).length} apps, ${Object.keys(places).length} places, ${Object.keys(symbols).length} symbols`);
