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
  const npArt = h("div.art", sym("music")), npTitle = h("div.t"), npSub = h("div.s");
  const syncNow = () => {
    const np = state.nowPlaying;
    npTitle.textContent = np?.title ?? "Not Playing"; npSub.textContent = np?.artist ?? "";
    npArt.style.backgroundImage = np?.art ? `url("${np.art}")` : "";
    npArt.classList.toggle("has-art", !!np?.art);
  };
  bus.on("state:nowPlaying", syncNow); syncNow();
  const nowPlaying = h("div.cc-mod.cc-now.glass", npArt, npTitle, npSub,
    h("div.ctl", h("button", sym("backward")), playBtn, h("button", sym("forward"))));

  const titled = (el, kind) => { el.querySelector(".t")?.addEventListener("click", () => showDetail(kind, el)); el.querySelector(".airplay")?.addEventListener("click", () => showDetail(kind, el)); return el; };
  function modules() {
    return [
      wide("wifi", "wifi", "Wi-Fi", "Home", (e) => { if (!e.target.closest(".cc-dot")) showDetail("wifi", e.currentTarget); }),
      nowPlaying,
      detailOn(circle("bluetooth", "bluetooth", "Bluetooth"), "bluetooth"), circle("airdrop", "broadcast", "Nearby Share"),
      wide("focus", "moon", "Focus", null, (e) => { if (!e.target.closest(".cc-dot")) showDetail("focus", e.currentTarget); }),
      circle("stage", "stage", "Stage Manager"), circle(null, "mirror", "Screen Mirroring", () => {}),
      titled(slider("brightness", "Display", "sun", "sun-max"), "display"),
      titled(slider("volume", "Sound", "speaker", "speaker-wave", h("span.airplay", sym("airplay"))), "sound"),
      circle(null, "contrast", "Dark Mode", () => (state.theme = state.theme === "dark" ? "light" : "dark")),
      circle(null, "calculator", "Calculator", () => { close(); launch("calculator"); }),
      circle(null, "timer", "Timer", () => bus.emit("notify", { app: "calendar", title: "Timer", body: "5-minute timer started." })),
      circle(null, "screenshot", "Screenshot", () => { close(); setTimeout(() => bus.emit("screenshot"), 250); }),
      h("button.edit.glass", "Edit Controls"),
    ];
  }
  const darkBtn = () => root.querySelector('[title="Dark Mode"]');
  bus.on("state:theme", (t) => darkBtn()?.classList.toggle("on", t === "dark"));

  // Detail panels: a module morphs into a full-height panel (spring from its own
  // frame). Wi-Fi/Focus open from their labels, sliders from their titles, and
  // circles on right-click or a long press.
  const DETAILS = {
    wifi: () => {
      const nets = ["Home", "Golden Gate Guest", "Presidio 5G", "Bay Bridge", "Crissy Field"].map((n, i) =>
        h("div.net", { className: `net ${i === 0 ? "on" : ""}` }, h("span.ico", sym("wifi")), n, i ? h("span.lock", sym("lock")) : null));
      return ["Wi-Fi", "wifi", [section("Known Network"), nets[0], section("Other Networks"), ...nets.slice(1)], ["Wi-Fi Settings…", "wifi"]];
    },
    bluetooth: () => ["Bluetooth", "bluetooth", [section("Devices"),
      ...[["Studio Headphones", "headphones", true], ["Magic Trackpad", "rectangle-fill", true], ["Keyboard", "keyboard", false], ["Pixel Buds", "headphones", false]]
        .map(([n, icon, on]) => h("div.net", { className: `net ${on ? "on" : ""}`, on: { click: (e) => e.currentTarget.classList.toggle("on") } }, h("span.ico", sym(icon)), n, h("span.lock", on ? "Connected" : "")))], ["Bluetooth Settings…", "bluetooth"]],
    focus: () => ["Focus", "focus", ["Do Not Disturb", "Personal", "Work", "Sleep"].map((n, i) => h("div.net", { className: `net ${state.focus && i === 0 ? "on" : ""}`, on: { click: (e) => { e.currentTarget.parentElement.querySelectorAll(".net").forEach((x) => x !== e.currentTarget && x.classList.remove("on")); e.currentTarget.classList.toggle("on"); state.focus = e.currentTarget.classList.contains("on"); } } },
      h("span.ico", sym(["moon", "person", "briefcase", "bell"][i])), n)), ["Focus Settings…", "focus"]],
    display: () => ["Display", null, [slider("brightness", "", "sun", "sun-max"), row("Dark Mode", "contrast", state.theme === "dark", (on) => (state.theme = on ? "dark" : "light")),
      row("Night Shift", "sun", false, () => {}), row("Auto-Brightness", "sun-max", true, () => {})], ["Display Settings…", "displays"]],
    sound: () => ["Sound", null, [slider("volume", "", "speaker", "speaker-wave"), section("Output"),
      ...[["Built-in Speakers", "speaker-wave", true], ["Studio Headphones", "headphones", false], ["Living Room", "airplay", false]]
        .map(([n, icon, on]) => h("div.net", { className: `net ${on ? "on" : ""}`, on: { click: (e) => { e.currentTarget.parentElement.querySelectorAll(".net").forEach((x) => x.classList.toggle("on", x === e.currentTarget)); } } }, h("span.ico", sym(icon)), n))], ["Sound Settings…", "sound"]],
  };
  const section = (t) => h("div.header", { style: { fontSize: "12px", opacity: ".7", margin: "10px 8px 4px" } }, t);
  function row(label, icon, on, set) {
    const sw = h("button.switch", { className: `switch ${on ? "on" : ""}`, on: { click: (e) => { e.stopPropagation(); sw.classList.toggle("on"); set(sw.classList.contains("on")); } } });
    return h("div.net", h("span.ico", sym(icon)), label, h("span.lock", sw));
  }

  function showDetail(kind, fromEl) {
    const [title, key, body, [footLabel, pane]] = DETAILS[kind]();
    const sw = key ? h("button.switch", { className: `switch ${state[key] ? "on" : ""}`, on: { click: () => { state[key] = !state[key]; sw.classList.toggle("on", state[key]); } } }) : null;
    const back = () => { root.replaceChildren(...modules()); darkBtn()?.classList.toggle("on", state.theme === "dark"); [...root.children].forEach((m, i) => animate(m, [{ opacity: 0, transform: "scale(.94)" }, { opacity: 1, transform: "none" }], "popover", { delay: i * 8 })); };
    const panel = h("div.cc-mod.cc-detail.glass",
      h("h3", h("button.cc-back", { title: "Back", on: { click: back } }, sym("chevron-left")), h("span", title), sw ?? h("span")),
      ...body,
      h("button.foot", { on: { click: () => { close(); launch("settings", pane); } } }, footLabel));
    const first = (fromEl ?? root.firstChild).getBoundingClientRect();
    root.replaceChildren(panel);
    const r = panel.getBoundingClientRect();
    animate(panel, [{ transform: `translate(${first.left - r.left}px, ${first.top - r.top}px) scale(${first.width / r.width}, ${first.height / r.height})`, transformOrigin: "top left" }, { transform: "none", transformOrigin: "top left" }], "popover");
    [...panel.children].forEach((c, i) => animate(c, [{ opacity: 0, transform: "translateY(-4px)" }, { opacity: 1, transform: "none" }], "smooth", { delay: 90 + i * 18 }));
    panel.addEventListener("mousedown", (e) => { if (e.target === panel) back(); });
  }
  // Long press / right-click opens a circle's details.
  function detailOn(el, kind) {
    let t = 0;
    el.addEventListener("contextmenu", (e) => { e.preventDefault(); e.stopPropagation(); showDetail(kind, el); });
    el.addEventListener("pointerdown", () => { t = setTimeout(() => { el.dataset.held = "1"; showDetail(kind, el); }, 480); });
    ["pointerup", "pointerleave"].forEach((ev) => el.addEventListener(ev, () => clearTimeout(t)));
    el.addEventListener("click", (e) => { if (el.dataset.held) { e.stopImmediatePropagation(); delete el.dataset.held; } }, true);
    return el;
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
