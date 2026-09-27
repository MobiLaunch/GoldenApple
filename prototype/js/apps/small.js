// Terminal, Calculator and Notes.
import { h, sym, state } from "../util.js";
import { createWindow, pill, tb } from "../wm.js";
import { registerApp, launch, APPS } from "../apps.js";
import * as fs from "../vfs.js";

// ------------------------------------------------------------------ Terminal
const FETCH = [
  ["      ▟▙   ▟▙      ", "golden@golden-gate"],
  ["   ───██───██───   ", "──────────────────"],
  ["  ╱   ██▀▀▀██   ╲  ", "OS      Golden Gate 27 (x86_64)"],
  [" ╱    ██▀▀▀██    ╲ ", "Kernel  6.18.4-gg1"],
  ["╱     ██▀▀▀██     ╲", "WM      Hyprland 0.51"],
  ["══════██═════██════", "Shell   Quickshell · zsh 5.9"],
  ["      ██     ██    ", "Theme   Liquid Glass [light]"],
  ["      ██     ██    ", "Font    Inter Variable 13"],
];
function openTerminal() {
  let cwd = `/Users/${fs.USER}`;
  const out = h("div");
  const input = h("input", { spellcheck: false, autocomplete: "off" });
  const promptEl = () => h("span", h("span.p", `${fs.USER}@golden-gate`), " ", h("span.d", cwd.replace(`/Users/${fs.USER}`, "~") || "/"), " % ");
  const line = h("div", promptEl(), input);
  const term = h("div.term", out, line);
  const win = createWindow({ app: "terminal", w: 640, h: 400, noToolbar: true, className: "terminal", content: [h("div.tbar", { "data-drag": "" }, `${fs.USER} — zsh — 80×24`), term] });
  term.addEventListener("mousedown", () => setTimeout(() => input.focus()));
  const print = (...x) => out.append(h("div", ...x));
  print(h("span.dim", "Last login: Sat Sep 26 21:20:04 on ttys000"));
  const history = []; let hi = 0;
  const cmds = {
    help: () => print("ggfetch  ls  cd  pwd  open <app>  theme <light|dark>  date  uname  echo  clear  whoami"),
    ls: () => { const n = fs.resolve(cwd); print((n?.children ?? []).map((c) => c.kind === "folder" ? h("span.d", c.name + "/  ") : c.name + "  ")); },
    cd: (a = `/Users/${fs.USER}`) => {
      const p = a === ".." ? fs.parentOf(cwd) : a.startsWith("/") ? a : a === "~" ? `/Users/${fs.USER}` : fs.join(cwd, a);
      fs.resolve(p)?.children ? (cwd = p) : print(`cd: no such file or directory: ${a}`);
    },
    pwd: () => print(cwd), whoami: () => print(fs.USER), date: () => print(new Date().toString()),
    uname: () => print("Linux golden-gate 6.18.4-gg1 #1 SMP PREEMPT_DYNAMIC x86_64 GNU/Linux"),
    echo: (...a) => print(a.join(" ")), clear: () => out.replaceChildren(),
    ggfetch: () => FETCH.forEach(([art, info]) => print(h("span.gold", art), "  ", info.includes("@") ? h("span.p", info) : info)),
    neofetch: () => cmds.ggfetch(), fastfetch: () => cmds.ggfetch(),
    theme: (m) => (m === "dark" || m === "light" ? (state.theme = m) : print("usage: theme light|dark")),
    open: (a = "") => { const id = Object.keys(APPS).find((k) => APPS[k].name.toLowerCase() === a.toLowerCase() || k === a.toLowerCase()); id ? launch(id) : print(`open: unknown application: ${a}`); },
  };
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowUp" && history.length) { hi = Math.max(0, hi - 1); input.value = history[hi]; e.preventDefault(); }
    if (e.key !== "Enter") return;
    const raw = input.value.trim(); input.value = "";
    print(promptEl(), raw);
    if (raw) { history.push(raw); hi = history.length; }
    const [c, ...args] = raw.split(/\s+/);
    if (c) (cmds[c] ?? (() => print(`zsh: command not found: ${c}`)))(...args);
    line.firstChild.replaceWith(promptEl());
    win.content.scrollTop = win.content.scrollHeight;
  });
  setTimeout(() => input.focus(), 50);
  return win;
}

