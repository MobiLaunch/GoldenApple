// Files: the Finder-equivalent. Icon / list / column / gallery views, history,
// floating glass sidebar, search, context menus and the icon-size slider.
import { h, sym, appIcon, bus, animate, genArt } from "../util.js";
import { createWindow, activeWindow, pill, tb, div } from "../wm.js";
import { registerApp, launch } from "../apps.js";
import { openMenu } from "../menus.js";
import * as fs from "../vfs.js";

const HOME = `/Users/${fs.USER}`;
const SIDEBAR = [
  { rows: [["Recents", "clock", "@recents"], ["Shared", "people", "@shared"]] },
  { title: "Favourites", rows: [["Applications", "apps", "/Applications"], ["Desktop", "rectangle-fill", `${HOME}/Desktop`], ["Documents", "doc", `${HOME}/Documents`], ["Downloads", "download", `${HOME}/Downloads`], ["Pictures", "photo", `${HOME}/Pictures`], ["Music", "music", `${HOME}/Music`], ["Movies", "film", `${HOME}/Movies`]] },
  { title: "Locations", rows: [["Cloud Drive", "cloud", `${HOME}/Documents`], [fs.USER, "house", HOME], ["System HD", "drive", "/"], ["Network", "globe", "@network"]] },
  { title: "Tags", rows: [["Red", null, "@tag", "#ff453a"], ["Orange", null, "@tag", "#ff9f0a"], ["Blue", null, "@tag", "#0a84ff"], ["Green", null, "@tag", "#30d158"]] },
];
const QL_TEXT = [
  "Golden Gate brings Liquid Glass to Linux: translucent materials with a specular rim, spring motion everywhere, and a shell that feels at home on a laptop.",
  "This document is a preview rendered by Quick Look. Press Space again or Escape to close it, or use the arrow keys to preview the next item.",
  "Materials, motion and type come from one set of design tokens, so the shell, the apps and the compositor always agree.",
];
const qlPhoto = (seed) => genArt(seed, { w: 800, h: 560 });
const TAG_COLORS = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2", "#8e8e93"];

