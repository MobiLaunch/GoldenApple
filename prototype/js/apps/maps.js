// Maps: an original stylised bay map (light + dark palettes via CSS variables),
// drag to pan, wheel/buttons to zoom, search with a spring fly-to, a bouncing
// pin, a place card in the floating sidebar and an animated route.
import { h, sym, animate, wait } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp } from "../apps.js";

const PLACES = [
  ["Golden Gate Bridge", "Landmark · Suspension bridge", 520, 405, "4.9", "Open 24 hours"],
  ["Alcatraz Island", "Landmark · Historic site", 1150, 250, "4.7", "Ferries from Pier 33"],
  ["Golden Gate Park", "Park", 430, 895, "4.8", "Open 5 AM – 10 PM"],
  ["Ferry Building", "Market · Landmark", 1318, 590, "4.7", "Open until 7 PM"],
  ["Crissy Field", "Beach · Park", 660, 492, "4.8", "Open 24 hours"],
  ["Mission Dolores Park", "Park", 1010, 985, "4.7", "Open 6 AM – 10 PM"],
  ["Sausalito", "City", 250, 170, "4.6", "Across the bridge"],
];
const ME = [905, 812];

function mapSVG() {
  const streets = [];
  for (let x = 720; x <= 1330; x += 38) streets.push(`M${x} 500V1200`);
  for (let y = 540; y <= 1200; y += 38) streets.push(`M700 ${y}H1340`);
  for (let x = 40; x <= 700; x += 44) streets.push(`M${x} 640V1200`);
  for (let y = 660; y <= 1200; y += 44) streets.push(`M20 ${y}H700`);
  const label = (x, y, t, cls = "", rot = 0) => `<text x="${x}" y="${y}" class="${cls}" transform="rotate(${rot} ${x} ${y})">${t}</text>`;
  return `<svg class="map-svg" viewBox="0 0 1600 1200" xmlns="http://www.w3.org/2000/svg">
  <defs><clipPath id="sf"><path d="M0 600L80 560 260 522 430 482 560 470 700 480 820 470 950 440 1080 410 1180 440 1250 500 1300 580 1330 700 1350 850 1380 1000 1420 1200H0Z"/></clipPath></defs>
  <rect width="1600" height="1200" fill="var(--map-water)"/>
  <path d="M0 0H770L730 200 700 262 600 330 430 372 300 342 150 365 0 385Z" fill="var(--map-land)"/>
  <path d="M1510 0H1600V1200H1560L1540 900 1500 700 1560 500 1500 300Z" fill="var(--map-land)"/>
  <ellipse cx="1150" cy="250" rx="34" ry="18" fill="var(--map-land)"/><ellipse cx="1330" cy="150" rx="90" ry="60" fill="var(--map-park)"/>
  <ellipse cx="1470" cy="470" rx="30" ry="46" fill="var(--map-land)"/>
  <path d="M0 600L80 560 260 522 430 482 560 470 700 480 820 470 950 440 1080 410 1180 440 1250 500 1300 580 1330 700 1350 850 1380 1000 1420 1200H0Z" fill="var(--map-land)"/>
  <g clip-path="url(#sf)">
    <path d="${streets.join("")}" stroke="var(--map-street)" stroke-width="5" fill="none"/>
    <path d="M300 480H700V640H300Z" fill="var(--map-park)" rx="20"/>
    <path d="M60 862H780V930H60Z" fill="var(--map-park)"/>
    <path d="M900 950h180v70H900z" fill="var(--map-park)"/>
    <path d="M1320 560L800 1010M300 480V1200M560 470L700 520 1180 520M60 1060H1400" stroke="var(--map-major-casing)" stroke-width="16" fill="none" stroke-linecap="round"/>
    <path d="M1320 560L800 1010M300 480V1200M560 470L700 520 1180 520M60 1060H1400" stroke="var(--map-major)" stroke-width="10" fill="none" stroke-linecap="round"/>
  </g>
  <path d="M130 360Q210 280 250 170T420 40" stroke="var(--map-major)" stroke-width="9" fill="none" stroke-linecap="round"/>
  <path d="M520 330L520 480" stroke="#d9412c" stroke-width="12" stroke-linecap="round"/>
  <path d="M506 360h28M506 450h28" stroke="#b3261e" stroke-width="7"/>
  <g class="map-labels">
    ${label(160, 760, "Pacific Ocean", "water", -8)}${label(1240, 330, "San Francisco Bay", "water")}${label(760, 420, "Golden Gate", "water small")}
    ${label(250, 210, "Sausalito")}${label(470, 560, "Presidio", "park")}${label(420, 902, "Golden Gate Park", "park")}
    ${label(830, 560, "Marina")}${label(1180, 650, "Financial District")}${label(1030, 1100, "Mission")}${label(620, 790, "Richmond")}${label(560, 1150, "Sunset")}
    ${label(1150, 222, "Alcatraz", "small")}${label(1540, 620, "Oakland", "", -90)}
  </g>
</svg>`;
}

