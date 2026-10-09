// Original icon artwork for the CitronOS icon theme.
// Symbols: 24×24, drawn with currentColor (stroke 1.75, round caps) in the spirit of a
// system symbol font. App icons: 100×100 on a superellipse ("squircle") body.
//
// App icon conventions (used by build.mjs to derive the dark variant):
//   class="bg"   the body fill; swapped for a graphite gradient in dark mode
//   class="tint" white glyph parts; take the icon's accent colour in dark mode

// ------------------------------------------------------------------ geometry
export function squircle(size = 100, n = 5, steps = 160) {
  const r = size / 2, pts = [];
  for (let i = 0; i < steps; i++) {
    const a = (i / steps) * Math.PI * 2;
    const c = Math.cos(a), s = Math.sin(a);
    pts.push([r + r * Math.sign(c) * Math.abs(c) ** (2 / n), r + r * Math.sign(s) * Math.abs(s) ** (2 / n)]);
  }
  return "M" + pts.map((p) => p.map((v) => v.toFixed(2)).join(" ")).join("L") + "Z";
}

function gear(cx, cy, rOuter, rInner, teeth, toothFrac = 0.5) {
  const pts = [], step = (Math.PI * 2) / teeth;
  for (let i = 0; i < teeth; i++) {
    const a = i * step, w = step * toothFrac * 0.5, bevel = step * 0.08;
    pts.push([a - w - bevel, rInner], [a - w, rOuter], [a + w, rOuter], [a + w + bevel, rInner]);
  }
  return "M" + pts.map(([a, r]) => `${(cx + r * Math.cos(a)).toFixed(2)} ${(cy + r * Math.sin(a)).toFixed(2)}`).join("L") + "Z";
}

// ------------------------------------------------------------------ symbols
// Extra attributes override the defaults (a duplicated attribute is invalid XML,
// which browsers tolerate inline but Qt, GTK and librsvg reject).
function S(body, extra = "") {
  const attrs = { xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "1.75", "stroke-linecap": "round", "stroke-linejoin": "round" };
  for (const [, k, v] of extra.matchAll(/([\w:-]+)="([^"]*)"/g)) attrs[k] = v;
  return `<svg ${Object.entries(attrs).map(([k, v]) => `${k}="${v}"`).join(" ")}>${body}</svg>`;
}
const dot = (x, y, r = 1.3) => `<circle cx="${x}" cy="${y}" r="${r}" fill="currentColor" stroke="none"/>`;

// A tile glyph: the screen's outline, with (x, y, w, h) of it filled, inset
// from the outline so the two read apart.
function tile(x, y, w, h) {
  const g = 1.6, r = (v, a, b) => Math.max(a, Math.min(b, v));
  const x0 = r(x + g, 3 + g, 21 - g), y0 = r(y + g, 4.5 + g, 19.5 - g);
  const x1 = r(x + w - g, 3 + g, 21 - g), y1 = r(y + h - g, 4.5 + g, 19.5 - g);
  return S(`<rect x="3" y="4.5" width="18" height="15" rx="2.8"/><rect x="${x0}" y="${y0}" width="${+(x1 - x0).toFixed(2)}" height="${+(y1 - y0).toFixed(2)}" rx="1.2" fill="currentColor" stroke="none"/>`);
}