function openFiles(_id, arg) {
  const st = { path: typeof arg === "string" && /^[/@]/.test(arg) ? arg : "/Applications", view: "icons", back: [], fwd: [], sel: new Set(), query: "", iconSize: 64 };
  const sidebar = h("div");
  const title = h("div.title");
  const views = ["icons", "list", "columns", "gallery"];
  const viewBtns = Object.fromEntries(views.map((v) => [v, tb({ icons: "grid", list: "list", columns: "columns", gallery: "gallery" }[v], { title: `View as ${v}`, click: () => setView(v) })]));
  const backBtn = tb("chevron-left", { title: "Back", click: () => go(st.back.pop(), "back") });
  const fwdBtn = tb("chevron-right", { title: "Forward", click: () => go(st.fwd.pop(), "fwd") });
  const search = h("input", { placeholder: "Search", on: { input: (e) => { st.query = e.target.value.trim().toLowerCase(); render(); } } });

  const pathBar = h("div.path");
  const info = h("div.info");
  const zoomFill = h("i"), zoomKnob = h("b");
  const zoomer = h("div.zoomer", { title: "Icon size" }, zoomFill, zoomKnob);
  const statusbar = h("div.statusbar", pathBar, h("div.info-wrap", { style: { flex: 1, position: "relative", display: "flex" } }, info, zoomer));
  info.style.flex = "1";

  const body = h("div.files-body");
  const win = createWindow({
    app: "files", w: 1000, h: 600, sidebar, sidebarWidth: 200, content: body, statusbar,
    toolbar: [
      pill(backBtn, div(), fwdBtn), title, h("div.grow"),
      pill(...views.map((v) => viewBtns[v])),
      pill(tb("grid", { title: "Group", chev: true, click: (e) => groupMenu(e) })),
      pill(tb("share", { title: "Share" }), tb("tag", { title: "Tags", click: (e) => tagMenu(e) }), tb("ellipsis", { title: "Action", click: (e) => actionMenu(e) })),
      h("label.pill.search", sym("search"), search),
    ],
  });
  win.el.classList.add("files");

  function setView(v) { st.view = v; render(); }
  function go(path, how) {
    if (!path) return;
    if (how !== "back") st.back.push(st.path);
    if (how === "new") st.fwd = [];
    if (how === "back") st.fwd.push(st.path);
    st.path = path; st.sel.clear(); st.query = ""; search.value = "";
    render(true);
  }
  const navigate = (p) => go(p, "new");

  function entries() {
    if (st.query) return [...fs.walk()].filter(([n]) => n.name.toLowerCase().includes(st.query)).map(([n, p]) => ({ ...n, path: p })).slice(0, 60);
    if (st.path === "@recents") return [...fs.walk()].filter(([n]) => n.kind !== "folder" && n.kind !== "app").sort((a, b) => b[0].date - a[0].date).slice(0, 16).map(([n, p]) => ({ ...n, path: p }));
    if (st.path === "@trash") return fs.TRASH.map((c) => ({ ...c, path: `@trash/${c.name}` }));
    if (st.path.startsWith("@")) return [];
    const node = fs.resolve(st.path);
    return (node?.children ?? []).map((c) => ({ ...c, path: fs.join(st.path, c.name) })).sort((a, b) => a.name.localeCompare(b.name));
  }
  const labelFor = (p) => ({ "@recents": "Recents", "@shared": "Shared", "@network": "Network", "@tag": "Tagged", "@trash": "Trash" }[p] ?? (p === "/" ? "System HD" : p.split("/").at(-1)));

  function open(n) {
    if (n.kind === "folder") navigate(n.path);
    else if (n.kind === "app") launch(n.app);
    else if (n.kind === "image") launch("photos");
    else if (n.kind === "audio") { launch("music"); }
    else bus.emit("notify", { app: "files", title: n.name, body: "Quick Look previews arrive with the native Files app." });
  }

  function render(navigated) {
    // sidebar
    sidebar.replaceChildren(...SIDEBAR.flatMap((s) => [
      s.title ? h("div.sec", s.title) : null,
      ...s.rows.map(([label, icon, path, color]) => h("div.side-row", { className: `side-row ${path === st.path && !st.query ? "sel" : ""}`, "data-path": path.startsWith("@") ? null : path, on: { click: () => navigate(path) } },
        icon ? sym(icon) : h("i", { style: { width: "10px", height: "10px", margin: "0 3px", borderRadius: "50%", background: color } }), label)),
    ]).filter(Boolean));
    // toolbar
    title.replaceChildren(st.query ? sym("search") : appIcon(st.path === "/" ? "disk" : "folder"), st.query ? `Searching “${st.query}”` : labelFor(st.path));
    backBtn.disabled = !st.back.length; fwdBtn.disabled = !st.fwd.length;
    views.forEach((v) => viewBtns[v].classList.toggle("on", v === st.view));
    win.setTitle(labelFor(st.path));
    // content
    const list = entries();
    body.className = `files-body view-${st.view}`;
    body.style.setProperty("--icon", `${st.iconSize}px`);
    body.replaceChildren(list.length ? { icons: iconView, list: listView, columns: columnView, gallery: galleryView }[st.view](list) : h("div.empty", st.path.startsWith("@") ? "Nothing here yet" : "No items"));
    if (navigated) animate(body, [{ opacity: 0.4, transform: "translateX(6px)" }, { opacity: 1, transform: "none" }], "snappy");
    // status bar
    const crumbs = st.path.startsWith("@") ? [st.path] : ["/", ...st.path.split("/").filter(Boolean).map((_, i, a) => "/" + a.slice(0, i + 1).join("/"))];
    pathBar.replaceChildren(...crumbs.flatMap((p, i) => [i ? sym("chevron-right") : null, h("span", { style: { display: "flex", gap: "5px", alignItems: "center" }, on: { dblclick: () => navigate(p) } }, appIcon(p === "/" ? "disk" : "folder"), labelFor(p))]).filter(Boolean));
    info.textContent = `${list.length} item${list.length === 1 ? "" : "s"}${st.sel.size ? `, ${st.sel.size} selected` : ""}, 62.2 GB available`;
    const pct = (st.iconSize - 40) / (128 - 40);
    zoomFill.style.width = `${pct * 100}%`; zoomKnob.style.left = `${pct * 100}%`;
    zoomer.style.display = st.view === "icons" ? "" : "none";
  }

  // --- item interaction shared by all views
  function bindItem(el, n) {
    el.classList.toggle("sel", st.sel.has(n.path));
    el.addEventListener("mousedown", (e) => {
      if (e.button === 2 && st.sel.has(n.path)) return;
      if (!(e.metaKey || e.ctrlKey || e.shiftKey)) st.sel.clear();
      st.sel.has(n.path) && (e.metaKey || e.ctrlKey) ? st.sel.delete(n.path) : st.sel.add(n.path);
      body.querySelectorAll(".sel").forEach((x) => x.classList.remove("sel"));
      body.querySelectorAll("[data-path]").forEach((x) => st.sel.has(x.dataset.path) && x.classList.add("sel"));
      info.textContent = info.textContent.replace(/, \d+ selected|(?=, 62)/, st.sel.size ? `, ${st.sel.size} selected` : "");
      e.stopPropagation();
      if (e.button === 0 && !n.path.startsWith("/Applications/")) armDrag(e, el, n);
    });
    el.addEventListener("dblclick", () => open(n));
    el.addEventListener("contextmenu", (e) => { e.preventDefault(); e.stopPropagation(); itemMenu(e, n); });
    el.dataset.path = n.path;
    return el;
  }

  function iconView(list) {
    return h("div.grid", list.map((n) => bindItem(h("div.cell", appIcon(fs.iconFor(n)), h("span.name", n.kind === "app" ? n.name : n.name)), n)));
  }
  function listView(list) {
    const row = (n, depth) => {
      const r = bindItem(h("div.row", { style: { "--depth": depth } },
        h("span.c-name", n.kind === "folder" ? h("button.disc", { on: { click: (e) => { e.stopPropagation(); r.classList.toggle("open"); toggle(r, n, depth); } } }, sym("chevron-right")) : h("span.disc"),
          appIcon(fs.iconFor(n)), h("span.t", n.name)),
        h("span.c-date", fs.fmtDate(n.date)), h("span.c-size", fs.fmtSize(n)), h("span.c-kind", fs.kindLabel(n))), n);
      return r;
    };
    const toggle = (r, n, depth) => {
      if (r.classList.contains("open")) {
        const kids = (fs.resolve(n.path)?.children ?? []).map((c) => row({ ...c, path: fs.join(n.path, c.name) }, depth + 1));
        kids.forEach((k) => (k.dataset.parent = n.path));
        r.after(...kids);
        kids.forEach((k, i) => animate(k, [{ opacity: 0, transform: "translateY(-4px)" }, { opacity: 1, transform: "none" }], "snappy", { delay: i * 12 }));
      } else body.querySelectorAll(`[data-parent^="${CSS.escape(n.path)}"]`).forEach((k) => k.remove());
    };
    return h("div.list",
      h("div.head", h("span.c-name", "Name"), h("span.c-date", "Date Modified"), h("span.c-size", "Size"), h("span.c-kind", "Kind")),
      list.map((n) => row(n, 0)));
  }
  function columnView(list) {
    const cols = h("div.columns");
    const addCol = (items, from) => {
      while (cols.children.length > from) cols.lastChild.remove();
      const col = h("div.col", items.map((n) => {
        const r = h("div.crow", appIcon(fs.iconFor(n)), h("span.t", n.name), n.kind === "folder" ? h("span.chev", sym("chevron-right")) : null);
        r.addEventListener("click", () => {
          col.querySelectorAll(".crow").forEach((x) => x.classList.toggle("sel", x === r));
          if (n.kind === "folder") addCol((fs.resolve(n.path)?.children ?? []).map((c) => ({ ...c, path: fs.join(n.path, c.name) })), from + 1);
          else { while (cols.children.length > from + 1) cols.lastChild.remove(); cols.append(h("div.col.preview", appIcon(fs.iconFor(n)), h("b", n.name), h("small", `${fs.kindLabel(n)} · ${fs.fmtSize(n)}`), h("small", fs.fmtDate(n.date)))); }
          cols.scrollLeft = cols.scrollWidth;
        });
        r.addEventListener("dblclick", () => open(n));
        r.addEventListener("contextmenu", (e) => { e.preventDefault(); e.stopPropagation(); itemMenu(e, n); });
        return r;
      }));
      cols.append(col);
      animate(col, [{ opacity: 0 }, { opacity: 1 }], "snappy");
    };
    addCol(list, 0);
    return cols;
  }
  function galleryView(list) {
    let cur = list.find((n) => st.sel.has(n.path)) ?? list[0];
    const stage = h("div.stage");
    const strip = h("div.strip");
    const show = (n) => {
      cur = n;
      stage.replaceChildren(appIcon(fs.iconFor(n)), h("b", n.name), h("small", `${fs.kindLabel(n)} — ${fs.fmtSize(n)}`));
      animate(stage.firstChild, [{ transform: "scale(.9)", opacity: 0.5 }, { transform: "none", opacity: 1 }], "bouncy");
      strip.querySelectorAll(".thumb").forEach((t) => t.classList.toggle("sel", t._n === n));
    };
    strip.append(...list.map((n) => { const t = h("div.thumb", { on: { click: () => show(n), dblclick: () => open(n) } }, appIcon(fs.iconFor(n))); t._n = n; return t; }));
    show(cur);
    return h("div.gallery", stage, strip);
  }

  // --- menus
  function itemMenu(e, n) {
    openMenu([
      { label: "Ask Assistant", icon: h("span.mb-orb", { style: { width: "15px", height: "15px" } }), hero: true, action: () => bus.emit("spotlight", `About “${n.name}”`) },
      { label: "Open", action: () => open(n) },
      { label: "Open With", submenu: [{ label: "Photos", icon: appIcon("photos"), action: () => launch("photos") }, { label: "Notes", icon: appIcon("notes"), action: () => launch("notes") }, "-", { label: "App Store…" }] },
      "-",
      { label: "Move to Trash", icon: "trash", kbd: "⌘⌫", action: () => trashItems([n.path]) },
      "-",
      { label: "Get Info", kbd: "⌘I" }, { label: "Rename", action: () => rename(n.path) }, { label: `Compress “${n.name}”` }, { label: "Duplicate" }, { label: "Make Alias" }, { label: "Quick Look", kbd: "Space", action: () => quickLook(n.path) },
      "-",
      { label: "Copy" }, { label: "Share…", icon: "share" },
      "-",
      { tags: TAG_COLORS }, { label: "Tags…" },
      "-",
      { label: "Quick Actions", submenu: [{ label: "Rotate Left", icon: "arrow-clockwise" }, { label: "Create PDF", icon: "doc" }, { label: "Remove Background", icon: "sparkles" }, "-", { label: "Customize…" }] },
      { label: "Services", submenu: [{ label: "Open in Terminal", action: () => launch("terminal") }, { label: "New Note With Selection", action: () => launch("notes") }] },
    ], { x: e.clientX, y: e.clientY });
  }
  function backgroundMenu(e) {
    openMenu([
      { label: "New Folder", kbd: "⇧⌘N", action: newFolder }, "-", { label: "Get Info" }, "-",
      { label: "View", submenu: views.map((v) => ({ label: `as ${v[0].toUpperCase() + v.slice(1)}`, checked: st.view === v, action: () => setView(v) })) },
      { label: "Use Groups" }, { label: "Sort By", submenu: [{ label: "Name", checked: true }, { label: "Kind" }, { label: "Date Last Opened" }, { label: "Date Added" }, { label: "Date Modified" }, { label: "Size" }] },
      { label: "Show View Options", kbd: "⌘J" },
    ], { x: e.clientX, y: e.clientY });
  }
  const at = (e) => { const r = e.currentTarget.getBoundingClientRect(); return { x: r.left, y: r.bottom + 6 }; };
  function groupMenu(e) { openMenu([{ label: "None", checked: true }, "-", { label: "Name" }, { label: "Kind" }, { label: "Application" }, { label: "Date Last Opened" }, { label: "Date Added" }, { label: "Size" }, { label: "Tags" }], at(e)); }
  function tagMenu(e) { openMenu([{ tags: TAG_COLORS }, "-", { label: "Show All Tags…" }], at(e)); }
  function actionMenu(e) { openMenu([{ label: "New Folder", action: newFolder }, { label: "Show View Options" }, "-", { label: "Show Path Bar", checked: true }, { label: "Show Status Bar", checked: true }, { label: "Show Preview" }], at(e)); }

  body.addEventListener("contextmenu", (e) => { e.preventDefault(); backgroundMenu(e); });
  body.addEventListener("mousedown", () => { st.sel.clear(); body.querySelectorAll(".sel").forEach((x) => x.classList.remove("sel")); });
  zoomer.addEventListener("mousedown", (e) => {
    e.stopPropagation();
    const r = zoomer.getBoundingClientRect();
    const set = (x) => { st.iconSize = Math.round(40 + Math.min(1, Math.max(0, (x - r.left) / r.width)) * 88); body.style.setProperty("--icon", `${st.iconSize}px`); render(); };
    set(e.clientX);
    const mv = (ev) => set(ev.clientX), up = () => { removeEventListener("mousemove", mv); removeEventListener("mouseup", up); };
    addEventListener("mousemove", mv); addEventListener("mouseup", up);
  });
  win.el.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && "1234".includes(e.key)) { setView(views[+e.key - 1]); e.preventDefault(); }
  });

  // ------------------------------------------------------------------ file operations
  const cellFor = (path) => body.querySelector(`[data-path="${CSS.escape(path)}"]`);
  const nodeAt = (path) => ({ ...fs.resolve(path), path });
  const writable = () => !st.path.startsWith("@") && !st.query && st.path !== "/Applications";

  async function trashItems(paths) {
    paths = paths.filter((p) => !p.startsWith("/Applications/"));
    if (!paths.length) return;
    // Items shrink towards the Trash in the Dock ("poof").
    const tile = document.querySelector('.dock-item[data-app="trash"]')?.getBoundingClientRect();
    await Promise.all(paths.map((p) => {
      const el = cellFor(p); if (!el || !tile) return null;
      const r = el.getBoundingClientRect();
      return el.animate([{ transform: "none", opacity: 1 }, { transform: `translate(${tile.left - r.left}px, ${tile.top - r.top}px) scale(.2)`, opacity: 0 }], { duration: 480, easing: "cubic-bezier(.5,0,.2,1)", fill: "forwards" }).finished;
    }));
    paths.forEach((p) => fs.trash(p));
    st.sel.clear();
    render();
    bus.emit("trash");
  }

  function newFolder() {
    if (!writable()) return;
    const name = fs.uniqueName(st.path, "untitled folder");
    fs.resolve(st.path).children.push({ name, kind: "folder", date: new Date(), children: [] });
    st.sel = new Set([fs.join(st.path, name)]);
    if (st.view !== "icons" && st.view !== "list") st.view = "icons";
    render();
    const el = cellFor(fs.join(st.path, name));
    if (el) animate(el, [{ transform: "scale(.5)", opacity: 0 }, { transform: "none", opacity: 1 }], "bouncy");
    rename(fs.join(st.path, name));
  }

  // Inline rename: the name becomes a field with the stem selected.
  function rename(path) {
    const el = cellFor(path); if (!el || path.startsWith("/Applications/")) return;
    const label = el.querySelector(".name, .t"); if (!label) return;
    const node = fs.resolve(path);
    const input = h("input.rename", { value: node.name, spellcheck: false });
    label.replaceWith(input);
    input.focus();
    const dot = node.kind !== "folder" ? node.name.lastIndexOf(".") : -1;
    input.setSelectionRange(0, dot > 0 ? dot : node.name.length);
    let done = false;
    const finish = (commit) => {
      if (done) return; done = true;
      const v = input.value.trim().replace(/\//g, ":");
      if (commit && v && v !== node.name) {
        node.name = fs.uniqueName(fs.parentOf(path), v);
        st.sel = new Set([fs.join(fs.parentOf(path), node.name)]);
      }
      render();
    };
    input.addEventListener("keydown", (e) => { e.stopPropagation(); if (e.key === "Enter") finish(true); if (e.key === "Escape") finish(false); });
    input.addEventListener("blur", () => finish(true));
    input.addEventListener("mousedown", (e) => e.stopPropagation());
  }

  // Quick Look: a glass preview that zooms out of the item's icon.
  let ql = null;
  function quickLook(path) {
    if (ql) return closeQL();
    const n = nodeAt(path);
    const from = cellFor(path)?.querySelector("img")?.getBoundingClientRect();
    let preview;
    if (n.kind === "image") preview = h("div.ql-image", { style: { backgroundImage: `url("${qlPhoto(n.name)}")` } });
    else if (n.kind === "doc") preview = h("div.ql-doc", h("h1", n.name.replace(/\.[^.]+$/, "")), ...QL_TEXT.map((t) => h("p", t)));
    else preview = h("div.ql-icon", appIcon(fs.iconFor(n)), h("b", n.name), h("small", n.kind === "folder" ? `${n.children?.length ?? 0} items` : `${fs.kindLabel(n)} · ${fs.fmtSize(n)}`));
    const panel = h("div.ql.glass-regular", h("div.ql-bar", h("button.ql-close", { title: "Close", on: { click: () => closeQL() } }, sym("xmark")), h("span", n.name), h("button.btn.ql-open", { on: { click: () => { closeQL(); open(n); } } }, `Open with ${n.kind === "image" ? "Photos" : n.kind === "audio" ? "Music" : n.kind === "app" ? n.name : "Notes"}`)), preview);
    document.getElementById("desktop").append(panel);
    const to = panel.getBoundingClientRect();
    const t = from ? `translate(${from.left + from.width / 2 - (to.left + to.width / 2)}px, ${from.top + from.height / 2 - (to.top + to.height / 2)}px) scale(${from.width / to.width})` : "scale(.8)";
    animate(panel, [{ transform: t, opacity: 0.2 }, { transform: "none", opacity: 1 }], "bouncy");
    ql = { panel, t };
    panel.addEventListener("mousedown", (e) => e.stopPropagation());
  }
  async function closeQL() {
    if (!ql) return;
    const { panel, t } = ql; ql = null;
    await panel.animate([{ transform: "none", opacity: 1 }, { transform: t, opacity: 0 }], { duration: 260, easing: "cubic-bezier(.4,0,.6,1)", fill: "forwards" }).finished;
    panel.remove();
  }
  addEventListener("mousedown", () => ql && closeQL());

  // Keyboard: arrows move the selection, Space previews, Return renames,
  // ⌘⌫ trashes, ⌘↓ opens, ⌘↑ goes to the enclosing folder, ⇧⌘N makes a folder.
  function onKey(e) {
    if (activeWindow() !== win || e.target.matches("input, textarea") || document.getElementById("spotlight")?.hidden === false) return;
    const mod = e.metaKey || e.ctrlKey;
    const items = [...body.querySelectorAll("[data-path]")];
    const cur = items.findIndex((x) => st.sel.has(x.dataset.path));
    const pick = (i) => { const el = items[Math.max(0, Math.min(items.length - 1, i))]; if (!el) return; st.sel = new Set([el.dataset.path]); items.forEach((x) => x.classList.toggle("sel", x === el)); el.scrollIntoView({ block: "nearest" }); if (ql) { closeQL(); setTimeout(() => quickLook(el.dataset.path), 280); } };
    const cols = st.view === "icons" ? Math.max(1, Math.round(body.querySelector(".grid")?.getBoundingClientRect().width / (items[0]?.getBoundingClientRect().width || 1))) : 1;
    if (e.key === " " ) { if (cur >= 0) quickLook(items[cur].dataset.path); else if (ql) closeQL(); }
    else if (e.key === "Escape" && ql) closeQL();
    else if (mod && e.key === "Backspace") trashItems([...st.sel]);
    else if (mod && e.shiftKey && e.key.toLowerCase() === "n") newFolder();
    else if (mod && e.key === "ArrowDown" && cur >= 0) open(nodeAt(items[cur].dataset.path));
    else if (mod && e.key === "ArrowUp" && !st.path.startsWith("@")) navigate(fs.parentOf(st.path));
    else if (e.key === "Enter" && cur >= 0) rename(items[cur].dataset.path);
    else if (e.key === "ArrowRight" && st.view === "icons") pick(cur + 1);
    else if (e.key === "ArrowLeft" && st.view === "icons") pick(cur - 1);
    else if (e.key === "ArrowDown") pick(cur < 0 ? 0 : cur + cols);
    else if (e.key === "ArrowUp") pick(cur - cols);
    else return;
    e.preventDefault(); e.stopPropagation();
  }
  addEventListener("keydown", onKey);
  win.onClose = () => removeEventListener("keydown", onKey);

  // Drag and drop: onto folders, sidebar places, or the Trash in the Dock.
  function armDrag(e, el, n) {
    const sx = e.clientX, sy = e.clientY;
    let ghost = null, target = null;
    const paths = st.sel.has(n.path) ? [...st.sel] : [n.path];
    const dropTargets = () => [
      ...[...body.querySelectorAll("[data-path]")].filter((x) => fs.resolve(x.dataset.path)?.children && !paths.includes(x.dataset.path)).map((x) => [x, x.dataset.path]),
      ...[...sidebar.querySelectorAll(".side-row[data-path]")].map((x) => [x, x.dataset.path]),
      ...[...document.querySelectorAll('.dock-item[data-app="trash"]')].map((x) => [x, "@trash"]),
    ];
    const move = (ev) => {
      if (!ghost) {
        if (Math.hypot(ev.clientX - sx, ev.clientY - sy) < 5) return;
        const img = el.querySelector("img").cloneNode();
        ghost = h("div.drag-ghost", img, paths.length > 1 ? h("span.badge", String(paths.length)) : null);
        document.body.append(ghost);
        animate(ghost, [{ transform: "scale(1)" }, { transform: "scale(.9)" }], "snappy");
      }
      ghost.style.left = `${ev.clientX - 32}px`; ghost.style.top = `${ev.clientY - 32}px`;
      const hit = document.elementsFromPoint(ev.clientX, ev.clientY);
      const t = dropTargets().find(([x]) => hit.includes(x));
      if (target?.[0] !== t?.[0]) { target?.[0].classList.remove("drop-hot"); t?.[0].classList.add("drop-hot"); target = t; }
    };
    const up = async () => {
      removeEventListener("mousemove", move); removeEventListener("mouseup", up);
      if (!ghost) return;
      target?.[0].classList.remove("drop-hot");
      if (target) {
        ghost.remove();
        if (target[1] === "@trash") return trashItems(paths);
        paths.forEach((p) => fs.moveTo(p, target[1]));
        st.sel.clear(); render();
        return;
      }
      // No target: the ghost springs back to where it came from.
      const r = el.getBoundingClientRect(), g = ghost.getBoundingClientRect();
      await ghost.animate([{ transform: "scale(.9)" }, { transform: `translate(${r.left + r.width / 2 - (g.left + g.width / 2)}px, ${r.top + 20 - (g.top + g.height / 2)}px) scale(1)`, opacity: 0.2 }], { duration: 380, easing: getComputedStyle(document.documentElement).getPropertyValue("--spring-snappy").trim(), fill: "forwards" }).finished;
      ghost.remove();
    };
    addEventListener("mousemove", move); addEventListener("mouseup", up);
  }
  render();
  return win;
}

registerApp("files", openFiles, {
  Go: [
    { label: "Back", kbd: "⌘[" }, { label: "Forward", kbd: "⌘]" }, "-",
    { label: "Recents", icon: "clock", kbd: "⇧⌘F" }, { label: "Documents", icon: "doc", kbd: "⇧⌘O" }, { label: "Desktop", icon: "rectangle-fill", kbd: "⇧⌘D" },
    { label: "Downloads", icon: "download", kbd: "⌥⌘L" }, { label: "Home", icon: "house", kbd: "⇧⌘H" }, { label: "Applications", icon: "apps", kbd: "⇧⌘A", action: () => launch("files", "/Applications") }, "-",
    { label: "Go to Folder…", kbd: "⇧⌘G" }, { label: "Connect to Server…", kbd: "⌘K" },
  ],
});
