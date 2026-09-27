// Files: the Finder-equivalent. Icon / list / column / gallery views, history,
// floating glass sidebar, search, context menus and the icon-size slider.
import { h, sym, appIcon, bus, animate } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
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
const TAG_COLORS = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2", "#8e8e93"];

function openFiles(_id, arg) {
  const st = { path: typeof arg === "string" && arg.startsWith("/") ? arg : "/Applications", view: "icons", back: [], fwd: [], sel: new Set(), query: "", iconSize: 64 };
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
    if (st.path.startsWith("@")) return [];
    const node = fs.resolve(st.path);
    return (node?.children ?? []).map((c) => ({ ...c, path: fs.join(st.path, c.name) })).sort((a, b) => a.name.localeCompare(b.name));
  }
  const labelFor = (p) => ({ "@recents": "Recents", "@shared": "Shared", "@network": "Network", "@tag": "Tagged" }[p] ?? (p === "/" ? "System HD" : p.split("/").at(-1)));

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
      ...s.rows.map(([label, icon, path, color]) => h("div.side-row", { className: `side-row ${path === st.path && !st.query ? "sel" : ""}`, on: { click: () => navigate(path) } },
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
      { label: "Move to Trash", icon: "trash", action: () => bus.emit("notify", { app: "files", title: "Moved to Trash", body: n.name }) },
      "-",
      { label: "Get Info", kbd: "⌘I" }, { label: "Rename" }, { label: `Compress “${n.name}”` }, { label: "Duplicate" }, { label: "Make Alias" }, { label: "Quick Look", kbd: "Space" },
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
      { label: "New Folder" }, "-", { label: "Get Info" }, "-",
      { label: "View", submenu: views.map((v) => ({ label: `as ${v[0].toUpperCase() + v.slice(1)}`, checked: st.view === v, action: () => setView(v) })) },
      { label: "Use Groups" }, { label: "Sort By", submenu: [{ label: "Name", checked: true }, { label: "Kind" }, { label: "Date Last Opened" }, { label: "Date Added" }, { label: "Date Modified" }, { label: "Size" }] },
      { label: "Show View Options", kbd: "⌘J" },
    ], { x: e.clientX, y: e.clientY });
  }
  const at = (e) => { const r = e.currentTarget.getBoundingClientRect(); return { x: r.left, y: r.bottom + 6 }; };
  function groupMenu(e) { openMenu([{ label: "None", checked: true }, "-", { label: "Name" }, { label: "Kind" }, { label: "Application" }, { label: "Date Last Opened" }, { label: "Date Added" }, { label: "Size" }, { label: "Tags" }], at(e)); }
  function tagMenu(e) { openMenu([{ tags: TAG_COLORS }, "-", { label: "Show All Tags…" }], at(e)); }
  function actionMenu(e) { openMenu([{ label: "New Folder" }, { label: "Show View Options" }, "-", { label: "Show Path Bar", checked: true }, { label: "Show Status Bar", checked: true }, { label: "Show Preview" }], at(e)); }

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
