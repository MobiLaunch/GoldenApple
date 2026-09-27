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
    playing: false, magnify: prefs.get("magnify", true), dockSize: prefs.get("dockSize", 54),
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
