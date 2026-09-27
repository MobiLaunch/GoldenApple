// Context menus and menu-bar menus: glass panels with submenus, keyboard
// navigation, the confirmation blink on selection and spring open/close.
import { h, sym, animate, wait } from "./util.js";

let chain = [];          // open menus, root first
let onRootClose = null;

/**
 * items: [{ label, icon, kbd, action, disabled, submenu, hero, checked }, "-", { header }, { tags: [...] }]
 * opts:  { x, y, onClose, origin }
 */
export function openMenu(items, opts = {}) {
  closeMenus(true);
  onRootClose = opts.onClose ?? null;
  const m = buildMenu(items, 0);
  m._openedAt = performance.now();
  place(m, opts.x, opts.y);
  animate(m, [{ opacity: 0, transform: "scale(.94)" }, { opacity: 1, transform: "scale(1)" }], "popover");
  return m;
}

export function closeMenus(immediate = false) {
  const menus = chain.splice(0);
  const cb = onRootClose; onRootClose = null;
  menus.forEach((m) => {
    if (immediate) return m.remove();
    m.style.pointerEvents = "none";
    m.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 140, easing: "ease-out", fill: "forwards" }).finished.then(() => m.remove());
  });
  if (menus.length) cb?.();
}
export const menuOpen = () => chain.length > 0;

function buildMenu(items, depth) {
  const m = h("div.menu.glass-menu", { role: "menu" });
  m.dataset.depth = depth;
  for (const it of items) {
    if (it === "-") { m.append(h("div.sep")); continue; }
    if (it.header) { m.append(h("div.header", it.header)); continue; }
    if (it.tags) {
      m.append(h("div.tags", it.tags.map((c) => h("i", { style: { background: c } }))));
      continue;
    }
    const row = h("div.item", { role: "menuitem" },
      it.icon !== undefined || items.some((x) => x.icon || x.checked !== undefined) ? h("span.ico", it.checked ? sym("checkmark") : it.icon ? (it.icon instanceof Node ? it.icon : sym(it.icon)) : "") : null,
      h("span.label", it.label),
      it.kbd ? h("span.kbd", it.kbd) : null,
      it.submenu ? h("span.chev", sym("chevron-right")) : null);
    if (it.hero) row.classList.add("hero");
    if (it.disabled) row.classList.add("disabled");
    row._item = it;
    row.addEventListener("mouseenter", () => highlight(m, row));
    // Press-drag-release selection works, but not a release from the click that opened the menu.
    row.addEventListener("mouseup", () => { if (performance.now() - chain[0]._openedAt > 220) activate(row); });
    m.append(row);
  }
  m.addEventListener("mouseleave", () => { if (!m._sub) highlight(m, null); });
  m.addEventListener("contextmenu", (e) => e.preventDefault());
  m.addEventListener("mousedown", (e) => e.stopPropagation());
  document.getElementById("desktop").append(m);
  chain.push(m);
  return m;
}

function place(m, x, y, alt) {
  const r = m.getBoundingClientRect();
  if (x + r.width > innerWidth - 6) x = alt != null ? alt - r.width : innerWidth - r.width - 6;
  if (y + r.height > innerHeight - 6) y = Math.max(34, innerHeight - r.height - 6);
  m.style.left = `${Math.max(6, x)}px`;
  m.style.top = `${y}px`;
}

let subTimer = 0;
function highlight(m, row) {
  m.querySelectorAll(":scope > .item.hl").forEach((r) => r !== row && r.classList.remove("hl"));
  if (!row || row.classList.contains("disabled")) return;
  row.classList.add("hl");
  clearTimeout(subTimer);
  const depth = +m.dataset.depth;
  if (m._sub && m._subRow !== row) closeFrom(depth + 1), (m._sub = null);
  if (row._item.submenu && m._subRow !== row) subTimer = setTimeout(() => openSub(m, row), 110);
}

function openSub(m, row) {
  closeFrom(+m.dataset.depth + 1);
  const r = row.getBoundingClientRect();
  const sub = buildMenu(row._item.submenu, +m.dataset.depth + 1);
  place(sub, r.right + 2, r.top - 6, r.left - 2);
  sub.style.transformOrigin = "top left";
  animate(sub, [{ opacity: 0, transform: "scale(.96)" }, { opacity: 1, transform: "scale(1)" }], "popover");
  m._sub = sub; m._subRow = row;
}

function closeFrom(depth) {
  chain.splice(depth).forEach((s) => s.remove());
  const parent = chain[depth - 1];
  if (parent) { parent._sub = null; parent._subRow = null; }
}

async function activate(row) {
  const it = row._item;
  if (it.disabled || it.submenu) return;
  // The system-wide "blink" that confirms a menu choice.
  row.classList.remove("hl"); await wait(60); row.classList.add("hl"); await wait(60);
  closeMenus();
  it.action?.();
}

// Keyboard navigation for the deepest open menu.
addEventListener("keydown", (e) => {
  if (!chain.length) return;
  const m = chain[chain.length - 1];
  const rows = [...m.querySelectorAll(":scope > .item:not(.disabled)")];
  const cur = rows.findIndex((r) => r.classList.contains("hl"));
  if (e.key === "Escape") { closeMenus(); e.preventDefault(); }
  else if (e.key === "ArrowDown") { highlight(m, rows[(cur + 1) % rows.length]); e.preventDefault(); }
  else if (e.key === "ArrowUp") { highlight(m, rows[(cur - 1 + rows.length) % rows.length]); e.preventDefault(); }
  else if (e.key === "ArrowRight" && rows[cur]?._item.submenu) { openSub(m, rows[cur]); highlight(chain.at(-1), chain.at(-1).querySelector(".item")); }
  else if (e.key === "ArrowLeft" && chain.length > 1) { closeFrom(chain.length - 1); }
  else if (e.key === "Enter" && rows[cur]) { activate(rows[cur]); e.preventDefault(); }
  else return;
  e.stopPropagation();
}, true);

addEventListener("mousedown", () => closeMenus());
addEventListener("blur", () => closeMenus());
