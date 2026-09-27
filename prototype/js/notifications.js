// Notification banners and the widgets panel (opened from the clock).
import { h, appIcon, bus, animate } from "./util.js";
import { APPS } from "./apps.js";

export function initNotifications() {
  const desk = document.getElementById("desktop");
  const banners = h("div#banners");
  desk.append(banners);

  bus.on("notify", ({ app = "settings", title, body }) => {
    const b = h("div.banner.glass-regular", appIcon(app), h("div", { style: { flex: 1, minWidth: 0 } },
      h("div.t", title, h("small", "now")), h("div.b", body)));
    b.title = APPS[app]?.name ?? "";
    banners.prepend(b);
    animate(b, [{ opacity: 0, transform: "translateX(110%)" }, { opacity: 1, transform: "none" }], "snappy");
    const dismiss = async () => {
      await b.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateX(60%)" }], { duration: 220, easing: "ease-in", fill: "forwards" }).finished;
      b.remove();
    };
    b.addEventListener("click", dismiss);
    setTimeout(dismiss, 5200);
  });

  // Widgets
  const today = new Date("2026-09-26T12:00");
  const first = new Date(today.getFullYear(), today.getMonth(), 1).getDay();
  const days = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
  const cal = h("div.widget.w-cal.glass-regular", h("div.month", today.toLocaleDateString("en-US", { month: "long" })),
    h("div.grid", ..."SMTWTFS".split("").map((d) => h("span.dow", d)),
      ...Array.from({ length: first }, () => h("span")),
      ...Array.from({ length: days }, (_, i) => h("span", { className: i + 1 === today.getDate() ? "today" : i + 1 < today.getDate() ? "dim" : "" }, String(i + 1)))));
  const weather = h("div.widget.w-weather.glass-regular", h("div.city", "San Francisco"), h("div.temp", "64°"), h("div.cond", "Fog clearing by afternoon"), h("div", { style: { fontSize: "12px", opacity: ".85" } }, "H:68° L:55°"));
  const events = h("div.widget.wide.w-events.glass-regular", h("div.month", { style: { color: "var(--accent-red)", fontWeight: 700, fontSize: "11px", textTransform: "uppercase", letterSpacing: ".04em" } }, "Today"),
    ...[["Design review · Liquid Glass", "10:00 – 11:00 AM", "#bf5af2"], ["Ship Golden Gate 0.1", "2:00 PM", "#ff9f0a"], ["Sunset walk, Crissy Field", "6:45 PM", "#30d158"]]
      .map(([t, s, c]) => h("div.ev", { style: { "--c": c } }, h("div", t, h("small", s)))));
  const widgets = h("div#widgets", { hidden: true }, weather, cal, events);
  desk.append(widgets);
  widgets.addEventListener("mousedown", (e) => e.stopPropagation());

  let open = false, btn = null;
  async function close() {
    if (!open) return;
    open = false; btn?.classList.remove("active");
    await Promise.all([...widgets.children].map((w) => w.animate([{ opacity: 1 }, { opacity: 0, transform: "translateX(30px)" }], { duration: 180, fill: "forwards" }).finished));
    if (!open) widgets.hidden = true;
  }
  function show(b) {
    bus.emit("overlays:close");
    open = true; btn = b; b?.classList.add("active");
    widgets.hidden = false;
    [...widgets.children].forEach((w, i) => animate(w, [{ opacity: 0, transform: "translateX(60px) scale(.94)" }, { opacity: 1, transform: "none" }], "popover", { delay: i * 40 }));
  }
  addEventListener("mousedown", close);
  bus.on("overlays:close", close);
  return { toggle: (b) => (open ? close() : show(b)) };
}
