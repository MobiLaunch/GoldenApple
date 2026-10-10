// Notification banners and the widgets panel (opened from the clock).
import { h, sym, appIcon, bus, animate } from "./util.js";
import { APPS } from "./apps.js";

export function initNotifications() {
  const desk = document.getElementById("desktop");
  const banners = h("div#banners");
  desk.append(banners);

  const history = [];
  bus.on("notify", ({ app = "settings", title, body }) => {
    history.unshift({ app, title, body, at: new Date() });
    history.length = Math.min(history.length, 6);
    const close = h("button.b-close.glass-regular", { title: "Clear" }, sym("xmark"));
    const b = h("div.banner.glass-regular", close, appIcon(app), h("div", { style: { flex: 1, minWidth: 0 } },
      h("div.t", title, h("small", "now")), h("div.b", body)));
    b.title = APPS[app]?.name ?? "";
    banners.prepend(b);
    animate(b, [{ opacity: 0, transform: "translateX(110%)" }, { opacity: 1, transform: "none" }], "snappy");
    let gone = false;
    const dismiss = async (dx = 60) => {
      if (gone) return; gone = true;
      await b.animate([{ opacity: 1, transform: getComputedStyle(b).transform === "none" ? "none" : getComputedStyle(b).transform }, { opacity: 0, transform: `translateX(${Math.max(dx, 60) + 260}px)` }], { duration: 240, easing: "ease-in", fill: "forwards" }).finished;
      b.animate([{ height: `${b.offsetHeight}px`, marginBottom: "0px" }, { height: "0px", marginBottom: "-8px", paddingTop: 0, paddingBottom: 0 }], { duration: 200, fill: "forwards" }).finished.then(() => b.remove());
    };
    close.addEventListener("click", (e) => { e.stopPropagation(); dismiss(); });
    // Swipe right to dismiss; a short swipe springs back.
    b.addEventListener("pointerdown", (e) => {
      if (e.target.closest(".b-close")) return;
      const sx = e.clientX; let dx = 0;
      b.setPointerCapture(e.pointerId);
      b.onpointermove = (ev) => { dx = Math.max(-20, ev.clientX - sx); b.style.transform = `translateX(${dx < 0 ? dx / 3 : dx}px)`; b.style.opacity = String(1 - Math.max(0, dx) / 400); };
      b.onpointerup = () => {
        b.onpointermove = b.onpointerup = null;
        if (dx > 90) dismiss(dx);
        else { const from = b.style.transform; b.style.transform = ""; b.style.opacity = ""; animate(b, [{ transform: from }, { transform: "none" }], "bouncy"); if (Math.abs(dx) < 4) { bus.emit("launch", { id: app }); dismiss(); } }
      };
    });
    setTimeout(() => { if (!b.matches(":hover")) dismiss(); else b.addEventListener("mouseleave", () => setTimeout(dismiss, 1200), { once: true }); }, 5200);
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
    ...[["Design review · Liquid Glass", "10:00 – 11:00 AM", "#bf5af2"], ["Ship CitronOS 0.1", "2:00 PM", "#ff9f0a"], ["Sunset walk, Crissy Field", "6:45 PM", "#30d158"]]
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
    widgets.querySelector(".nc-stack")?.remove();
    if (history.length) {
      // Notification Center: the latest notifications as a stack above the widgets.
      const stack = h("div.nc-stack", { className: `nc-stack ${history.length > 1 ? "stacked" : ""}`, on: { click: (e) => e.currentTarget.classList.toggle("expanded") } },
        ...history.map((n, i) => h("div.banner.glass-regular", { style: { "--i": i } }, appIcon(n.app), h("div", { style: { flex: 1, minWidth: 0 } },
          h("div.t", n.title, h("small", n.at.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }))), h("div.b", n.body)))));
      widgets.prepend(stack);
    }
    widgets.hidden = false;
    [...widgets.children].forEach((w, i) => animate(w, [{ opacity: 0, transform: "translateX(60px) scale(.94)" }, { opacity: 1, transform: "none" }], "popover", { delay: i * 40 }));
  }
  addEventListener("mousedown", close);
  bus.on("overlays:close", close);
  return { toggle: (b) => (open ? close() : show(b)) };
}
