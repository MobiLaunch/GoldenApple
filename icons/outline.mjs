// Turn a stroked symbol SVG into one filled path.
//
// GTK 4.20+ draws symbolic icons with its own SVG renderer, which fills shapes
// and ignores strokes: a stroked magnifier comes out as a solid disc and a
// stroked "+" as nothing. The symbols are drawn with strokes (the browser and
// Qt render those fine), so the icon theme gets outlined copies: every stroke is
// expanded with Skia's PathKit and everything is merged into a single fill.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

export async function loadOutliner() {
  const init = require("pathkit-wasm/bin/pathkit.js");
  const P = await init({ wasmBinary: readFileSync(require.resolve("pathkit-wasm/bin/pathkit.wasm")) });

  const attrsOf = (s) => Object.fromEntries([...s.matchAll(/([\w:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
  const num = (v, d = 0) => (v == null ? d : parseFloat(v));

  function shape(tag, a) {
    if (tag === "path") return P.FromSVGString(a.d);
    const p = P.NewPath();
    if (tag === "circle") p.ellipse(num(a.cx), num(a.cy), num(a.r), num(a.r), 0, 0, 2 * Math.PI);
    else if (tag === "ellipse") p.ellipse(num(a.cx), num(a.cy), num(a.rx), num(a.ry), 0, 0, 2 * Math.PI);
    else if (tag === "line") { p.moveTo(num(a.x1), num(a.y1)); p.lineTo(num(a.x2), num(a.y2)); }
    else if (tag === "rect") {
      const x = num(a.x), y = num(a.y), w = num(a.width), h = num(a.height);
      const r = Math.min(num(a.rx, num(a.ry)), w / 2, h / 2);
      if (r > 0) return P.FromSVGString(
        `M${x + r} ${y}H${x + w - r}A${r} ${r} 0 0 1 ${x + w} ${y + r}V${y + h - r}A${r} ${r} 0 0 1 ${x + w - r} ${y + h}` +
        `H${x + r}A${r} ${r} 0 0 1 ${x} ${y + h - r}V${y + r}A${r} ${r} 0 0 1 ${x + r} ${y}Z`);
      p.rect(x, y, w, h);
    } else throw new Error(`outline: unsupported <${tag}>`);
    return p;
  }

  const cap = { round: P.StrokeCap.ROUND, square: P.StrokeCap.SQUARE, butt: P.StrokeCap.BUTT };
  const join = { round: P.StrokeJoin.ROUND, bevel: P.StrokeJoin.BEVEL, miter: P.StrokeJoin.MITER };

  // svg: a symbol from icons/source.mjs. Returns an SVG with one filled path.
  return function outline(svg, color = "#2e3436") {
    const root = attrsOf(svg.match(/<svg([^>]*)>/)[1]);
    const out = P.NewPath();
    for (const m of svg.matchAll(/<(path|circle|ellipse|rect|line)\b([^>]*?)\/?>/g)) {
      const a = { ...root, ...attrsOf(m[2]) };
      const filled = a.fill && a.fill !== "none";
      const stroked = a.stroke && a.stroke !== "none";
      if (filled) {
        const f = shape(m[1], a);
        out.op(f, P.PathOp.UNION);
        f.delete();
      }
      if (stroked) {
        const s = shape(m[1], a);
        s.stroke({
          width: num(a["stroke-width"], 1),
          cap: cap[a["stroke-linecap"]] ?? P.StrokeCap.BUTT,
          join: join[a["stroke-linejoin"]] ?? P.StrokeJoin.MITER,
        });
        out.op(s, P.PathOp.UNION);
        s.delete();
      }
    }
    out.simplify();
    // Skia's boolean ops return even-odd paths; SVG's default rule is non-zero.
    const rule = out.getFillType().value === P.FillType.EVENODD.value ? ' fill-rule="evenodd"' : "";
    const d = out.toSVGString().replace(/(\d+\.\d{3})\d+/g, "$1");
    out.delete();
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${root.viewBox}"><path fill="${color}"${rule} d="${d}"/></svg>`;
  };
}