export const symbols = {
  // A lemon with its leaf, solid: the CitronOS mark used where a platform logo goes.
  logo: S(`<path fill="currentColor" stroke="none" d="M2.97 20.14C2.79 19.84 2.77 19.44 3.06 18.96C3.50 18.34 3.91 17.67 3.99 16.67C3.60 13.97 5.08 11.63 7.97 9.83C10.85 8.03 13.61 7.72 15.86 9.26C16.80 9.62 17.58 9.54 18.33 9.43C18.89 9.37 19.24 9.56 19.43 9.86C19.61 10.16 19.63 10.56 19.34 11.04C18.90 11.66 18.49 12.33 18.41 13.33C18.80 16.03 17.32 18.37 14.43 20.17C11.55 21.97 8.79 22.28 6.54 20.74C5.60 20.38 4.82 20.46 4.07 20.57C3.51 20.63 3.16 20.44 2.97 20.14Z"/><path fill="currentColor" stroke="none" d="M18.6 8.1C18.4 4.6 16.1 2.4 12.6 2C12.8 5.6 15.1 7.8 18.6 8.1Z"/>`),
  wifi: S(`<path d="M3.2 9.4a12.6 12.6 0 0 1 17.6 0"/><path d="M6.3 12.6a8.2 8.2 0 0 1 11.4 0"/><path d="M9.4 15.7a3.8 3.8 0 0 1 5.2 0"/>${dot(12, 18.8, 1.5)}`, ' stroke-width="2.1"'),
  bluetooth: S(`<path d="M6.5 7.5l10.5 9-5 4.5V3l5 4.5-10.5 9"/>`, ' stroke-width="1.9"'),
  broadcast: S(`${dot(12, 12.5, 2)}<path d="M8.6 16a5 5 0 1 1 6.8 0"/><path d="M5.8 19a9 9 0 1 1 12.4 0"/>`, ' stroke-width="1.9"'),
  moon: S(`<path d="M19.5 14.6A8 8 0 0 1 9.4 4.5a8 8 0 1 0 10.1 10.1z" fill="currentColor"/>`),
  stage: S(`<rect x="9" y="5" width="12" height="14" rx="2.5"/><path d="M4 6.5v1.5M4 11.2v1.6M4 16v1.5"/>`, ' stroke-width="2.1"'),
  mirror: S(`<rect x="3" y="4" width="14" height="11" rx="2.2"/><path d="M7.5 19H19a2 2 0 0 0 2-2V8.5"/>`, ' stroke-width="1.9"'),
  tv: S(`<rect x="2.5" y="4" width="19" height="12.5" rx="2.2"/><path d="M8 20.5h8M12 16.5v4"/>`),
  key: S(`<circle cx="8" cy="12" r="4.5"/><path d="M12.5 12h9M18.5 12v3.5M15.5 12v2.5"/>`),
  "eye-slash": S(`<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/><path d="M4 4l16 16"/>`),
  "arrow-uturn-left": S(`<path d="M9 14L4.5 9.5 9 5"/><path d="M4.5 9.5H15a4.5 4.5 0 0 1 0 9h-3"/>`),
  sun: S(`<circle cx="12" cy="12" r="3.6"/><path d="M12 3.5v1.5M12 19v1.5M3.5 12H5M19 12h1.5M6 6l1 1M17 17l1 1M6 18l1-1M17 7l1-1"/>`),
  "sun-max": S(`<circle cx="12" cy="12" r="4" fill="currentColor"/><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M5.3 18.7l1.6-1.6M17.1 6.9l1.6-1.6"/>`),
  speaker: S(`<path d="M4 9.5h3l5-4v13l-5-4H4z" fill="currentColor"/>`),
  "speaker-wave": S(`<path d="M3 9.5h3l5-4v13l-5-4H3z" fill="currentColor"/><path d="M14.5 9a4.2 4.2 0 0 1 0 6M17.2 6.5a8 8 0 0 1 0 11M19.9 4a11.8 11.8 0 0 1 0 16"/>`),
  headphones: S(`<path d="M4 16v-3a8 8 0 0 1 16 0v3"/><rect x="3.5" y="14" width="4" height="6.5" rx="1.6" fill="currentColor"/><rect x="16.5" y="14" width="4" height="6.5" rx="1.6" fill="currentColor"/>`),
  search: S(`<circle cx="10.5" cy="10.5" r="6.2"/><path d="M15.2 15.2L20 20"/>`, ' stroke-width="2"'),
  "control-center": S(`<rect x="3" y="4.5" width="18" height="6" rx="3"/>${dot(17.5, 7.5, 1.7)}<rect x="3" y="13.5" width="18" height="6" rx="3"/>${dot(6.5, 16.5, 1.7)}`, ' stroke-width="1.6"'),
  play: S(`<path d="M7.5 5.2v13.6a.8.8 0 0 0 1.2.7l11-6.8a.8.8 0 0 0 0-1.4l-11-6.8a.8.8 0 0 0-1.2.7z" fill="currentColor"/>`),
  pause: S(`<rect x="6.5" y="5" width="3.6" height="14" rx="1" fill="currentColor"/><rect x="13.9" y="5" width="3.6" height="14" rx="1" fill="currentColor"/>`),
  backward: S(`<path d="M11.5 6.5v11L3.5 12zM20.5 6.5v11L12.5 12z" fill="currentColor"/>`),
  forward: S(`<path d="M12.5 6.5v11l8-5.5zM3.5 6.5v11l8-5.5z" fill="currentColor"/>`),
  "chevron-left": S(`<path d="M15 4.5L7.5 12l7.5 7.5"/>`, ' stroke-width="2"'),
  "chevron-right": S(`<path d="M9 4.5l7.5 7.5L9 19.5"/>`, ' stroke-width="2"'),
  "chevron-down": S(`<path d="M5.5 9l6.5 6.5L18.5 9"/>`, ' stroke-width="2"'),
  "chevron-updown": S(`<path d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>`, ' stroke-width="1.9"'),
  grid: S(`<rect x="4" y="4" width="7" height="7" rx="1.8"/><rect x="13" y="4" width="7" height="7" rx="1.8"/><rect x="4" y="13" width="7" height="7" rx="1.8"/><rect x="13" y="13" width="7" height="7" rx="1.8"/>`),
  list: S(`${dot(4.5, 6)}${dot(4.5, 12)}${dot(4.5, 18)}<path d="M8.5 6H20M8.5 12H20M8.5 18H20"/>`),
  columns: S(`<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M9 4.5v15M15 4.5v15"/>`),
  gallery: S(`<rect x="3" y="4" width="18" height="11" rx="2.2"/><path d="M4.5 19.5h2M9 19.5h2M13 19.5h2M17.5 19.5h2"/>`, ' stroke-width="1.9"'),
  share: S(`<path d="M8.5 9.5H7a2 2 0 0 0-2 2v7.5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7.5a2 2 0 0 0-2-2h-1.5"/><path d="M12 14.5V3M8.5 6.5L12 3l3.5 3.5"/>`),
  tag: S(`<path d="M3.5 12.3V5a1.5 1.5 0 0 1 1.5-1.5h7.3l8.2 8.2a1.6 1.6 0 0 1 0 2.2l-6.9 6.9a1.6 1.6 0 0 1-2.2 0z"/>${dot(8, 8, 1.4)}`),
  ellipsis: S(`${dot(5.5, 12, 1.7)}${dot(12, 12, 1.7)}${dot(18.5, 12, 1.7)}`),
  clock: S(`<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3 2"/>`),
  people: S(`<circle cx="9" cy="8.5" r="3.2"/><path d="M3 19.5c.6-3.3 3-5 6-5s5.4 1.7 6 5"/><circle cx="16.5" cy="9" r="2.6"/><path d="M16.5 14c2.4 0 4 1.3 4.5 4"/>`),
  house: S(`<path d="M4 10.5L12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5H14V15h-4v5.5H5.5A1.5 1.5 0 0 1 4 19z"/>`),
  doc: S(`<path d="M6 3.5h8l4.5 4.5v11a1.5 1.5 0 0 1-1.5 1.5H6A1.5 1.5 0 0 1 4.5 19V5A1.5 1.5 0 0 1 6 3.5z"/><path d="M13.5 3.5V8.5h5"/>`),
  download: S(`<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5v8.5M8.5 12.8L12 16.3l3.5-3.5"/>`),
  photo: S(`<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><circle cx="8.5" cy="9.5" r="1.6"/><path d="M3.5 17l5-4.5 3.5 3 3.5-3.5 5 4.5"/>`),
  music: S(`<path d="M9 18V6l10-2v11.5"/><ellipse cx="6.5" cy="18" rx="2.6" ry="2.2" fill="currentColor"/><ellipse cx="16.5" cy="15.5" rx="2.6" ry="2.2" fill="currentColor"/>`),
  film: S(`<rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M7.5 4v16M16.5 4v16M3.5 8h4M3.5 12h4M3.5 16h4M16.5 8h4M16.5 12h4M16.5 16h4"/>`, ' stroke-width="1.6"'),
  cloud: S(`<path d="M7 18.5a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 10a4.3 4.3 0 0 1-.5 8.5z"/>`),
  eject: S(`<path d="M12 4.5l7.5 8.5h-15z" fill="currentColor"/><rect x="4.5" y="16" width="15" height="2.8" rx="1.1" fill="currentColor"/>`),
  drive: S(`<rect x="3" y="7" width="18" height="10" rx="2.5"/><path d="M6.5 13.5h6"/>${dot(17, 13.5, 1.2)}`),
  trash: S(`<path d="M4 6.5h16M9.5 6.5V4.5h5v2M6 6.5l1 13a1.5 1.5 0 0 0 1.5 1.4h7a1.5 1.5 0 0 0 1.5-1.4l1-13M10 10.5v6.5M14 10.5v6.5"/>`),
  plus: S(`<path d="M12 5v14M5 12h14"/>`, ' stroke-width="2"'),
  minus: S(`<path d="M5 12h14"/>`, ' stroke-width="2"'),
  sidebar: S(`<rect x="3" y="4.5" width="18" height="15" rx="2.8"/><path d="M9.5 4.5v15M5.5 8h1.5M5.5 11h1.5"/>`),
  screenshot: S(`<path d="M3.5 8V5.5a2 2 0 0 1 2-2H8M16 3.5h2.5a2 2 0 0 1 2 2V8M20.5 16v2.5a2 2 0 0 1-2 2H16M8 20.5H5.5a2 2 0 0 1-2-2V16"/><path d="M7.5 9.5h2l1-1.5h3l1 1.5h2a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-9a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="1.6"/>`, ' stroke-width="1.6"'),
  calculator: S(`<rect x="5" y="3" width="14" height="18" rx="2.5"/><rect x="7.8" y="5.8" width="8.4" height="3.4" rx=".8"/>${dot(9, 12.5, 1)}${dot(12, 12.5, 1)}${dot(15, 12.5, 1)}${dot(9, 15.5, 1)}${dot(12, 15.5, 1)}${dot(15, 15.5, 1)}${dot(9, 18.2, 1)}${dot(12, 18.2, 1)}${dot(15, 18.2, 1)}`, ' stroke-width="1.6"'),
  timer: S(`<circle cx="12" cy="13" r="7.5"/><path d="M12 13V9M10 3h4M18 6.5l1.2-1.2"/>`),
  contrast: S(`<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z" fill="currentColor"/>`, ' stroke-width="1.9"'),
  heart: S(`<path d="M12 20s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7.3 4.3 4.3 0 0 1 19.5 10c0 5.6-7.5 10-7.5 10z"/>`),
  folder: S(`<path d="M3.5 7V5.8A1.8 1.8 0 0 1 5.3 4h4.2l2 2.2h7.2a1.8 1.8 0 0 1 1.8 1.8v10.2a1.8 1.8 0 0 1-1.8 1.8H5.3a1.8 1.8 0 0 1-1.8-1.8z"/><path d="M3.5 9h17"/>`),
  apps: S(`${dot(6, 6, 1.9)}${dot(12, 6, 1.9)}${dot(18, 6, 1.9)}${dot(6, 12, 1.9)}${dot(12, 12, 1.9)}${dot(18, 12, 1.9)}${dot(6, 18, 1.9)}${dot(12, 18, 1.9)}${dot(18, 18, 1.9)}`),
  gear: S(`<path d="${gear(12, 12, 9, 7.2, 8, 0.45)}"/><circle cx="12" cy="12" r="3"/>`, ' stroke-width="1.6"'),
  power: S(`<path d="M12 3.5v8M7 6.3a7.5 7.5 0 1 0 10 0"/>`, ' stroke-width="1.9"'),
  lock: S(`<rect x="5" y="10.5" width="14" height="10" rx="2.2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>`),
  // Touch ID (Settings › Touch ID & Password): a fingerprint's ridges.
  touchid: S(`<path d="M4.6 9.6a7.6 7.6 0 0 1 14.8 0"/><path d="M7.6 20.2c-1.3-2.1-1.9-4.7-1.9-7.7a6.3 6.3 0 0 1 12.6 0v.8"/><path d="M9.1 12.3a2.9 2.9 0 0 1 5.8 0c0 3.1-.6 5.8-1.9 8.2"/><path d="M12 12.4c0 3.6-.8 6.4-2.2 8.6"/><path d="M18.1 16.6c-.3 1.5-.8 2.8-1.4 3.9"/>`, ' stroke-width="1.6"'),
  sparkles: S(`<path d="M10 3.5l1.6 4.6 4.6 1.6-4.6 1.6L10 16l-1.6-4.7-4.6-1.6 4.6-1.6zM17.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z" fill="currentColor" stroke-width="1"/>`),
  bell: S(`<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"/>`),
  xmark: S(`<path d="M6 6l12 12M18 6L6 18"/>`, ' stroke-width="2"'),
  checkmark: S(`<path d="M5 12.5l4.5 4.5L19 7"/>`, ' stroke-width="2.2"'),
  keyboard: S(`<rect x="2.5" y="6" width="19" height="12" rx="2.2"/><path d="M6 9.5h.01M9.3 9.5h.01M12.6 9.5h.01M15.9 9.5h.01M18 9.5h.01M6.5 14.5h11"/>`, ' stroke-width="1.7"'),
  globe: S(`<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.5 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.5-3.5-8.5s1-6 3.5-8.5z"/>`),
  "arrow-clockwise": S(`<path d="M19 12a7 7 0 1 1-2.1-5M19 4v4h-4"/>`),
  "rectangle-fill": S(`<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="M3 9h18"/>`),
  "zoom-in": S(`<circle cx="10.5" cy="10.5" r="6.2"/><path d="M15.2 15.2L20 20M8 10.5h5M10.5 8v5"/>`),
  wallpaper: S(`<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 15c4-4 7-1 10-3.5S18 8 21 9.5"/>`),
  envelope: S(`<rect x="3" y="5.5" width="18" height="13" rx="2.5"/><path d="M3.8 7.2l8.2 6 8.2-6"/>`),
  paperplane: S(`<path d="M20.5 3.5L10.2 13.8M20.5 3.5l-6.3 17-4-6.7-6.7-4z"/>`),
  compose: S(`<path d="M11 4.5H6.5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V13"/><path d="M17.6 3.9a1.9 1.9 0 0 1 2.7 2.7l-8.4 8.4-3.4.7.7-3.4z"/>`),
  reply: S(`<path d="M9.5 7L4.5 12l5 5M4.5 12H14a5.5 5.5 0 0 1 5.5 5.5V19"/>`),
  "reply-all": S(`<path d="M11 7l-5 5 5 5M7 7l-5 5 5 5M6 12h9a5 5 0 0 1 5 5v2"/>`),
  "forward-mail": S(`<path d="M14.5 7l5 5-5 5M19.5 12H10a5.5 5.5 0 0 0-5.5 5.5V19"/>`),
  archive: S(`<rect x="3.5" y="4.5" width="17" height="4.5" rx="1.2"/><path d="M5 9v9.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V9M10 13h4"/>`),
  flag: S(`<path d="M5.5 21V4M5.5 4.5c4-2.2 7 2.2 13 0v9c-6 2.2-9-2.2-13 0"/>`),
  star: S(`<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.8z"/>`),
  bubble: S(`<path d="M12 4c5 0 8.5 3.1 8.5 7s-3.5 7-8.5 7c-1 0-2-.1-2.9-.4L5 19.5l1.1-3.4C4.5 14.8 3.5 13 3.5 11c0-3.9 3.5-7 8.5-7z"/>`),
  calendar: S(`<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>${dot(8, 13.5, 1)}${dot(12, 13.5, 1)}${dot(16, 13.5, 1)}${dot(8, 17, 1)}${dot(12, 17, 1)}`),
  location: S(`<path d="M20 4L4 11.2l7.2 1.6L12.8 20z"/>`),
  pin: S(`<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>`),
  car: S(`<path d="M3.5 16.5h17v-4l-2-5.3a1.5 1.5 0 0 0-1.4-1H6.9a1.5 1.5 0 0 0-1.4 1l-2 5.3zM3.5 12.5h17M5.5 16.5v2.5M18.5 16.5v2.5"/>${dot(7, 14.5, 1.1)}${dot(17, 14.5, 1.1)}`),
  layers: S(`<path d="M12 3.5l8.5 4.5-8.5 4.5L3.5 8zM3.5 12l8.5 4.5 8.5-4.5M3.5 16l8.5 4.5 8.5-4.5"/>`),
  compass: S(`<circle cx="12" cy="12" r="8.5"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/>`),
  shuffle: S(`<path d="M3.5 7h3c4.5 0 5.5 10 10 10h3.5M3.5 17h3c1.8 0 3-1.5 4-3.5M13 9.5c1-2 2.2-2.5 4-2.5h3M18 4.5l2.5 2.5L18 9.5M18 14.5l2.5 2.5-2.5 2.5"/>`),
  repeat: S(`<path d="M4 11V9.5A2.5 2.5 0 0 1 6.5 7H19M16 4l3 3-3 3M20 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M8 20l-3-3 3-3"/>`),
  person: S(`<circle cx="12" cy="8" r="3.8"/><path d="M4.5 20.5c.8-4 3.8-6 7.5-6s6.7 2 7.5 6"/>`),
  bookmark: S(`<path d="M6.5 3.5h11v17l-5.5-4-5.5 4z"/>`),
  book: S(`<path d="M3.5 5.5c3-1.5 6-1.5 8.5 0v14c-2.5-1.5-5.5-1.5-8.5 0zM20.5 5.5c-3-1.5-6-1.5-8.5 0v14c2.5-1.5 5.5-1.5 8.5 0z"/>`),
  shield: S(`<path d="M12 3.5l7.5 3v5.5c0 4.5-3.2 7.8-7.5 9-4.3-1.2-7.5-4.5-7.5-9V6.5z"/>`),
  mic: S(`<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>`),
  video: S(`<rect x="3" y="6.5" width="12.5" height="11" rx="2.5"/><path d="M15.5 10.5l5-3v9l-5-3"/>`),
  phone: S(`<path d="M5 4h3.5l1.5 4.5-2 1.5a11 11 0 0 0 6 6l1.5-2L20 15.5V19a1.5 1.5 0 0 1-1.6 1.5A16.5 16.5 0 0 1 3.5 5.6 1.5 1.5 0 0 1 5 4z"/>`),
  info: S(`<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/>${dot(12, 7.8, 1.2)}`),
  smile: S(`<circle cx="12" cy="12" r="8.5"/><path d="M8.5 14.5a4.5 4.5 0 0 0 7 0"/>${dot(9.3, 10, 1.1)}${dot(14.7, 10, 1.1)}`),
  "arrow-up": S(`<path d="M12 19.5V5M6 11l6-6 6 6"/>`, ' stroke-width="2.2"'),
  "chevron-up": S(`<path d="M5.5 15l6.5-6.5 6.5 6.5"/>`, ' stroke-width="2"'),
  game: S(`<path d="M7 8.5h10a4.5 4.5 0 0 1 4.3 5.8l-1 3.3a2 2 0 0 1-3.4.8L15 16H9l-1.9 2.4a2 2 0 0 1-3.4-.8l-1-3.3A4.5 4.5 0 0 1 7 8.5zM8 11v3M6.5 12.5h3"/>${dot(15.5, 11.5, 1)}${dot(17.5, 13.5, 1)}`),
  brush: S(`<path d="M14.5 4.5l5 5-8 8-5-5zM6.5 12.5c-2 0-3 1.5-3 3.5v3.5H7c2 0 3.5-1 3.5-3"/>`),
  briefcase: S(`<rect x="3.5" y="7.5" width="17" height="12" rx="2.5"/><path d="M9 7.5V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5v2M3.5 12.5h17"/>`),
  code: S(`<path d="M8 7l-5 5 5 5M16 7l5 5-5 5M13.5 5l-3 14"/>`),
  // LCode: build, issues, devices and the Simulator's hardware buttons.
  hammer: S(`<path d="M8.5 4h8l3.5 3v2.2h-5L13 10.4h-1.4l-1.1-1.2h-2z" fill="currentColor"/><path d="M12.2 11.2L5.4 19.8" stroke-width="2.6"/>`),
  smartphone: S(`<rect x="6.5" y="2.5" width="11" height="19" rx="2.8"/><path d="M10.5 5.2h3"/>`),
  warning: S(`<path d="M10.6 4.3a1.6 1.6 0 0 1 2.8 0l7.9 14a1.6 1.6 0 0 1-1.4 2.4H4.1a1.6 1.6 0 0 1-1.4-2.4z"/><path d="M12 9.3v4.7"/>${dot(12, 17.2, 1.2)}`),
  "xmark-circle": S(`<circle cx="12" cy="12" r="8.5"/><path d="M9 9l6 6M15 9l-6 6"/>`),
  stop: S(`<rect x="6" y="6" width="12" height="12" rx="2.2" fill="currentColor"/>`),
  "rotate-left": S(`<rect x="9.5" y="7.5" width="11" height="13" rx="2.2"/><path d="M3.5 12a7 7 0 0 1 7-7.5h1.5M10 2.5l2 2-2 2"/>`),
  "rotate-right": S(`<rect x="3.5" y="7.5" width="11" height="13" rx="2.2"/><path d="M20.5 12a7 7 0 0 0-7-7.5H12M14 2.5l-2 2 2 2"/>`),
  tablet: S(`<rect x="4" y="3" width="16" height="18" rx="2.6"/><path d="M10.5 18h3"/>`),
  terminal: S(`<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M7 10l3 2.5L7 15M12.5 15.5h4.5"/>`),
  "sidebar-right": S(`<rect x="3" y="4.5" width="18" height="15" rx="2.8"/><path d="M14.5 4.5v15M17 8h1.5M17 11h1.5"/>`),
  // The screenshot toolbar (⇧⌘5): the whole screen, a selection (dashed), and
  // each with the record dot for recording.
  "capture-screen": S(`<rect x="2.5" y="4.5" width="19" height="13" rx="2.2"/><path d="M8.5 20.5h7"/>`),
  "capture-selection": S(`<rect x="3.5" y="5" width="17" height="14" rx="1.5" stroke-dasharray="2.6 2.4"/>`),
  "record-screen": S(`<rect x="2.5" y="4.5" width="19" height="13" rx="2.2"/><path d="M8.5 20.5h7"/>${dot(17, 13.5, 2.6)}`),
  "record-selection": S(`<rect x="3.5" y="5" width="17" height="14" rx="1.5" stroke-dasharray="2.6 2.4"/>${dot(16.5, 14.5, 2.6)}`),
  // Window › Move & Resize: the screen with the tile's part filled in.
  "tile-left": tile(3, 4.5, 9, 15),
  "tile-right": tile(12, 4.5, 9, 15),
  "tile-top": tile(3, 4.5, 18, 7.5),
  "tile-bottom": tile(3, 12, 18, 7.5),
  "tile-top-left": tile(3, 4.5, 9, 7.5),
  "tile-top-right": tile(12, 4.5, 9, 7.5),
  "tile-bottom-left": tile(3, 12, 9, 7.5),
  "tile-bottom-right": tile(12, 12, 9, 7.5),
  "tile-fill": tile(3, 4.5, 18, 15),
  "tile-center": tile(6.5, 7.5, 11, 9),
  "panel-bottom": S(`<rect x="3" y="4.5" width="18" height="15" rx="2.8"/><path d="M3 14.5h18"/>`),
  "chevron-small-right": S(`<path d="M10 7.5l4.5 4.5-4.5 4.5"/>`, ' stroke-width="1.6"'),
  eye: S(`<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>`),
  thermometer: S(`<path d="M10 4.5a2 2 0 0 1 4 0v9.3a4 4 0 1 1-4 0z"/><path d="M12 11v5"/>`),
  drop: S(`<path d="M12 3.5s6 6.4 6 11a6 6 0 0 1-12 0c0-4.6 6-11 6-11z"/>`),
  wind: S(`<path d="M3.5 9h11a3 3 0 1 0-3-3M3.5 15h14a3 3 0 1 1-3 3M3.5 12h7"/>`),
  gauge: S(`<path d="M4.5 17a8.5 8.5 0 1 1 15 0"/><path d="M12 13l3.5-4"/>${dot(12, 13, 1.3)}`),
  sunset: S(`<path d="M3 17.5h18M6.5 17.5a5.5 5.5 0 0 1 11 0M12 3.5v4M8.5 6L12 9.5 15.5 6M4 12.5l1.2.7M20 12.5l-1.2.7M6 21h12"/>`),
  airplay: S(`<path d="M6.5 17H5a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2V15a2 2 0 0 1-2 2h-1.5"/><path d="M12 14l4.5 6h-9z" fill="currentColor"/>`),
  scissors: S(`<circle cx="6.5" cy="17.5" r="2.8"/><circle cx="17.5" cy="17.5" r="2.8"/><path d="M8.5 15.5L18 4M15.5 15.5L6 4"/>`),
  copy: S(`<rect x="8" y="8" width="12" height="12.5" rx="2.2"/><path d="M16 8V5.7A1.7 1.7 0 0 0 14.3 4H5.7A1.7 1.7 0 0 0 4 5.7v8.6A1.7 1.7 0 0 0 5.7 16H8"/>`),
  paste: S(`<rect x="5" y="4.5" width="14" height="16.5" rx="2.2"/><rect x="9" y="3" width="6" height="3.5" rx="1.2" fill="currentColor"/>`),
  undo: S(`<path d="M9 14L4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>`),
  redo: S(`<path d="M15 14l5-5-5-5M20 9H9.5a5.5 5.5 0 0 0 0 11H13"/>`),
  pencil: S(`<path d="M16.5 4.2a2 2 0 0 1 2.9 2.9L8.6 17.9l-4 1 1-4z"/><path d="M14.5 6.2l2.9 2.9"/>`),
  link: S(`<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.2 1.2"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.2-1.2"/>`),
  fullscreen: S(`<path d="M14.5 3.5h6v6M20.5 3.5l-6.5 6.5M9.5 20.5h-6v-6M3.5 20.5l6.5-6.5"/>`),
  window: S(`<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 8.5h18"/>${dot(6, 6.5, .8)}${dot(8.5, 6.5, .8)}${dot(11, 6.5, .8)}`),
  "text-cursor": S(`<path d="M9 4h6M9 20h6M12 4v16"/>`),
  printer: S(`<path d="M7 9V3.5h10V9M7 17H5a1.5 1.5 0 0 1-1.5-1.5v-5A1.5 1.5 0 0 1 5 9h14a1.5 1.5 0 0 1 1.5 1.5v5A1.5 1.5 0 0 1 19 17h-2"/><rect x="7" y="14" width="10" height="6.5" rx="1"/>`),
  quote: S(`<path d="M5 18c2.5-1 4-3.4 4-6.5V7H4.5v5H9M15 18c2.5-1 4-3.4 4-6.5V7h-4.5v5H19"/>`),

  // LCode: languages, the App Designer's library and its inspectors.
  swift: S(`<path d="M3.5 6.2c3 2.9 6.2 5.3 9.4 6.9-2.3.6-5.4.2-8.4-1.6 2.6 3 6.3 5.5 10.4 5.7 1.6.1 3.2-.6 4.3.6.3-1.4-.4-2.8-1.1-3.5 1.1-3.7-.8-7.9-4.2-10.7 1.3 2.1 2.1 4.6 1.7 6.7C14.6 12.4 8.5 8.9 3.5 6.2z" fill="currentColor" stroke="none"/>`),
  python: S(`<path d="M11.8 2.8c-3.3 0-3.9 1.4-3.9 2.7v2.3h4.2v.9H6.2c-1.6 0-3 1.2-3 3.9s1.3 3.8 2.9 3.8h1.5v-2.3c0-1.6 1.4-3 3-3h4.1c1.3 0 2.4-1.1 2.4-2.4V5.5c0-1.3-1.2-2.7-5.3-2.7z" fill="currentColor" stroke="none"/><path d="M12.2 21.2c3.3 0 3.9-1.4 3.9-2.7v-2.3h-4.2v-.9h5.9c1.6 0 3-1.2 3-3.9s-1.3-3.8-2.9-3.8h-1.5v2.3c0 1.6-1.4 3-3 3H9.3c-1.3 0-2.4 1.1-2.4 2.4v3.2c0 1.3 1.2 2.7 5.3 2.7z" fill="currentColor" fill-opacity=".6" stroke="none"/>${dot(10, 5.3, .9)}`),
  rust: S(`<path fill-rule="evenodd" d="${gear(12, 12, 10.2, 8.4, 18, 0.45)}M12 5.2a6.8 6.8 0 1 0 0 13.6a6.8 6.8 0 1 0 0-13.6z" fill="currentColor" stroke="none"/><path d="M9.6 15.8V8.4h3a2.1 2.1 0 0 1 0 4.2h-3m2.6 0l2.5 3.2"/>`),
  "c-language": S(`<path d="M12 2.6l8.1 4.7v9.4L12 21.4l-8.1-4.7V7.3z"/><path d="M15.3 9.2a4.2 4.2 0 1 0 0 5.6" stroke-width="2"/>`),
  textformat: S(`<path d="M4.5 6.5V4.5h11v2M10 4.5v15M7.5 19.5h5"/><path d="M15 12.5h5M17.5 12.5v7" stroke-width="1.5"/>`),
  button: S(`<rect x="2.5" y="7" width="19" height="10" rx="5"/><path d="M8 12h8"/>`),
  toggle: S(`<rect x="2.5" y="7" width="19" height="10" rx="5"/><circle cx="16.5" cy="12" r="3.2" fill="currentColor" stroke="none"/>`),
  slider: S(`<path d="M3 12h18"/><circle cx="9" cy="12" r="3.2" fill="currentColor" stroke="none"/>`),
  textfield: S(`<rect x="2.5" y="6.5" width="19" height="11" rx="3"/><path d="M7 9.5v5"/>`),
  shapes: S(`<rect x="3" y="3" width="10" height="10" rx="2"/><circle cx="15" cy="15" r="6"/>`),
  "stack-vertical": S(`<rect x="4" y="3.5" width="16" height="7" rx="2"/><rect x="4" y="13.5" width="16" height="7" rx="2"/>`),
  "stack-horizontal": S(`<rect x="3.5" y="4" width="7" height="16" rx="2"/><rect x="13.5" y="4" width="7" height="16" rx="2"/>`),
  "stack-depth": S(`<rect x="3" y="7" width="13" height="13" rx="2.5"/><path d="M7 4.5V4a1 1 0 0 1 1-1h11a2 2 0 0 1 2 2v11a1 1 0 0 1-1 1h-.5"/>`),
  spacer: S(`<path d="M3 4v16M21 4v16M6.5 12h11M9 9.5L6.5 12 9 14.5M15 9.5l2.5 2.5-2.5 2.5"/>`),
  divider: S(`<path d="M3 12h18"/><rect x="5" y="3.5" width="14" height="5" rx="1.5" stroke-opacity=".55"/><rect x="5" y="15.5" width="14" height="5" rx="1.5" stroke-opacity=".55"/>`),
  card: S(`<rect x="3" y="4" width="18" height="16" rx="4"/><path d="M7 9h7M7 12.5h10M7 16h5" stroke-width="1.5"/>`),
  scroll: S(`<rect x="3" y="3" width="18" height="18" rx="3"/><path d="M17.5 6.5v5" stroke-width="2.2"/><path d="M6.5 8h7M6.5 12h7M6.5 16h7" stroke-width="1.4"/>`),
  "checkmark-square": S(`<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><path d="M8 12.2l2.8 2.8L16.2 9"/>`),
  progress: S(`<rect x="2.5" y="9.5" width="19" height="5" rx="2.5"/><path d="M5 12h7" stroke-width="2.6"/>`),
  segmented: S(`<rect x="2.5" y="7" width="19" height="10" rx="3"/><path d="M9 7v10M15 7v10"/><rect x="3.8" y="8.3" width="4" height="7.4" rx="1.5" fill="currentColor" stroke="none" fill-opacity=".45"/>`),
  palette: S(`<path d="M12 3a9 9 0 0 0 0 18c1.2 0 1.8-.8 1.8-1.7 0-1.2-1-1.6-1-2.6 0-.9.7-1.6 1.6-1.6h2.2A4.4 4.4 0 0 0 21 10.7C21 6.4 17 3 12 3z"/>${dot(7.5, 11)}${dot(9.5, 7.3)}${dot(14, 6.8)}${dot(17, 9.6)}`),
  eyedropper: S(`<path d="M14.5 6.5l3 3M4 20l1.2-3.3 8.4-8.4 2.1 2.1-8.4 8.4z"/><path d="M13.8 5.8l1.9-1.9a2.1 2.1 0 0 1 3 3l-1.9 1.9z" fill="currentColor"/>`),
  gradient: S(`<defs><linearGradient id="gg-grad" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="currentColor" stop-opacity=".1"/><stop offset="1" stop-color="currentColor"/></linearGradient></defs><rect x="3.5" y="3.5" width="17" height="17" rx="4" fill="url(#gg-grad)"/>`),
  sliders: S(`<path d="M4 6.5h16M4 12h16M4 17.5h16" stroke-opacity=".5"/>${dot(9, 6.5, 2.1)}${dot(15.5, 12, 2.1)}${dot(7, 17.5, 2.1)}`),
  ruler: S(`<rect x="2.5" y="7.5" width="19" height="9" rx="1.5"/><path d="M6 7.5v3M9.5 7.5v4.5M13 7.5v3M16.5 7.5v4.5M20 7.5v3" stroke-width="1.4"/>`),
  bolt: S(`<path d="M13.5 2.5L5 13.5h6l-1.5 8 8.5-11h-6z" fill="currentColor" fill-opacity=".2"/>`),
  cursor: S(`<path d="M6 3v15.5l4.2-4.1 2.9 6.3 2.4-1.1-2.9-6.2h5.9z" fill="currentColor" fill-opacity=".15"/>`),
  curlybraces: S(`<path d="M8.5 4H8a2 2 0 0 0-2 2v3.2c0 1-.8 2-2 2.8 1.2.8 2 1.8 2 2.8V18a2 2 0 0 0 2 2h.5M15.5 4h.5a2 2 0 0 1 2 2v3.2c0 1 .8 2 2 2.8-1.2.8-2 1.8-2 2.8V18a2 2 0 0 1-2 2h-.5"/>`),
  shippingbox: S(`<path d="M3.5 7.5L12 3l8.5 4.5v9L12 21l-8.5-4.5z"/><path d="M3.5 7.5L12 12l8.5-4.5M12 12v9M7.7 5.2l8.5 4.6"/>`),
  appicon: S(`<path d="M7.6 3h8.8c2.6 0 4.6 2 4.6 4.6v8.8c0 2.6-2 4.6-4.6 4.6H7.6C5 21 3 19 3 16.4V7.6C3 5 5 3 7.6 3z"/><path d="M12 7.2l1.4 3 3.2.4-2.4 2.2.6 3.2-2.8-1.6-2.8 1.6.6-3.2-2.4-2.2 3.2-.4z" fill="currentColor" stroke="none"/>`),
  "text-align-left": S(`<path d="M4 6h16M4 10h10M4 14h16M4 18h10"/>`),
  "text-align-center": S(`<path d="M4 6h16M7 10h10M4 14h16M7 18h10"/>`),
  "text-align-right": S(`<path d="M4 6h16M10 10h10M4 14h16M10 18h10"/>`),
  puzzle: S(`<path d="M5 8h3.5a2 2 0 1 1 4 0H16v3.5a2 2 0 1 1 0 4V19h-3.5a2 2 0 1 0-4 0H5v-3.5a2 2 0 1 0 0-4z"/>`),
  wand: S(`<path d="M4 20l11-11M13.5 7.5l3 3"/><path d="M17 3v3M15.5 4.5h3M20 8v2.4M18.8 9.2h2.4M9.5 3.5v2M8.5 4.5h2" stroke-width="1.4"/>`),
  circle: S(`<circle cx="12" cy="12" r="8.5"/>`),
  "square-dashed": S(`<rect x="3.5" y="3.5" width="17" height="17" rx="3.5" stroke-dasharray="3 2.6"/>`),
  inspector: S(`<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M14.5 4v16M17 8h1.5M17 11h1.5"/>`),
};

