import { ICONS } from "../assets/icons.js";

// Tiny hyperscript: h("div.cls#id", {attrs, on:{click}}, ...children)
export function h(tag, props = {}, ...kids) {
  if (typeof props === "string" || props instanceof Node || Array.isArray(props)) { kids.unshift(props); props = {}; }
  const [, name = "div", rest = ""] = tag.match(/^([a-z0-9-]*)(.*)$/i);
  const el = document.createElement(name || "div");
  for (const m of rest.matchAll(/([.#])([\w-]+)/g)) m[1] === "." ? el.classList.add(m[2]) : (el.id = m[2]);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === "on") for (const [ev, fn] of Object.entries(v)) el.addEventListener(ev, fn);
    else if (k === "style" && typeof v === "object") for (const [p, val] of Object.entries(v)) p.startsWith("--") ? el.style.setProperty(p, val) : (el.style[p] = val);
    else if (k === "html") el.innerHTML = v;
    else if (k in el && !k.startsWith("data") && k !== "list") el[k] = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat(Infinity)) if (kid != null && kid !== false) el.append(kid instanceof Node ? kid : document.createTextNode(kid));
  return el;
}

// Symbol from the sprite: sym("wifi")
export function sym(name, cls = "") {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("class", `sym ${cls}`.trim());
  const use = document.createElementNS(ns, "use");
  use.setAttribute("href", `#sym-${name}`);
  svg.append(use);
  return svg;
}

export const isDark = () => document.documentElement.dataset.theme === "dark";
export const appIconURL = (key) => (ICONS.apps[key] ? ICONS.apps[key][isDark() ? "dark" : "light"] : ICONS.places[key]);
export function appIcon(key, cls = "") {
  const img = h("img", { src: appIconURL(key), alt: "", draggable: false, className: cls });
  img.dataset.icon = key;
  return img;
}
// Re-point every rendered app icon when the appearance changes.
export function refreshIcons(root = document) {
  root.querySelectorAll("img[data-icon]").forEach((img) => (img.src = appIconURL(img.dataset.icon)));
}

// ------------------------------------------------------------------ motion
const springCache = {};
export const spring = (name) => {
  if (springCache[name]) return springCache[name];
  const css = getComputedStyle(document.documentElement);
  const s = {
    easing: css.getPropertyValue(`--spring-${name}`).trim() || "ease-out",
    duration: parseInt(css.getPropertyValue(`--spring-${name}-duration`)) || 400,
  };
  if (css.getPropertyValue(`--spring-${name}`)) springCache[name] = s;
  return s;
};
export const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Web Animations with a named spring; resolves when finished.
export function animate(el, keyframes, name = "snappy", opts = {}) {
  const s = spring(name);
  const a = el.animate(keyframes, { duration: reducedMotion ? 1 : s.duration, easing: s.easing, fill: "both", ...opts });
  return a.finished.then(() => { if (!opts.keep) { try { a.commitStyles(); } catch {} a.cancel(); } return a; }).catch(() => a);
}

export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// Persisted preferences (per-viewer conveniences only; storage may be unavailable).
export const prefs = {
  get(k, d) { try { const v = localStorage.getItem("gg." + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem("gg." + k, JSON.stringify(v)); } catch {} },
};

// Minimal event bus + reactive state.
const listeners = new Map();
export const bus = {
  on(ev, fn) { (listeners.get(ev) ?? listeners.set(ev, new Set()).get(ev)).add(fn); return () => listeners.get(ev).delete(fn); },
  emit(ev, ...args) { listeners.get(ev)?.forEach((fn) => fn(...args)); },
};
export const state = new Proxy(
  {
    theme: prefs.get("theme", "light"), accent: prefs.get("accent", "blue"), wallpaper: prefs.get("wallpaper", "tide"),
    wifi: true, bluetooth: true, airdrop: true, focus: false, stage: false, volume: 0.62, brightness: 0.58,
    playing: false, nowPlaying: { title: "Fog Horns", artist: "The Presidio Quartet", album: "Fog Horns", art: null, progress: 0.3 }, magnify: prefs.get("magnify", true), dockSize: prefs.get("dockSize", 54),
  },
  {
    set(t, k, v) {
      if (t[k] === v) return true;
      t[k] = v;
      if (["theme", "accent", "wallpaper", "magnify", "dockSize"].includes(k)) prefs.set(k, v);
      bus.emit("state", { key: k, value: v });
      bus.emit(`state:${k}`, v);
      return true;
    },
  }
);

export function fmtClock(d = new Date()) {
  const day = d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" }).replace(",", "");
  const time = d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  return `${day}  ${time}`;
}

// ------------------------------------------------------------------ shared visuals
const AVATAR_GRADIENTS = [["#ffb347", "#ff5e7e"], ["#5ac8fa", "#007aff"], ["#a8e063", "#34c759"], ["#bf5af2", "#5e5ce6"], ["#ff9f0a", "#ff453a"], ["#64d2ff", "#5e5ce6"], ["#ffd60a", "#ff9f0a"], ["#8e8e93", "#48484a"]];
const hash = (s) => [...String(s)].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);
// Contact avatar: initials on a gradient chosen from the name.
export function avatar(name, size = 36) {
  const [a, b] = AVATAR_GRADIENTS[hash(name) % AVATAR_GRADIENTS.length];
  const initials = name.split(/\s+/).map((w) => w[0]).join("").slice(0, 2).toUpperCase();
  return h("span.avatar", { style: { width: `${size}px`, height: `${size}px`, fontSize: `${size * 0.4}px`, background: `linear-gradient(180deg, ${a}, ${b})` } }, initials);
}

// Deterministic abstract artwork (album covers, article thumbnails, hero cards).
export function genArt(seed, { w = 300, h: ht = 300 } = {}) {
  let s = hash(seed) || 1;
  const r = () => ((s = (s * 16807) % 2147483647) / 2147483647);
  const pal = [["#ff5f6d", "#ffc371"], ["#2193b0", "#6dd5ed"], ["#8e2de2", "#4a00e0"], ["#f7971e", "#ffd200"], ["#11998e", "#38ef7d"], ["#fc466b", "#3f5efb"], ["#0f2027", "#2c5364"], ["#ee9ca7", "#ffdde1"], ["#1d2b64", "#f8cdda"], ["#ff512f", "#dd2476"]][Math.floor(r() * 10)];
  const kind = Math.floor(r() * 4);
  const shapes = [
    () => `<circle cx="${w * (0.3 + r() * 0.4)}" cy="${ht * (0.3 + r() * 0.4)}" r="${w * (0.22 + r() * 0.12)}" fill="#fff" opacity=".85"/><circle cx="${w * r()}" cy="${ht * r()}" r="${w * 0.35}" fill="${pal[0]}" opacity=".5" style="mix-blend-mode:multiply"/>`,
    () => Array.from({ length: 7 }, (_, i) => `<path d="M0 ${ht * (0.2 + i * 0.1)} Q ${w / 2} ${ht * (r() * 0.9)} ${w} ${ht * (0.2 + i * 0.1)}" stroke="#fff" stroke-opacity="${0.25 + i * 0.08}" stroke-width="${3 + r() * 5}" fill="none"/>`).join(""),
    () => Array.from({ length: 16 }, (_, i) => `<rect x="${(i % 4) * w / 4 + 8}" y="${Math.floor(i / 4) * ht / 4 + 8}" width="${w / 4 - 16}" height="${ht / 4 - 16}" rx="${r() > 0.5 ? w / 8 : 6}" fill="#fff" opacity="${(r() * 0.7).toFixed(2)}"/>`).join(""),
    () => `<path d="M${w * 0.1} ${ht * 0.9} C ${w * 0.2} ${ht * r()}, ${w * 0.8} ${ht * r()}, ${w * 0.9} ${ht * 0.1}" stroke="#fff" stroke-width="${w * 0.12}" stroke-linecap="round" fill="none" opacity=".8"/><circle cx="${w * 0.75}" cy="${ht * 0.3}" r="${w * 0.08}" fill="#fff"/>`,
  ];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${ht}"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${pal[0]}"/><stop offset="1" stop-color="${pal[1]}"/></linearGradient></defs><rect width="${w}" height="${ht}" fill="url(#g)"/>${shapes[kind]()}</svg>`;
  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg);
}

// An app icon that isn't one of ours: gradient squircle with a white symbol.
export function genIcon(symbol, from, to, size = 64) {
  return h("span.gen-icon", { style: { width: `${size}px`, height: `${size}px`, fontSize: `${size * 0.5}px`, background: `linear-gradient(180deg, ${from}, ${to})` } }, sym(symbol));
}
