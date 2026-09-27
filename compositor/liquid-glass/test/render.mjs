#!/usr/bin/env node
// Compiles liquid-glass.frag as GLSL ES 1.00 (WebGL 1 is just as strict as the
// compositor's GLES) and renders it over a blurred desktop the way the plugin
// will: sharp screen outside the glass shapes, the shader inside them.
//
//   node compositor/liquid-glass/test/render.mjs [shader.frag] [out.png]
//
// Fails on any compile or link error. Writes a preview when out.png is given.
import { chromium } from "playwright";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const shader = resolve(process.argv[2] ?? join(here, "..", "liquid-glass.frag"));
const out = process.argv[3];
const files = { "/harness.html": join(here, "harness.html"), "/backdrop.jpg": join(here, "..", "..", "..", "docs", "screenshots", "photos.jpg") };
const server = createServer((req, res) => {
  const f = files[req.url];
  if (!f) return res.writeHead(404).end();
  res.writeHead(200, { "content-type": extname(f) === ".html" ? "text/html" : "image/jpeg" }).end(readFileSync(f));
}).listen(0);

// Shapes like the shell's: Control Center modules, a round button, the Dock, a tinted panel.
const shapes = [
  { rect: [1060, 40, 360, 120], radius: 32 },
  { rect: [1060, 180, 110, 110], radius: 55 },
  { rect: [1190, 180, 230, 110], radius: 28 },
  { rect: [380, 790, 680, 90], radius: 30 },
  { rect: [520, 330, 400, 220], radius: 26, tint: [0.02, 0.03, 0.05, 0.25] },
];

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
await page.goto(`http://localhost:${server.address().port}/harness.html`);
const result = await page.evaluate(([src, shapes]) => window.render(src, shapes), [readFileSync(shader, "utf8"), shapes]);
if (!result.error && out) await page.screenshot({ path: out });
await browser.close();
server.close();

if (result.error) {
  console.error(`${shader}: failed to compile\n${result.error.trim()}`);
  process.exit(1);
}
console.log(`${shader}: compiles and renders${out ? ` (preview: ${out})` : ""}`);