// ------------------------------------------------------------------ app icons
const SQ = squircle();
const lin = (id, a, b, x1 = 0, y1 = 0, x2 = 0, y2 = 1) =>
  `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;

// Wraps artwork in the squircle, adds the Liquid Glass rim and top sheen.
function app(name, accent, defs, body) {
  // The background and sheen are drawn as the squircle itself: Qt's SVG renderer
  // (Dock, Spotlight, SDDM) ignores clip-path, so the clip is only a second line of defence.
  body = body.replace(/<rect class="bg" (fill="[^"]*") width="100" height="100"\/>/, `<path class="bg" $1 d="${SQ}"/>`);
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" data-accent="${accent}">
<defs><clipPath id="${name}-clip"><path d="${SQ}"/></clipPath>${defs}
<linearGradient id="${name}-sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".28"/><stop offset=".45" stop-color="#fff" stop-opacity="0"/></linearGradient>
<linearGradient id="${name}-rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".75"/><stop offset=".5" stop-color="#fff" stop-opacity=".08"/><stop offset="1" stop-color="#fff" stop-opacity=".45"/></linearGradient>
<pattern id="${name}-art" patternUnits="userSpaceOnUse" width="100" height="100">${body}</pattern></defs>
<g clip-path="url(#${name}-clip)"><path d="${SQ}" fill="url(#${name}-art)"/><path d="${SQ}" fill="url(#${name}-sheen)"/></g>
<path d="${SQ}" fill="none" stroke="url(#${name}-rim)" stroke-width="1.2"/></svg>`;
}

