// Spotlight: glass search capsule with category buttons, app/file/action
// results and quick actions. Also serves as the "Apps" launcher.
import { h, sym, appIcon, state, bus, animate } from "./util.js";
import { APPS, launch } from "./apps.js";
import * as fs from "./vfs.js";

const ACTIONS = [
  ["Toggle Dark Mode", "contrast", () => (state.theme = state.theme === "dark" ? "light" : "dark")],
  ["Take Screenshot", "screenshot", () => bus.emit("screenshot")],
  ["New Note", "doc", () => launch("notes")],
  ["Start 5 Minute Timer", "timer", () => bus.emit("notify", { app: "calendar", title: "Timer", body: "5-minute timer started." })],
  ["Change Wallpaper", "wallpaper", () => launch("settings", "wallpaper")],
  ["Open Terminal Here", "apps", () => launch("terminal")],
  ["Turn Wi-Fi Off", "wifi", () => (state.wifi = false)],
  ["Lock Screen", "lock", () => bus.emit("sleep")],
];

export function initSpotlight() {
  const input = h("input", { placeholder: "Spotlight Search", spellcheck: false });
  const results = h("div.results.glass-menu");
  const cats = { apps: ["apps", "Applications"], files: ["folder", "Files"], actions: ["sparkles", "Actions"], clipboard: ["doc", "Clipboard"] };
  let cat = null, sel = 0, items = [];
  const catBtns = Object.entries(cats).map(([k, [icon, title]]) => h("button.cat.glass-regular", { title, "data-cat": k, on: { click: () => { cat = cat === k ? null : k; update(); input.focus(); } } }, sym(icon)));
  const field = h("div.field.glass-regular", sym("search"), input);
  const wrap = h("div.wrap", h("div.bar", field, ...catBtns), results);
  const root = h("div#spotlight", { hidden: true }, wrap);
  document.getElementById("desktop").append(root);
  root.addEventListener("mousedown", (e) => { if (e.target === root) close(); e.stopPropagation(); });

  function update() {
    const q = input.value.trim().toLowerCase();
    catBtns.forEach((b) => b.classList.toggle("on", b.dataset.cat === cat));
    input.placeholder = cat ? `Search ${cats[cat][1]}` : "Spotlight Search";
    items = [];
    results.classList.remove("grid-mode");
    // Apps with an empty query: the launcher's icon grid.
    if (cat === "apps" && !q) {
      results.classList.add("grid-mode");
      const apps = Object.entries(APPS).filter(([k]) => k !== "launcher");
      items = apps.map(([k, a]) => ({ label: a.name, run: () => launch(k) }));
      sel = -1;
      results.replaceChildren(...apps.map(([k, a], i) => h("button.app-tile", { on: { click: () => run(i) } }, appIcon(k), h("span", a.name))));
      [...results.children].forEach((c, i) => animate(c, [{ opacity: 0, transform: "scale(.6)" }, { opacity: 1, transform: "none" }], "bouncy", { delay: i * 16 }));
      return;
    }
    const add = (group, list) => list.length && items.push({ group }, ...list);
    // Calculator: arithmetic in the field shows the answer as the top hit.
    if (!cat && /^[\d\s.+\-*/()%^]+$/.test(q) && /\d\s*[-+*/%^]\s*[\d(]/.test(q)) {
      try {
        const v = Function(`"use strict"; return (${q.replace(/\^/g, "**")})`)();
        if (Number.isFinite(v)) add("Calculator", [{ icon: h("span.ico.calc", sym("calculator")), label: `= ${+v.toPrecision(12)}`, sub: q, run: () => navigator.clipboard?.writeText(String(v)).catch(() => {}) }]);
      } catch {}
    }
    if (!cat || cat === "apps") add("Applications", Object.entries(APPS).filter(([k, a]) => k !== "launcher" && (!q || a.name.toLowerCase().includes(q))).slice(0, cat ? 20 : q ? 5 : 0)
      .map(([k, a]) => ({ icon: appIcon(k), label: a.name, sub: "Application", run: () => launch(k) })));
    if ((!cat && q) || cat === "files") add("Files", [...fs.walk()].filter(([n]) => n.kind !== "app" && (!q || n.name.toLowerCase().includes(q))).slice(0, 6)
      .map(([n, p]) => ({ icon: appIcon(fs.iconFor(n)), label: n.name, sub: fs.parentOf(p).split("/").pop() || "System HD", run: () => launch("files", n.kind === "folder" ? p : fs.parentOf(p)) })));
    if ((!cat && q) || cat === "actions") add("Actions", ACTIONS.filter(([l]) => !q || l.toLowerCase().includes(q)).map(([l, i, run]) => ({ icon: h("span.ico", sym(i)), label: l, sub: "Quick Action", run })));
    if (cat === "clipboard") add("Clipboard", ["hyprctl reload", "https://github.com/mobilaunch/goldenapple", "Liquid Glass rim: 135deg"].map((c) => ({ icon: h("span.ico", sym("doc")), label: c, sub: "Copied today", run: () => {} })));
    if (!cat && q && !items.length) add("Search", [{ icon: h("span.ico", sym("globe")), label: `Search the web for “${input.value}”`, sub: "Web", run: () => launch("browser") }]);
    sel = items.findIndex((x) => !x.group);
    results.replaceChildren(...items.map((it, i) => it.group ? h("div.group", it.group) :
      h("div.res", { className: `res ${i === sel ? "hl" : ""}`, on: { mouseenter: () => highlight(i), click: () => run(i) } }, it.icon, it.label, h("span.sub", it.sub))));
  }
  function highlight(i) {
    if (results.classList.contains("grid-mode")) return; sel = i; [...results.children].forEach((c, j) => c.classList.toggle("hl", j === i)); results.children[i]?.scrollIntoView({ block: "nearest" }); }
  function run(i) { const it = items[i]; if (!it || it.group) return; close(); it.run(); }

  input.addEventListener("input", update);
  input.addEventListener("keydown", (e) => {
    const idx = items.map((x, i) => (x.group ? -1 : i)).filter((i) => i >= 0);
    const p = idx.indexOf(sel);
    if (e.key === "ArrowDown") { highlight(idx[(p + 1) % idx.length]); e.preventDefault(); }
    else if (e.key === "ArrowUp") { highlight(idx[(p - 1 + idx.length) % idx.length]); e.preventDefault(); }
    else if (e.key === "Enter") run(sel);
    else if (e.key === "Escape") close();
    else if (e.key === "Tab") { const keys = Object.keys(cats); cat = keys[(keys.indexOf(cat) + 1) % keys.length]; update(); e.preventDefault(); }
  });

  let isOpen = false;
  function open(text = "", category = null) {
    bus.emit("overlays:close");
    isOpen = true; root.hidden = false; cat = category === "assistant" ? null : category;
    input.value = text;
    if (category === "assistant") input.placeholder = "Ask anything…";
    update();
    input.focus();
    animate(field, [{ opacity: 0, transform: "scale(.86)" }, { opacity: 1, transform: "none" }], "bouncy");
    catBtns.forEach((b, i) => animate(b, [{ opacity: 0, transform: "translateX(-40px) scale(.6)" }, { opacity: 1, transform: "none" }], "bouncy", { delay: 30 + i * 30 }));
    animate(results, [{ opacity: 0, transform: "translateY(-6px)" }, { opacity: 1, transform: "none" }], "popover");
  }
  async function close() {
    if (!isOpen) return;
    isOpen = false;
    await wrap.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(.96)" }], { duration: 140, easing: "ease-in" }).finished;
    if (!isOpen) root.hidden = true;
  }
  bus.on("spotlight", (text, category) => open(text, category));
  bus.on("overlays:close", () => isOpen && close());
  return { open, close, toggle: () => (isOpen ? close() : open()) };
}
