// Experimental Liquid Glass refraction (opt-in with ?refract): an SVG displacement
// filter whose map is generated per element size, so the backdrop bends towards the
// rim like a lens. Chromium currently drops the blur when a url() filter is chained
// in backdrop-filter, so this stays off by default; on Linux the compositor shader
// is where real refraction belongs (see compositor/liquid-glass/).
const NS = "http://www.w3.org/2000/svg";
let defs, count = 0;
const cache = new Map();

function displacementMap(w, h, r, bezel) {
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  const ctx = c.getContext("2d");
  const img = ctx.createImageData(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      // Signed distance to the rounded-rect edge and the outward normal.
      const qx = Math.max(Math.abs(x - w / 2) - (w / 2 - r), 0), qy = Math.max(Math.abs(y - h / 2) - (h / 2 - r), 0);
      const inside = Math.min(w / 2 - Math.abs(x - w / 2), h / 2 - Math.abs(y - h / 2));
      const dist = qx || qy ? r - Math.hypot(qx, qy) : inside;
      let nx = 0, ny = 0;
      if (qx || qy) { const l = Math.hypot(qx, qy) || 1; nx = (qx / l) * Math.sign(x - w / 2); ny = (qy / l) * Math.sign(y - h / 2); }
      else if (w / 2 - Math.abs(x - w / 2) < h / 2 - Math.abs(y - h / 2)) nx = Math.sign(x - w / 2); else ny = Math.sign(y - h / 2);
      // Convex lens profile: strongest bend right at the rim, flat in the middle.
      const t = Math.max(0, 1 - dist / bezel), k = t * t * (3 - 2 * t);
      const i = (y * w + x) * 4;
      img.data[i] = 128 - nx * k * 127;
      img.data[i + 1] = 128 - ny * k * 127;
      img.data[i + 2] = 128;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return c.toDataURL();
}

export function refract(el, { radius, bezel = 16, scale = 28 } = {}) {
  const r = el.getBoundingClientRect();
  const w = Math.round(r.width), hgt = Math.round(r.height);
  if (!w || !hgt) return;
  const rad = Math.min(radius ?? parseFloat(getComputedStyle(el).borderTopLeftRadius) ?? 20, w / 2, hgt / 2);
  const key = `${w}x${hgt}x${rad}x${bezel}x${scale}`;
  let id = cache.get(key);
  if (!id) {
    id = `lg-${++count}`;
    const f = document.createElementNS(NS, "filter");
    f.setAttribute("id", id);
    f.setAttribute("x", "0"); f.setAttribute("y", "0"); f.setAttribute("width", "100%"); f.setAttribute("height", "100%");
    f.setAttribute("color-interpolation-filters", "sRGB");
    f.innerHTML = `<feImage href="${displacementMap(w, hgt, rad, bezel)}" x="0" y="0" width="${w}" height="${hgt}" result="map"/>
      <feDisplacementMap in="SourceGraphic" in2="map" scale="${scale}" xChannelSelector="R" yChannelSelector="G"/>`;
    defs.append(f);
    cache.set(key, id);
  }
  el.style.setProperty("--refract", `url(#${id})`);
  el.dataset.refract = "";
}

export function initGlass() {
  const q = new URLSearchParams(location.search);
  const enabled = q.has("refract") && CSS.supports("backdrop-filter", "url(#x)");
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("style", "position:absolute;width:0;height:0");
  defs = document.createElementNS(NS, "defs");
  svg.append(defs);
  document.body.append(svg);
  if (!enabled) return;
  // Apply to the Dock and Control Center modules whenever they (re)render.
  const apply = () => document.querySelectorAll("#dock, #cc .glass").forEach((el) => refract(el, { bezel: el.id === "dock" ? 14 : 12, scale: el.id === "dock" ? 30 : 22 }));
  new MutationObserver(() => requestAnimationFrame(apply)).observe(document.getElementById("cc"), { childList: true });
  new ResizeObserver(() => refract(document.getElementById("dock"), { bezel: 14, scale: 30 })).observe(document.getElementById("dock"));
  apply();
}