export const apps = {
  files: app("files", "#1a8cff", lin("files-bg", "#6cd0ff", "#0a74f0") + lin("files-f", "#ffffff", "#e3f1ff"),
    `<rect class="bg" fill="url(#files-bg)" width="100" height="100"/>
     <path class="tint" fill="#fff" fill-opacity=".55" d="M22 36a5 5 0 0 1 5-5h14.5a4 4 0 0 1 3 1.3l3.2 3.7H73a5 5 0 0 1 5 5v4H22z"/>
     <path class="tint" fill="url(#files-f)" d="M20 45a5 5 0 0 1 5-5h50a5 5 0 0 1 5 5v22a6 6 0 0 1-6 6H26a6 6 0 0 1-6-6z"/>
     <path d="M36 57.5q14 7 28 0" fill="none" stroke="#0a74f0" stroke-width="3.2" stroke-linecap="round"/>`),

  browser: app("browser", "#3ba0ff", lin("browser-bg", "#1b4fb8", "#0b1f4f") + lin("browser-gold", "#ffe08a", "#f5a524", 0, 0, 1, 1),
    `<rect class="bg" fill="url(#browser-bg)" width="100" height="100"/>
     <circle cx="50" cy="50" r="29" fill="#3ba0ff" fill-opacity=".25"/>
     <g class="tint-stroke" fill="none" stroke="#fff" stroke-width="2.4" stroke-opacity=".95">
       <circle cx="50" cy="50" r="27"/><ellipse cx="50" cy="50" rx="11" ry="27"/><path d="M23 50h54M27 37h46M27 63h46"/></g>
     <ellipse cx="50" cy="50" rx="40" ry="13" fill="none" stroke="url(#browser-gold)" stroke-width="4" transform="rotate(-24 50 50)"/>
     <circle cx="84" cy="36" r="4.5" fill="#ffe08a" transform="rotate(-24 50 50) translate(-3 14)"/>`),

  mail: app("mail", "#2b8bff", lin("mail-bg", "#62bfff", "#1662f0"),
    `<rect class="bg" fill="url(#mail-bg)" width="100" height="100"/>
     <rect class="tint" fill="#fff" x="19" y="30" width="62" height="42" rx="6"/>
     <path d="M21 33l29 21 29-21" fill="none" stroke="#1d74f5" stroke-opacity=".55" stroke-width="3" stroke-linejoin="round"/>`),

  messages: app("messages", "#34c759", lin("messages-bg", "#79ee6c", "#16b33a"),
    `<rect class="bg" fill="url(#messages-bg)" width="100" height="100"/>
     <path class="tint" fill="#fff" d="M50 22c17.7 0 32 11.2 32 25s-14.3 25-32 25c-3.6 0-7-.4-10.2-1.3C35.5 74.4 29 77 22.5 77c3.2-3 5.3-6.7 5.8-10.6C22 61.8 18 54.8 18 47c0-13.8 14.3-25 32-25z"/>
     <circle cx="38" cy="47" r="3.6" fill="#1fbf3b"/><circle cx="50" cy="47" r="3.6" fill="#1fbf3b"/><circle cx="62" cy="47" r="3.6" fill="#1fbf3b"/>`),

  music: app("music", "#ff375f", lin("music-bg", "#ff7a8e", "#f5173a"),
    `<rect class="bg" fill="url(#music-bg)" width="100" height="100"/>
     <path class="tint" fill="#fff" d="M40 29.5l30-7.5a3 3 0 0 1 3.7 2.9V63a9.5 8 0 1 1-5-7V35.7L45 41.5V70a9.5 8 0 1 1-5-7z"/>`),

  photos: app("photos", "#ff9f0a", lin("photos-bg", "#ffffff", "#eceef3") + lin("photos-sky", "#ffb347", "#ff5e7e") + lin("photos-m1", "#7b61ff", "#3d2a9c") + lin("photos-m2", "#1e8bff", "#0b4fb3"),
    `<rect class="bg" fill="url(#photos-bg)" width="100" height="100"/>
     <g transform="rotate(-6 50 50)"><rect x="20" y="22" width="60" height="56" rx="9" fill="url(#photos-sky)"/>
     <circle cx="62" cy="40" r="8" fill="#fff2a8"/>
     <path d="M20 66l17-20 13 13 8-8 22 18v5a9 9 0 0 1-9 9H29a9 9 0 0 1-9-9z" fill="url(#photos-m1)"/>
     <path d="M20 72l14-9 14 7 16-11 16 13v2a9 9 0 0 1-9 9H29a9 9 0 0 1-9-9z" fill="url(#photos-m2)"/></g>`),

  settings: app("settings", "#98989d", lin("settings-bg", "#b8b8be", "#6d6d72") + lin("settings-g", "#f4f4f6", "#c5c5ca"),
    `<rect class="bg" fill="url(#settings-bg)" width="100" height="100"/>
     <path class="tint" fill="url(#settings-g)" d="${gear(50, 50, 33, 27, 18, 0.5)}"/>
     <circle cx="50" cy="50" r="19" fill="#77777c"/><circle cx="50" cy="50" r="15" fill="url(#settings-g)"/>
     <path d="${gear(50, 50, 13, 10, 9, 0.45)}" fill="#8e8e93"/><circle cx="50" cy="50" r="4.5" fill="#dcdce0"/>`),

  terminal: app("terminal", "#30d158", lin("terminal-bg", "#3a3a3e", "#141416"),
    `<rect class="bg" fill="url(#terminal-bg)" width="100" height="100"/>
     <rect x="0" y="0" width="100" height="14" fill="#fff" fill-opacity=".08"/>
     <path d="M26 42l11 9-11 9" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" class="tint-stroke"/>
     <path d="M43 62h20" stroke="#30d158" stroke-width="5" stroke-linecap="round"/>`),

  notes: app("notes", "#ffcc00", lin("notes-bg", "#ffe680", "#ffb800"),
    `<rect class="bg" fill="url(#notes-bg)" width="100" height="100"/>
     <g transform="rotate(4 50 52)"><rect class="tint" fill="#fff" x="24" y="20" width="52" height="62" rx="5"/>
     <path d="M32 36h36M32 46h36M32 56h36M32 66h22" stroke="#d6cbb0" stroke-width="2.5" stroke-linecap="round"/>
     <rect x="24" y="20" width="52" height="8" rx="4" fill="#f5a524"/></g>`),

  calendar: app("calendar", "#ff453a", lin("calendar-bg", "#ffffff", "#f1f1f4"),
    `<rect class="bg" fill="url(#calendar-bg)" width="100" height="100"/>
     <text x="50" y="30" text-anchor="middle" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="600" font-size="13" fill="#ff3b30" letter-spacing=".5">SAT</text>
     <text class="tint-text" x="50" y="76" text-anchor="middle" font-family="Inter, Helvetica, Arial, sans-serif" font-weight="300" font-size="46" fill="#1c1c1e" letter-spacing="-2">26</text>`),

  calculator: app("calculator", "#ff9f0a", lin("calculator-bg", "#48484c", "#1c1c1e"),
    `<rect class="bg" fill="url(#calculator-bg)" width="100" height="100"/>
     ${[0, 1, 2, 3].map((r) => [0, 1, 2, 3].map((c) => `<circle cx="${23 + c * 18}" cy="${27 + r * 16}" r="6.8" fill="${c === 3 ? "#ff9f0a" : r === 0 ? "#a5a5aa" : "#5c5c60"}"/>`).join("")).join("")}`),

  maps: app("maps", "#30d158", lin("maps-bg", "#eef3e6", "#dfe8d3"),
    `<rect class="bg" fill="url(#maps-bg)" width="100" height="100"/>
     <path d="M0 64c20-6 30 6 52-2s32-18 48-14v52H0z" fill="#8ed1ff"/>
     <path d="M-2 20l40 16 22-40M58 -4l14 44 32 6" stroke="#fff" stroke-width="7" fill="none"/>
     <path d="M-4 86L104 18" stroke="#ffd35a" stroke-width="7"/>
     <rect x="62" y="56" width="22" height="16" rx="3" fill="#a6db8a" transform="rotate(-18 73 64)"/>
     <path d="M50 22a13 13 0 0 1 13 13c0 10-13 23-13 23S37 45 37 35a13 13 0 0 1 13-13z" fill="#ff3b30" stroke="#fff" stroke-width="2.5"/>
     <circle cx="50" cy="35" r="4.8" fill="#fff"/>`),

  store: app("store", "#0a84ff", lin("store-bg", "#4cb4ff", "#0060df"),
    `<rect class="bg" fill="url(#store-bg)" width="100" height="100"/>
     <path class="tint-stroke" d="M50 22v33M37 43l13 13 13-13" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
     <path class="tint-stroke" d="M24 58v10a7 7 0 0 0 7 7h38a7 7 0 0 0 7-7V58" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round"/>`),

  launcher: app("launcher", "#bf5af2", lin("launcher-bg", "#3d3d56", "#15151f"),
    `<rect class="bg" fill="url(#launcher-bg)" width="100" height="100"/>
     ${[["#ff453a", "#ff9f0a", "#ffd60a"], ["#30d158", "#64d2ff", "#0a84ff"], ["#5e5ce6", "#bf5af2", "#ff375f"]].map((row, r) => row.map((c, i) => `<rect x="${21 + i * 21}" y="${21 + r * 21}" width="16" height="16" rx="4.6" fill="${c}"/>`).join("")).join("")}`),

  lcode: app("lcode", "#0a84ff", lin("lcode-bg", "#2f9bff", "#0b4fd0"),
    `<rect class="bg" fill="url(#lcode-bg)" width="100" height="100"/>
     ${[16, 28, 40, 52, 64, 76, 88].map((v) => `<path d="M${v} 0v100M0 ${v}h100" stroke="#fff" stroke-opacity=".08" stroke-width="1"/>`).join("")}
     <path class="tint-stroke" d="M30 36L16 50l14 14M70 36l14 14-14 14" fill="none" stroke="#fff" stroke-opacity=".6" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
     <path class="tint" fill="#fff" d="M41 26h10v38h17v10H41z"/>`),

  airdrop: app("airdrop", "#0a84ff", lin("airdrop-bg", "#5ac8fa", "#0a6cf0"),
    `<rect class="bg" fill="url(#airdrop-bg)" width="100" height="100"/>
     <path class="tint-stroke" d="M42.22 63.78A11 11 0 1 1 57.78 63.78 M35.15 70.85A21 21 0 1 1 64.85 70.85 M28.08 77.92A31 31 0 1 1 71.92 77.92" fill="none" stroke="#fff" stroke-width="6.5" stroke-linecap="round"/>
     <circle class="tint" cx="50" cy="56" r="4.5" fill="#fff"/>`),

  // Passwords: a key on blue, as on the Mac.
  passwords: app("passwords", "#0a84ff", lin("passwords-bg", "#7fd8ff", "#0a62e6") + lin("passwords-k", "#ffffff", "#dceeff"),
    `<rect class="bg" fill="url(#passwords-bg)" width="100" height="100"/>
     <g class="tint" fill="url(#passwords-k)">
       <path fill-rule="evenodd" d="M35 31a19 19 0 1 1 0 38 19 19 0 0 1 0-38zm0 11a8 8 0 1 0 0 16 8 8 0 0 0 0-16z"/>
       <path d="M51 45.5h31a3 3 0 0 1 3 3v3a3 3 0 0 1-3 3h-4v8a3 3 0 0 1-3 3h-3a3 3 0 0 1-3-3v-8h-3v5a3 3 0 0 1-3 3h-2a3 3 0 0 1-3-3v-5h-5z"/>
     </g>`),

  // Citron Intelligence: Citron's orb (lib/CitronOrb.qml), clouds of its four
  // colours inside a glass ball. Radial gradients only: Qt's SVG renderer has no blur.
  intelligence: app("intelligence", "#a35cff", lin("intelligence-bg", "#2a2350", "#0c0a1f")
      + `<radialGradient id="intelligence-ball" cx="50" cy="52" r="27" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#3a7bff"/><stop offset="1" stop-color="#2a3fd0"/></radialGradient>`
      + `<radialGradient id="intelligence-c" cx="40" cy="42" r="20" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#5ee7ff" stop-opacity=".95"/><stop offset=".55" stop-color="#5ee7ff" stop-opacity=".55"/><stop offset="1" stop-color="#5ee7ff" stop-opacity="0"/></radialGradient><radialGradient id="intelligence-v" cx="61" cy="57" r="21" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#a35cff" stop-opacity=".95"/><stop offset=".55" stop-color="#a35cff" stop-opacity=".55"/><stop offset="1" stop-color="#a35cff" stop-opacity="0"/></radialGradient><radialGradient id="intelligence-p" cx="56" cy="39" r="15" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ff5fb4" stop-opacity=".95"/><stop offset=".55" stop-color="#ff5fb4" stop-opacity=".55"/><stop offset="1" stop-color="#ff5fb4" stop-opacity="0"/></radialGradient>`
      + `<radialGradient id="intelligence-core" cx="50" cy="50" r="13" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity=".75"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>`
      + `<radialGradient id="intelligence-bloom" cx="50" cy="52" r="40" gradientUnits="userSpaceOnUse"><stop offset=".55" stop-color="#7a5cff" stop-opacity=".45"/><stop offset="1" stop-color="#7a5cff" stop-opacity="0"/></radialGradient>`
      + lin("intelligence-glass", "#ffffff", "#ffffff"),
    `<rect class="bg" fill="url(#intelligence-bg)" width="100" height="100"/>
     <circle cx="50" cy="52" r="40" fill="url(#intelligence-bloom)"/>
     <g transform="translate(50 51) scale(1.22) translate(-50 -51)">
     <circle cx="50" cy="51" r="27" fill="url(#intelligence-ball)"/>
     <circle cx="40" cy="42" r="20" fill="url(#intelligence-c)"/>
     <circle cx="61" cy="57" r="21" fill="url(#intelligence-v)"/>
     <circle cx="56" cy="39" r="15" fill="url(#intelligence-p)"/>
     <circle cx="50" cy="50" r="13" fill="url(#intelligence-core)"/>
     <circle cx="50" cy="51" r="27" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="1.4"/>
     <ellipse cx="41" cy="33" rx="10" ry="4.5" fill="#fff" fill-opacity=".5" transform="rotate(-20 41 33)"/></g>`),

  // Disk Utility: a drive and a stethoscope, as the Mac's.
  diskutility: app("diskutility", "#8e8e93", lin("diskutility-bg", "#f4f5f8", "#c6cbd3")
      + lin("diskutility-drive", "#fbfbfd", "#a7aeb8") + lin("diskutility-face", "#e9ecf0", "#c3c8d0"),
    `<rect class="bg" fill="url(#diskutility-bg)" width="100" height="100"/>
     <rect x="16" y="50" width="68" height="30" rx="7" fill="url(#diskutility-drive)" stroke="#8a919b" stroke-width="1"/>
     <rect x="21" y="55" width="58" height="9" rx="3" fill="url(#diskutility-face)"/>
     <path d="M26 71h28" stroke="#6b7280" stroke-width="2.4" stroke-linecap="round"/>
     <circle cx="73" cy="71" r="2.8" fill="#34c759"/>
     <g fill="none" stroke="#2f343b" stroke-width="3.4" stroke-linecap="round">
       <path d="M36 16v9a14 14 0 0 0 28 0v-9"/>
       <path d="M50 39c0 9 4 14 14 14"/>
     </g>
     <circle cx="36" cy="15" r="3" fill="#2f343b"/><circle cx="64" cy="15" r="3" fill="#2f343b"/>
     <circle class="tint" cx="68" cy="53" r="7.5" fill="#b6bcc5" stroke="#2f343b" stroke-width="2.6"/>`),

  weather: app("weather", "#64d2ff", lin("weather-bg", "#3aa0f5", "#1a5fd0") + lin("weather-sun", "#ffe36b", "#ffb300"),
    `<rect class="bg" fill="url(#weather-bg)" width="100" height="100"/>
     <circle cx="40" cy="40" r="15" fill="url(#weather-sun)"/>
     <path class="tint" fill="#fff" d="M36 74a12 12 0 0 1-1.5-23.9A15 15 0 0 1 63 45a11 11 0 0 1 3 29z"/>`),
};

// Non-squircle glyphs that live in the dock or Files grid.
const plain = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs>${defs}</defs>${body}</svg>`;
export const places = {
  trash: plain(lin("tr-body", "#ffffff", "#d9dde4") + lin("tr-rim", "#f7f8fa", "#c8ccd4"),
    `<path d="M24 26l6 60a6 6 0 0 0 6 5.4h28a6 6 0 0 0 6-5.4l6-60z" fill="url(#tr-body)" fill-opacity=".72" stroke="#fff" stroke-width="1.2"/>
     ${[35, 43, 50, 57, 65].map((x) => `<path d="M${x} 32l${(x - 50) * 0.08} 52" stroke="#8a93a3" stroke-opacity=".38" stroke-width="2.4" stroke-linecap="round"/>`).join("")}
     <rect x="20" y="18" width="60" height="10" rx="5" fill="url(#tr-rim)" stroke="#fff" stroke-width="1"/>`),
  "trash-full": plain(lin("tf-body", "#ffffff", "#d9dde4") + lin("tf-rim", "#f7f8fa", "#c8ccd4"),
    `<path d="M26 22l14 -8 10 6 12 -9 10 10 -4 8z" fill="#f4f1ea" stroke="#d6d1c4" stroke-width="1"/><path d="M34 20l10-9 8 7" fill="#e9eef7" stroke="#c9d1de" stroke-width="1"/>
     <path d="M24 26l6 60a6 6 0 0 0 6 5.4h28a6 6 0 0 0 6-5.4l6-60z" fill="url(#tf-body)" fill-opacity=".72" stroke="#fff" stroke-width="1.2"/>
     <path d="M30 34h40l-3 18H33z" fill="#f2efe8" opacity=".9"/><path d="M34 52h32l-2 14H36z" fill="#e3e8f1" opacity=".85"/>
     ${[35, 43, 50, 57, 65].map((x) => `<path d="M${x} 32l${(x - 50) * 0.08} 52" stroke="#8a93a3" stroke-opacity=".38" stroke-width="2.4" stroke-linecap="round"/>`).join("")}
     <rect x="20" y="18" width="60" height="10" rx="5" fill="url(#tf-rim)" stroke="#fff" stroke-width="1"/>`),
  folder: plain(lin("fo-back", "#5ab8f2", "#3d9ee6") + lin("fo-front", "#9adcff", "#64c0f6"),
    `<path d="M10 24a6 6 0 0 1 6-6h20a5 5 0 0 1 3.8 1.8L44 25h40a6 6 0 0 1 6 6v8H10z" fill="url(#fo-back)"/>
     <path d="M8 36a6 6 0 0 1 6-6h72a6 6 0 0 1 6 6v42a6 6 0 0 1-6 6H14a6 6 0 0 1-6-6z" fill="url(#fo-front)"/>
     <path d="M8 36a6 6 0 0 1 6-6h72a6 6 0 0 1 6 6" fill="none" stroke="#fff" stroke-opacity=".6" stroke-width="1.2"/>`),
  document: plain(lin("doc-p", "#ffffff", "#f1f2f5"),
    `<path d="M24 8h36l20 20v58a6 6 0 0 1-6 6H24a6 6 0 0 1-6-6V14a6 6 0 0 1 6-6z" fill="url(#doc-p)" stroke="#d3d6dc" stroke-width="1.2"/>
     <path d="M60 8v14a6 6 0 0 0 6 6h14" fill="#e8eaee" stroke="#d3d6dc" stroke-width="1.2"/>
     <path d="M30 44h40M30 52h40M30 60h40M30 68h26" stroke="#c4c8cf" stroke-width="2.6" stroke-linecap="round"/>`),
  audio: plain(lin("au-p", "#ffffff", "#f1f2f5"),
    `<path d="M24 8h36l20 20v58a6 6 0 0 1-6 6H24a6 6 0 0 1-6-6V14a6 6 0 0 1 6-6z" fill="url(#au-p)" stroke="#d3d6dc" stroke-width="1.2"/>
     <path d="M60 8v14a6 6 0 0 0 6 6h14" fill="#e8eaee" stroke="#d3d6dc" stroke-width="1.2"/>
     <path d="M43 44l18-4v24a5 4.3 0 1 1-3-3.7V47l-12 2.6V68a5 4.3 0 1 1-3-3.7z" fill="#ff375f"/>`),
  image: plain(lin("im-p", "#ffffff", "#f1f2f5") + lin("im-s", "#ffb347", "#ff5e7e"),
    `<path d="M24 8h36l20 20v58a6 6 0 0 1-6 6H24a6 6 0 0 1-6-6V14a6 6 0 0 1 6-6z" fill="url(#im-p)" stroke="#d3d6dc" stroke-width="1.2"/>
     <rect x="28" y="40" width="42" height="34" rx="4" fill="url(#im-s)"/><path d="M28 68l12-12 9 8 8-7 13 11v2a4 4 0 0 1-4 4H32a4 4 0 0 1-4-4z" fill="#5e5ce6"/>`),
  disk: plain(lin("dk-b", "#f2f3f5", "#b9bdc6"),
    `<rect x="10" y="30" width="80" height="40" rx="8" fill="url(#dk-b)" stroke="#9ca1ab" stroke-width="1.2"/>
     <path d="M20 58h30" stroke="#8a8f99" stroke-width="3" stroke-linecap="round"/><circle cx="76" cy="58" r="3" fill="#30d158"/>`),
};