// ------------------------------------------------------------------ Calculator
function openCalculator() {
  let cur = "0", acc = null, op = null, fresh = true;
  const disp = h("div.disp", "0");
  const fmt = (n) => { const s = String(+(+n).toPrecision(10)); return s.length > 10 ? (+n).toExponential(4) : s; };
  const apply = (a, b, o) => ({ "+": a + b, "−": a - b, "×": a * b, "÷": b === 0 ? NaN : a / b }[o]);
  const keys = [["AC", "fn"], ["±", "fn"], ["%", "fn"], ["÷", "op"], ["7"], ["8"], ["9"], ["×", "op"], ["4"], ["5"], ["6"], ["−", "op"], ["1"], ["2"], ["3"], ["+", "op"], ["0", "zero"], ["."], ["=", "op"]];
  const btns = keys.map(([k, cls = ""]) => h("button", { className: cls, on: { click: () => press(k) } }, k));
  function press(k) {
    if (/\d/.test(k)) { cur = fresh || cur === "0" ? k : (cur + k).slice(0, 10); fresh = false; }
    else if (k === ".") { if (fresh) cur = "0"; if (!cur.includes(".")) cur += "."; fresh = false; }
    else if (k === "AC") { cur = "0"; acc = null; op = null; fresh = true; }
    else if (k === "±") cur = String(-cur);
    else if (k === "%") cur = String(cur / 100);
    else if (k === "=") { if (op != null) { cur = String(apply(acc, +cur, op)); acc = null; op = null; fresh = true; } }
    else { if (op != null && !fresh) cur = String(apply(acc, +cur, op)); acc = +cur; op = k; fresh = true; }
    disp.textContent = isNaN(+cur) ? "Error" : fmt(cur);
    btns.forEach((b) => b.classList.toggle("on", b.textContent === op && fresh));
  }
  const win = createWindow({ app: "calculator", w: 250, h: 420, noToolbar: true, className: "calc", content: h("div.body", { "data-drag": "" }, disp, h("div.keys", btns)) });
  win.el.querySelectorAll(".resize").forEach((r) => r.remove());
  win.el.tabIndex = 0;
  win.el.addEventListener("keydown", (e) => {
    const map = { "*": "×", "/": "÷", "-": "−", Enter: "=", Escape: "AC", Backspace: "AC" };
    const k = map[e.key] ?? e.key;
    if (keys.some(([x]) => x === k)) { press(k); e.preventDefault(); }
  });
  setTimeout(() => win.el.focus(), 50);
  return win;
}

// ------------------------------------------------------------------ Notes
const NOTES = [
  { t: "Golden Gate roadmap", b: "Golden Gate roadmap\n\n• Liquid Glass compositor shader (refraction + specular)\n• Native Files app in GTK4\n• Quickshell Control Center parity\n• Genie minimise in Hyprland plugin\n• Installer (Calamares) theme" },
  { t: "Motion notes", b: "Motion notes\n\nEverything uses springs described by response + damping.\nsmooth 0.50/1.00 — navigation\nsnappy 0.40/0.86 — controls\nbouncy 0.50/0.70 — playful moments\npopover 0.38/0.78 — menus and Control Center" },
  { t: "Groceries", b: "Groceries\n\n- Sourdough\n- Dungeness crab\n- Irish coffee supplies" },
];
function openNotes() {
  let cur = 0;
  const list = h("div");
  // The first line of a note is its title (styled with ::first-line).
  const ta = h("div.note-edit", { contentEditable: "plaintext-only", spellcheck: false });
  Object.defineProperty(ta, "value", { get: () => ta.innerText, set: (v) => { ta.textContent = v; } });
  const renderList = () => list.replaceChildren(h("div.sec", "Today"), ...NOTES.map((n, i) => h("div.note-row", { className: `note-row ${i === cur ? "sel" : ""}`, on: { click: () => { cur = i; ta.value = n.b; renderList(); } } }, h("b", n.b.split("\n")[0] || "New Note"), h("small", n.b.split("\n").filter(Boolean)[1] ?? "No additional text"))));
  ta.addEventListener("input", () => { NOTES[cur].b = ta.value; renderList(); });
  ta.value = NOTES[0].b;
  renderList();
  return createWindow({
    app: "notes", w: 820, h: 520, sidebar: list, sidebarWidth: 230, className: "notes", content: [h("div.note-date", "September 26, 2026 at 9:41 PM"), ta],
    toolbar: [h("div.grow"), pill(tb("list"), tb("grid")), pill(tb("doc", { title: "New note", click: () => { NOTES.unshift({ b: "" }); cur = 0; ta.value = ""; renderList(); ta.focus(); } })), pill(tb("checkmark"), tb("photo"), tb("lock")), h("label.pill.search", sym("search"), h("input", { placeholder: "Search" }))],
  });
}

registerApp("terminal", openTerminal, { Shell: [{ label: "New Window", kbd: "⌘N", action: () => launch("terminal", "new") }, { label: "New Tab", kbd: "⌘T" }, "-", { label: "Close Window", kbd: "⇧⌘W" }] });
registerApp("calculator", openCalculator, { Convert: [{ label: "Recent Conversions", disabled: true }, "-", { label: "Currency" }, { label: "Length" }, { label: "Temperature" }] });
registerApp("notes", openNotes, { Format: [{ label: "Title", kbd: "⇧⌘T" }, { label: "Heading", kbd: "⇧⌘H" }, { label: "Body", kbd: "⇧⌘B" }, "-", { label: "Checklist", kbd: "⇧⌘L" }] });
