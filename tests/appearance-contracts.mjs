// Asset pipeline and battery-state regressions. Run after npm run build.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { orchardSymbols } from "../icons/orchard-symbols.mjs";

const text = (f) => readFileSync(new URL("../" + f, import.meta.url), "utf8");
const has = (f) => existsSync(new URL("../" + f, import.meta.url));
const names = ["chevron-left", "chevron-right", "search", "wifi", "bluetooth", "moon", "play", "pause",
  "house", "bell", "plus", "minus", "folder", "lock", "clock", "cloud",
  "globe", "headphones", "settings", "trash-2", "download", "share-2", "list", "grid-2x2",
  "volume-1", "volume-2", "volume-x", "skip-back", "skip-forward",
  "chevron-up", "chevrons-up-down", "arrow-left", "arrow-right",
  "arrow-up", "rotate-cw", "rotate-ccw"];

test("OrchardKit Xcode artboards are normalized into usable Qt SVG glyphs", () => {
  const build = text("icons/build.mjs");
  assert.match(build, /import \{ orchardSymbols \} from "\.\/orchard-symbols\.mjs"/);
  const namedForGoldenGate = { "settings": "gear", "trash-2": "trash", "share-2": "share", "grid-2x2": "grid" };
  for (const name of names) {
    const key = namedForGoldenGate[name] ?? name;
    const svg = orchardSymbols[name];
    assert.ok(svg?.includes("<path"), name + " must have a drawable contour");
    assert.ok(!svg.includes('id="Notes"') && !svg.includes("3300 2200"), name + " must not ship a template artboard");
    assert.ok(/viewBox="[-.\d ]+"/.test(svg), name + " needs an explicit viewBox");
    assert.ok(has("apps/lib/assets/symbols/" + key + ".svg"), "missing app asset for " + name);
    assert.ok(has("shell/assets/symbols/" + key + ".svg"), "missing shell asset for " + name);
  }
  assert.match(build, /const unifiedSymbols = \{ \.\.\.baseSymbols \}/);
});

test("system font aliases prefer locally installed SFWindows while shipping Inter fallbacks", () => {
  const fc = text("themes/fontconfig/60-golden-gate.conf");
  const qml = text("apps/lib/theme/Theme.qml");
  const install = text("scripts/install-local-sfwindows.sh");
  for (const name of ["Golden Gate UI", "Golden Gate Display", "Golden Gate Mono"]) assert.ok(fc.includes(name));
  assert.match(qml, /fontUi: "Golden Gate UI"/);
  assert.match(qml, /fontDisplay: "Golden Gate Display"/);
  assert.match(fc, /Inter Variable/);
  assert.match(install, /fc-cache/);
  assert.doesNotMatch(install, /curl |wget |git clone/);
});

test("menu bar battery draws real green charging fill, bolt and Reduce Motion fallback", () => {
  const glyph = text("shell/components/BatteryGlyph.qml");
  const bar = text("shell/MenuBar.qml");
  const battery = text("shell/components/Battery.qml");
  assert.match(bar, /BatteryGlyph \{/);
  assert.match(bar, /full: Battery\.full/);
  assert.match(glyph, /fraction: Math\.max\(0, Math\.min\(1, level\)\)/);
  assert.match(glyph, /activeCharge: charging && !full/);
  assert.match(glyph, /activeCharge \? "#30d158"/);
  assert.match(glyph, /id: bolt/);
  assert.match(glyph, /running: glyph\.activeCharge && !glyph\.reduceMotion/);
  assert.match(battery, /device\.state === UPowerDeviceState\.FullyCharged/);
});

test("native compositor snapping is active without a frame-by-frame QML poll", () => {
  const conf = text("compositor/hyprland/hyprland.conf");
  assert.match(conf, /snap \{\s+enabled = true/);
  assert.match(conf, /window_gap = 12/);
  assert.match(conf, /monitor_gap = 12/);
  assert.match(conf, /respect_gaps = true/);
});
