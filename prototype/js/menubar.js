// Transparent menu bar: system menu, app menus (hover-to-switch once one is open),
// status items and the clock.
import { h, sym, bus, state, fmtClock } from "./util.js";
import { openMenu, closeMenus, menuOpen } from "./menus.js";
import { APPS, menusFor, launch } from "./apps.js";
import { activeWindow } from "./wm.js";

export function initMenubar(el, { toggleCC, toggleWidgets, openSpotlight }) {
  const left = h("div.side"), right = h("div.side");
  el.append(left, right);
  let current = null;

  const systemMenu = () => [
    { label: "About This Computer", icon: "info", action: () => launch("settings", "general") }, "-",
    { label: "System Settings…", icon: "gear", action: () => launch("settings") },
    { label: "Software…", icon: "download", action: () => launch("store") }, "-",
    { label: "Recent Items", icon: "clock", submenu: [{ header: "Applications" }, { label: "Files", icon: "folder", action: () => launch("files") }, { label: "Photos", icon: "photo", action: () => launch("photos") }, { label: "Terminal", icon: "apps", action: () => launch("terminal") }] }, "-",
    { label: "Force Quit…", icon: "xmark", kbd: "⌥⌘⎋" }, "-",
    { label: "Sleep", icon: "moon", action: () => bus.emit("sleep") }, { label: "Restart…", icon: "arrow-clockwise" }, { label: "Shut Down…", icon: "power" }, "-",
    { label: "Lock Screen", icon: "lock", kbd: "⌃⌘Q", action: () => bus.emit("lock") }, { label: "Log Out golden…", icon: "person", kbd: "⇧⌘Q" },
  ];

  function openFor(item, items) {
    if (current === item) return;
    left.querySelectorAll(".active").forEach((x) => x.classList.remove("active"));
    item.classList.add("active");
    current = item;
    const r = item.getBoundingClientRect();
    openMenu(items(), { x: r.left, y: r.bottom + 5, onClose: () => { item.classList.remove("active"); if (current === item) current = null; } });
  }
  const menuItem = (content, items, cls = "") => {
    const it = h("button.mb-item", { className: `mb-item ${cls}` }, content);
    it.addEventListener("mousedown", (e) => {
      e.stopPropagation();
      if (current === it) { closeMenus(); return; }
      closeOverlays(); openFor(it, items);
    });
    it.addEventListener("mouseenter", () => { if (menuOpen() && current && current !== it && left.contains(current) === left.contains(it)) openFor(it, items); });
    return it;
  };

  function renderLeft() {
    const w = activeWindow();
    const id = w?.app ?? "files";
    const menus = menusFor(id);
    const name = APPS[id]?.name ?? "Files";
    left.replaceChildren(
      menuItem(sym("logo"), systemMenu, "logo icon"),
      ...Object.entries(menus).map(([title, items], i) => menuItem(i === 0 ? name : title, () => items, i === 0 ? "app-name" : "")),
    );
  }

  const battery = h("div.mb-battery", h("span.cell", h("i", { style: { width: "86%" } })), h("span.nub"));
  const statusMenu = (content, items, cls) => {
    const it = menuItem(content, items, `icon ${cls ?? ""}`);
    right.append(it);
    return it;
  };
  statusMenu(battery, () => [{ header: "Battery" }, { label: "86% — Power Source: Battery", disabled: true }, "-", { label: "Using Significant Energy", disabled: true }, { label: "Photos", icon: "photo" }, "-", { label: "Battery Settings…", action: () => launch("settings", "general") }]);
  statusMenu(sym("wifi"), () => [
    { label: "Wi-Fi", checked: state.wifi, action: () => (state.wifi = !state.wifi) }, "-", { header: "Known Network" },
    { label: "Home", icon: "wifi", checked: undefined }, "-", { header: "Other Networks" },
    { label: "Golden Gate Guest", icon: "lock" }, { label: "Presidio 5G", icon: "lock" }, "-", { label: "Wi-Fi Settings…", action: () => launch("settings", "wifi") },
  ]);
  const plain = (content, onClick, cls) => {
    const b = h("button.mb-item", { className: `mb-item icon ${cls ?? ""}`, on: { mousedown: (e) => { e.stopPropagation(); closeMenus(); onClick(b); } } }, content);
    right.append(b);
    return b;
  };
  plain(sym("search"), () => { closeOverlays(); openSpotlight(); });
  const ccBtn = plain(sym("control-center"), () => toggleCC(ccBtn));
  plain(h("span.mb-orb"), () => { closeOverlays(); openSpotlight("", "assistant"); });
  const clock = plain(h("span.mb-clock", fmtClock()), () => toggleWidgets(clock));
  clock.style.padding = "0 6px 0 10px";
  setInterval(() => (clock.firstChild.textContent = fmtClock()), 10_000);

  function closeOverlays() { bus.emit("overlays:close"); }
  bus.on("focus", renderLeft);
  bus.on("windows", renderLeft);
  renderLeft();
  return { ccBtn, clock };
}
