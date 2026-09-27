#!/usr/bin/env node
// End-to-end smoke test for the reference shell. Serves prototype/, drives it
// with Playwright through the main flows and fails on any page error.
//
//   npm run test:ui                     (SHOTS=dir to also save screenshots)
import { createServer } from "node:http";
import { readFile, mkdir } from "node:fs/promises";
import { extname, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png" };
const server = createServer(async (req, res) => {
  let path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (path.endsWith("/")) path += "index.html";
  try {
    const body = await readFile(join(ROOT, path));
    res.writeHead(200, { "content-type": TYPES[extname(path)] ?? "application/octet-stream" }).end(body);
  } catch { res.writeHead(404).end(); }
}).listen(0);
const base = `http://localhost:${server.address().port}/`;
const shots = process.env.SHOTS;
if (shots) await mkdir(shots, { recursive: true });

const browser = await chromium.launch({ args: ["--ignore-certificate-errors"] });
const failures = [];
async function scenario(name, query, steps) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error" && !/fonts\.g|ERR_CERT|net::ERR/.test(m.text())) errors.push(m.text()); });
  try {
    await page.goto(base + query, { waitUntil: "load" });
    await page.waitForTimeout(700);
    await steps(page);
    await page.waitForTimeout(400);
    if (shots) await page.screenshot({ path: join(shots, `${name}.png`) });
  } catch (e) { errors.push(`step failed: ${e.message.split("\n")[0]}`); }
  await page.close();
  console.log(`${errors.length ? "✗" : "✓"} ${name}${errors.length ? `\n    ${errors.join("\n    ")}` : ""}`);
  if (errors.length) failures.push(name);
}
const wait = (p, ms = 500) => p.waitForTimeout(ms);

await scenario("boot, lock and unlock", "?boot", async (p) => {
  await wait(p, 2600);
  await p.keyboard.type("wrong"); await p.keyboard.press("Enter"); await wait(p);
  await p.keyboard.type("golden"); await p.keyboard.press("Enter"); await wait(p, 1500);
  if (await p.$("#lock")) throw new Error("still locked");
});
for (const app of ["files", "photos", "settings", "browser", "mail", "messages", "music", "calendar", "maps", "weather", "store", "notes", "terminal", "calculator"]) {
  await scenario(`open ${app}`, `?quiet&open=${app}`, async (p) => { await wait(p, 600); if (!(await p.$(".win"))) throw new Error("no window"); });
}
await scenario("control center and details", "?quiet&open=", async (p) => {
  await p.click('#menubar .mb-item:has(use[href="#sym-control-center"])'); await wait(p, 700);
  await p.click("#cc [title=Bluetooth]", { button: "right" }); await wait(p, 700);
  await p.click(".cc-back"); await wait(p, 500);
  await p.click("#cc .cc-slider .t >> nth=0"); await wait(p, 600);
});
await scenario("spotlight search and calculator", "?quiet&open=", async (p) => {
  await p.keyboard.press("Control+Space"); await p.keyboard.type("12*(3+4)"); await wait(p);
  const txt = await p.textContent("#spotlight .results");
  if (!txt.includes("84")) throw new Error("calculator result missing");
  await p.keyboard.press("Escape"); await wait(p);
  await p.click('.dock-item[data-app="launcher"]'); await wait(p, 800);
});
await scenario("menus and context menus", "?quiet&open=files", async (p) => {
  await p.click("#menubar .mb-item >> nth=2"); await wait(p);
  await p.hover("#menubar .mb-item >> nth=3"); await wait(p);
  await p.keyboard.press("Escape");
  await p.click(".files .cell >> nth=3", { button: "right" }); await wait(p);
  await p.hover(".menu .item:has-text('Open With')"); await wait(p);
  await p.keyboard.press("Escape");
});
await scenario("files: folder, rename, quick look, trash", "?quiet&open=files", async (p) => {
  await p.click(".side-row:has-text('Documents')"); await wait(p);
  await p.keyboard.press("Control+Shift+N"); await wait(p);
  await p.keyboard.type("Launch Plans"); await p.keyboard.press("Enter"); await wait(p);
  if (!(await p.$(".cell:has-text('Launch Plans')"))) throw new Error("folder not created");
  await p.click(".cell:has-text('Roadmap.md')"); await p.keyboard.press(" "); await wait(p, 700);
  if (!(await p.$(".ql"))) throw new Error("no quick look");
  await p.keyboard.press(" "); await wait(p);
  await p.keyboard.press("Control+Backspace"); await wait(p, 900);
  if (await p.$(".cell:has-text('Roadmap.md')")) throw new Error("not trashed");
  for (const view of ["List", "Columns", "Gallery", "Icons"]) { await p.click(`.toolbar .tb[data-tip="${view}"], .toolbar .tb[title="${view}"]`); await wait(p, 300); }
});
await scenario("windows: minimise, restore, mission control, tiling", "?quiet&open=files,notes", async (p) => {
  await p.click(".notes .lights .min"); await wait(p, 900);
  await p.click(".dock-item.mini"); await wait(p, 800);
  await p.keyboard.press("Control+ArrowUp"); await wait(p, 900);
  await p.keyboard.press("Escape"); await wait(p, 1200);                 // let Mission Control settle
  const t = await p.$(".notes .toolbar"); const b = await t.boundingBox();
  await p.mouse.move(b.x + 20, b.y + 20); await p.mouse.down(); await p.mouse.move(2, 400, { steps: 8 }); await p.mouse.up(); await wait(p, 800);
  if (parseFloat(await p.$eval(".win.notes", (e) => e.style.left)) > 20) throw new Error("window did not snap to the left half");
});
await scenario("messages: send", "?quiet&open=messages", async (p) => {
  await p.fill(".cm-field input", "Hello from Golden Gate"); await p.keyboard.press("Enter"); await wait(p, 400);
  if (!(await p.textContent(".messages")).includes("Hello from Golden Gate")) throw new Error("message not sent");
});
await scenario("music: play album", "?quiet&open=music", async (p) => {
  await p.hover(".album >> nth=0"); await p.click(".play-over >> nth=0"); await wait(p, 600);
});
await scenario("maps: search and directions", "?quiet&open=maps", async (p) => {
  await p.fill(".maps-side input", "alcatraz"); await p.keyboard.press("Enter"); await wait(p, 900);
  await p.click(".pc-main"); await wait(p, 1200);
});
await scenario("store: get app", "?quiet&open=store", async (p) => {
  await p.click(".get >> nth=0"); await wait(p, 1500);
});
await scenario("appearance: dark, accent, glass, icons", "?quiet&open=settings", async (p) => {
  await p.evaluate(() => { const s = window.gg.state; s.theme = "dark"; s.accent = "purple"; s.glass = "tinted"; s.iconStyle = "clear"; });
  await wait(p, 900);
  for (const pane of ["Wi-Fi", "Bluetooth", "Notifications", "Focus", "General", "Accessibility", "Keyboard", "Wallpaper"]) { await p.click(`.settings .side-row:has-text("${pane}")`); await wait(p, 200); }
});

await browser.close();
server.close();
if (failures.length) { console.error(`\n${failures.length} scenario(s) failed`); process.exit(1); }
console.log("\nall scenarios passed");