function openMaps() {
  const st = { x: -260, y: -260, s: 1, place: null };
  const stage = h("div.map-stage", { html: mapSVG() });
  const layer = h("div.map-layer");                     // pins + route live in map coordinates
  stage.append(layer);
  const me = h("div.me-dot", { style: { left: `${ME[0]}px`, top: `${ME[1]}px` } }, h("i"));
  layer.append(me);
  const viewport = h("div.map-view", stage);
  const sidebar = h("div.maps-side");
  const search = h("input", { placeholder: "Search Maps", spellcheck: false });
  const panel = h("div.maps-panel");
  sidebar.append(h("label.side-search", sym("search"), search), panel);

  const zoomBy = (f, cx, cy) => {
    const r = viewport.getBoundingClientRect();
    cx ??= r.width / 2; cy ??= r.height / 2;
    const ns = Math.min(2.4, Math.max(0.45, st.s * f));
    st.x = cx - (cx - st.x) * (ns / st.s); st.y = cy - (cy - st.y) * (ns / st.s); st.s = ns;
    apply(true);
  };
  const win = createWindow({
    app: "maps", w: 1100, h: 700, sidebar, sidebarWidth: 280, overlaySidebar: true, className: "maps", content: viewport,
    toolbar: [pill(tb("location", { title: "Current Location", click: () => flyTo(ME[0], ME[1], 1.4) })), h("div.grow"),
      pill(tb("layers", { title: "Map Modes" }), tb("Explore", { text: true })),
      pill(tb("minus", { title: "Zoom Out", click: () => zoomBy(1 / 1.35) }), div(), tb("plus", { title: "Zoom In", click: () => zoomBy(1.35) })),
      pill(tb("share", { title: "Share" }))],
  });
  const compass = h("button.compass.glass-regular", { title: "North" }, h("span", "N"));
  win.main.append(compass);

  function apply(animated) {
    const t = `translate(${st.x}px, ${st.y}px) scale(${st.s})`;
    if (animated) animate(stage, [{ transform: getComputedStyle(stage).transform }, { transform: t }], "smooth");
    stage.style.transform = t;
    layer.style.setProperty("--inv", 1 / st.s);
  }
  function flyTo(mx, my, s = 1.5) {
    const r = viewport.getBoundingClientRect();
    st.s = s; st.x = (r.width + 280) / 2 - mx * s; st.y = r.height / 2 - my * s;
    apply(true);
  }

  // drag to pan, wheel to zoom
  viewport.addEventListener("pointerdown", (e) => {
    if (e.target.closest("button")) return;
    viewport.setPointerCapture(e.pointerId);
    viewport.classList.add("dragging");
    const sx = e.clientX - st.x, sy = e.clientY - st.y;
    viewport.onpointermove = (ev) => { st.x = ev.clientX - sx; st.y = ev.clientY - sy; apply(false); };
    viewport.onpointerup = () => { viewport.onpointermove = null; viewport.classList.remove("dragging"); };
  });
  viewport.addEventListener("wheel", (e) => {
    e.preventDefault();
    const r = viewport.getBoundingClientRect();
    zoomBy(Math.exp(-e.deltaY * 0.0015), e.clientX - r.left, e.clientY - r.top);
  }, { passive: false });

  function results(q) {
    const list = PLACES.filter((p) => !q || p[0].toLowerCase().includes(q.toLowerCase()));
    panel.replaceChildren(h("div.sec", q ? "Results" : "Guides & Recents"), ...list.map((p) =>
      h("button.place-row", { on: { click: () => choose(p) } }, h("span.pr-icon", sym(p[1].startsWith("Park") ? "rectangle-fill" : p[1].startsWith("City") ? "house" : "pin")),
        h("span", h("b", p[0]), h("small", p[1])))));
  }
  let pin = null, route = null;
  async function choose(p) {
    st.place = p;
    route?.remove(); route = null;
    pin?.remove();
    pin = h("div.map-pin", { style: { left: `${p[2]}px`, top: `${p[3]}px` } }, h("span.head", sym("pin")));
    layer.append(pin);
    flyTo(p[2], p[3], 1.5);
    await wait(250);
    animate(pin.firstChild, [{ transform: "translateY(-60px) scale(.6)", opacity: 0 }, { transform: "translateY(0) scale(1)", opacity: 1 }], "bouncy");
    panel.replaceChildren(h("div.place-card",
      h("button.back-link", { on: { click: () => { results(search.value); pin?.remove(); route?.remove(); } } }, sym("chevron-left"), "Results"),
      h("h2", p[0]), h("span.cat", p[1]), h("div.stars", "★★★★★".slice(0, Math.round(+p[4])), h("span", ` ${p[4]} · 2,184 ratings`)),
      h("div.pc-actions", h("button.pc-main", { on: { click: () => directions(p) } }, sym("car"), h("span", "Directions")), h("button", sym("phone"), h("span", "Call")), h("button", sym("globe"), h("span", "Website")), h("button", sym("ellipsis"), h("span", "More"))),
      h("div.pc-details", h("div", h("small", "Hours"), h("b", p[5])), h("div", h("small", "Address"), h("b", "San Francisco, CA")))));
    animate(panel.firstChild, [{ opacity: 0, transform: "translateY(8px)" }, { opacity: 1, transform: "none" }], "snappy");
  }
  function directions(p) {
    route?.remove();
    const [ux, uy] = ME, [tx, ty] = [p[2], p[3]];
    const midY = Math.max(ty, 520);
    const d = `M${ux} ${uy} L${ux} ${midY + 40} Q${ux} ${midY} ${ux - 40} ${midY} L${tx + 40} ${midY} Q${tx} ${midY} ${tx} ${midY - 40} L${tx} ${ty}`;
    route = h("div.route", { html: `<svg viewBox="0 0 1600 1200"><path d="${d}" class="casing"/><path d="${d}" class="line"/></svg>` });
    layer.prepend(route);
    const line = route.querySelector(".line"), len = line.getTotalLength();
    [line, route.querySelector(".casing")].forEach((pth) => pth.animate([{ strokeDasharray: `${len}`, strokeDashoffset: len }, { strokeDasharray: `${len}`, strokeDashoffset: 0 }], { duration: 1100, easing: "cubic-bezier(.3,0,.2,1)", fill: "forwards" }));
    const mins = Math.round(len / 55), miles = (len / 240).toFixed(1);
    panel.querySelector(".pc-details")?.replaceWith(h("div.eta", h("b", `${mins} min`), h("span", `${miles} mi · Fastest route`), h("button.btn.primary", "Go")));
    const r = viewport.getBoundingClientRect();
    const s = Math.min(1.2, (r.width - 360) / (Math.abs(tx - ux) + 300), (r.height - 120) / (Math.abs(ty - uy) + 300));
    st.s = Math.max(0.5, s); st.x = (r.width + 280) / 2 - ((ux + tx) / 2) * st.s; st.y = r.height / 2 - ((uy + ty) / 2) * st.s;
    apply(true);
  }

  search.addEventListener("input", () => results(search.value));
  search.addEventListener("keydown", (e) => { if (e.key === "Enter") { const p = PLACES.find((x) => x[0].toLowerCase().includes(search.value.toLowerCase())); if (p) choose(p); } });
  results("");
  apply(false);
  requestAnimationFrame(() => flyTo(780, 560, 0.62));
  return win;
}

registerApp("maps", openMaps, { View: [{ label: "Explore" }, { label: "Driving" }, { label: "Transit" }, { label: "Satellite" }, "-", { label: "Zoom In", kbd: "⌘+" }, { label: "Zoom Out", kbd: "⌘-" }] });
