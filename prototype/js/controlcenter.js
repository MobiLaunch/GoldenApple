// Control Center: free-floating Liquid Glass modules that spring out of the
// menu-bar button, with the Wi-Fi module expanding into a detail panel.
import { h, sym, state, bus, animate, spring } from "./util.js";
import { launch } from "./apps.js";

export function initControlCenter() {
  const root = h("div#cc", { hidden: true });
  document.getElementById("desktop").append(root);
  root.addEventListener("mousedown", (e) => e.stopPropagation());
  let btn = null, open = false;

  const wide = (key, icon, title, sub, onDetail) => {
    const m = h("div.cc-mod.cc-wide.glass", { className: `cc-mod cc-wide glass ${state[key] ? "on" : ""}` },
      h("button.cc-dot", { on: { click: (e) => { e.stopPropagation(); state[key] = !state[key]; } } }, sym(icon)),
      h("div", { style: { minWidth: 0 } }, h("div.t", title), sub ? h("div.s", sub) : null));
    if (onDetail) m.addEventListener("click", onDetail);
    bus.on(`state:${key}`, (v) => m.classList.toggle("on", v));
    return m;
  };
  const circle = (key, icon, title, onClick) => {
    const b = h("button.cc-mod.cc-circle.glass", { title, className: `cc-mod cc-circle glass ${key && state[key] ? "on" : ""}`, on: { click: onClick ?? (() => (state[key] = !state[key])) } }, sym(icon));
    if (key) bus.on(`state:${key}`, (v) => b.classList.toggle("on", v));
    return b;
  };
  const slider = (key, title, lo, hi, extra) => {
    const fill = h("i", { style: { width: `${state[key] * 100}%` } });
    const track = h("div.slider", fill);
    track.addEventListener("pointerdown", (e) => {
      track.setPointerCapture(e.pointerId); track.classList.add("drag");
      const r = track.getBoundingClientRect();
      const set = (x) => (state[key] = Math.min(1, Math.max(0, (x - r.left) / r.width)));
      set(e.clientX);
      track.onpointermove = (ev) => set(ev.clientX);
      track.onpointerup = () => { track.onpointermove = null; track.classList.remove("drag"); };
    });
    bus.on(`state:${key}`, (v) => (fill.style.width = `${v * 100}%`));
    return h("div.cc-mod.cc-slider.glass", h("div.t", title), h("div.row", h("span.end", sym(lo)), track, h("span.end", sym(hi)), extra ?? null));
  };

  const playBtn = h("button.play", { on: { click: () => (state.playing = !state.playing) } }, sym("play"));
  bus.on("state:playing", (p) => playBtn.replaceChildren(sym(p ? "pause" : "play")));
  const nowPlaying = h("div.cc-mod.cc-now.glass",
    h("div.art", sym("music")), h("div.t", "Fog Horns"), h("div.s", "The Presidio Quartet"),
    h("div.ctl", h("button", sym("backward")), playBtn, h("button", sym("forward"))));

  function modules() {
    return [
      wide("wifi", "wifi", "Wi-Fi", "Home", (e) => { if (!e.target.closest(".cc-dot")) showDetail(); }),
      nowPlaying,
      circle("bluetooth", "bluetooth", "Bluetooth"), circle("airdrop", "broadcast", "Nearby Share"),
      wide("focus", "moon", "Focus", null),
      circle("stage", "stage", "Stage Manager"), circle(null, "mirror", "Screen Mirroring", () => {}),
      slider("brightness", "Display", "sun", "sun-max"),
      slider("volume", "Sound", "speaker", "speaker-wave", h("span.airplay", sym("broadcast"))),
      circle(null, "contrast", "Dark Mode", () => (state.theme = state.theme === "dark" ? "light" : "dark")),
      circle(null, "calculator", "Calculator", () => { close(); launch("calculator"); }),
      circle(null, "timer", "Timer", () => bus.emit("notify", { app: "calendar", title: "Timer", body: "5-minute timer started." })),
      circle(null, "screenshot", "Screenshot", () => { close(); setTimeout(() => bus.emit("screenshot"), 250); }),
      h("button.edit.glass", "Edit Controls"),
    ];
  }
  const darkBtn = () => root.querySelector('[title="Dark Mode"]');
  bus.on("state:theme", (t) => darkBtn()?.classList.toggle("on", t === "dark"));

  function showDetail() {
    const nets = ["Home", "Golden Gate Guest", "Presidio 5G", "Bay Bridge", "Crissy Field"].map((n, i) =>
      h("div.net", { className: `net ${i === 0 ? "on" : ""}` }, h("span.ico", sym("wifi")), n, i ? h("span.lock", sym("lock")) : null));
    const sw = h("button.switch", { className: `switch ${state.wifi ? "on" : ""}`, on: { click: () => { state.wifi = !state.wifi; sw.classList.toggle("on", state.wifi); } } });
    const panel = h("div.cc-mod.cc-detail.glass", h("h3", "Wi-Fi", sw), h("div.header", { style: { fontSize: "12px", opacity: ".7", margin: "0 8px 4px" } }, "Known Network"), nets[0],
      h("div.header", { style: { fontSize: "12px", opacity: ".7", margin: "10px 8px 4px" } }, "Other Networks"), ...nets.slice(1),
      h("button.foot", { on: { click: () => { close(); launch("settings", "wifi"); } } }, "Wi-Fi Settings…"));
    const first = root.firstChild.getBoundingClientRect();
    root.replaceChildren(panel);
    const r = panel.getBoundingClientRect();
    // Morph: the panel starts at the Wi-Fi module's frame and springs to full size.
    animate(panel, [{ transform: `translate(${first.left - r.left}px, ${first.top - r.top}px) scale(${first.width / r.width}, ${first.height / r.height})`, transformOrigin: "top left", borderRadius: "32px" }, { transform: "none", transformOrigin: "top left" }], "popover");
    [...panel.children].forEach((c, i) => animate(c, [{ opacity: 0 }, { opacity: 1 }], "smooth", { delay: 80 + i * 18 }));
    panel.addEventListener("mousedown", (e) => { if (e.target === panel) back(); });
    const back = () => { root.replaceChildren(...modules()); darkBtn()?.classList.toggle("on", state.theme === "dark"); };
    panel.querySelector("h3").addEventListener("dblclick", back);
  }

  async function openCC(button) {
    btn = button; open = true;
    root.replaceChildren(...modules());
    darkBtn()?.classList.toggle("on", state.theme === "dark");
    root.hidden = false;
    btn?.classList.add("active");
    const s = spring("popover");
    [...root.children].forEach((m, i) => {
      m.animate([{ opacity: 0, transform: "translateY(-18px) scale(.72)", filter: "blur(6px)" }, { opacity: 1, transform: "none", filter: "blur(0)" }],
        { duration: s.duration, easing: s.easing, delay: i * 14, fill: "backwards" });
    });
  }
  async function close() {
    if (!open) return;
    open = false;
    btn?.classList.remove("active");
    const kids = [...root.children];
    await Promise.all(kids.map((m, i) => m.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateY(-10px) scale(.86)" }],
      { duration: 180, easing: "cubic-bezier(.4,0,1,1)", delay: (kids.length - i) * 6, fill: "forwards" }).finished));
    if (!open) root.hidden = true;
  }
  addEventListener("mousedown", () => close());
  bus.on("overlays:close", close);
  return { toggle: (b) => (open ? close() : (bus.emit("overlays:close"), openCC(b))), close, open: openCC };
}
