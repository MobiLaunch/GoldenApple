#!/usr/bin/env node
// Regenerates docs/screenshots/*.jpg from the reference shell.
//
//   npm run screenshots
import { mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { serve } from "./serve.mjs";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "docs", "screenshots");
await mkdir(OUT, { recursive: true });
const server = serve();
const browser = await chromium.launch();
const wait = (p, ms = 500) => p.waitForTimeout(ms);

const SCENES = {
  "files-light": ["?quiet&open=files", async (p) => { await p.click(".cell:has-text('Photos')"); }],
  "files-dark-menu": ["?quiet&theme=dark&open=files", async (p) => { await p.click(".cell:has-text('Maps')", { button: "right" }); await wait(p); await p.hover(".menu .item:has-text('Open With')"); }],
  "control-center": ["?quiet&open=photos&cc=1", null],
  "control-center-detail": ["?quiet&open=music&cc=1", async (p) => { await p.click("#cc [title=Bluetooth]", { button: "right" }); }],
  "spotlight": ["?quiet&open=files", async (p) => { await p.keyboard.press("Control+Space"); await p.keyboard.type("ma"); }],
  "dock-magnify": ["?quiet&open=files,music", async (p) => { const b = await (await p.$('.dock-item[data-app="photos"]')).boundingBox(); await p.mouse.move(b.x + b.width / 2, b.y + b.height / 2); }],
  "photos": ["?quiet&open=photos", null],
  "settings-dark": ["?quiet&theme=dark&open=settings", async (p) => { await p.click('.settings .side-row:has-text("Appearance")'); }],
  "mission-control": ["?quiet&open=files,photos,notes,music", async (p) => { await p.keyboard.press("Control+ArrowUp"); }],
  "lock": ["?lock", null],
  "mail": ["?quiet&open=mail", null],
  "music": ["?quiet&theme=dark&open=music", null],
  "maps": ["?quiet&open=maps", async (p) => { await p.fill(".maps-side input", "alcatraz"); await p.keyboard.press("Enter"); await wait(p, 600); await p.click(".pc-main"); await wait(p, 1200); }],
  "weather": ["?quiet&open=weather", null],
  "calendar": ["?quiet&open=calendar", null],
  "messages-dark": ["?quiet&theme=dark&open=messages", null],
};

for (const [name, [query, steps]] of Object.entries(SCENES)) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(server.base + query, { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);
  await wait(page, 1000);
  if (steps) await steps(page);
  await wait(page, 1100);
  await page.screenshot({ path: join(OUT, `${name}.jpg`), type: "jpeg", quality: 86 });
  await page.close();
  console.log(`docs/screenshots/${name}.jpg`);
}
await browser.close();
server.close();
