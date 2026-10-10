// Weather: city cards, a live sky (drifting fog, rain, stars or sun glow),
// hourly and 10-day forecasts on glass cards and detail tiles.
import { h, sym, animate } from "../util.js";
import { createWindow, pill, tb } from "../wm.js";
import { registerApp } from "../apps.js";

const ICON = {
  sun: `<circle cx="12" cy="12" r="4.6" fill="#FFD60A"/><g stroke="#FFD60A" stroke-width="1.8" stroke-linecap="round"><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M5.3 18.7l1.6-1.6M17.1 6.9l1.6-1.6"/></g>`,
  cloud: `<path d="M7 19a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 10.5a4.3 4.3 0 0 1-.5 8.5z" fill="#fff"/>`,
  "cloud-sun": `<circle cx="9" cy="8.5" r="3.8" fill="#FFD60A"/><path d="M8.5 20a4 4 0 0 1-.5-8 5.4 5.4 0 0 1 10.3 1.4 3.4 3.4 0 0 1-.4 6.6z" fill="#fff"/>`,
  rain: `<path d="M7 15.5a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 7a4.3 4.3 0 0 1-.5 8.5z" fill="#E5E5EA"/><g stroke="#64D2FF" stroke-width="1.9" stroke-linecap="round"><path d="M8.5 18l-1 3M12.5 18l-1 3M16.5 18l-1 3"/></g>`,
  moon: `<path d="M18.5 15.2A7.5 7.5 0 0 1 9 5.7a7.5 7.5 0 1 0 9.5 9.5z" fill="#FFE58F"/><path d="M17 4.5l.5 1.3 1.3.5-1.3.5-.5 1.3-.5-1.3-1.3-.5 1.3-.5z" fill="#fff"/>`,
  fog: `<path d="M7 13.5a4.5 4.5 0 0 1-.6-9A6 6 0 0 1 18 5a4.3 4.3 0 0 1-.5 8.5z" fill="#E5E5EA"/><g stroke="#fff" stroke-width="1.8" stroke-linecap="round" opacity=".85"><path d="M4 17h16M6 20.5h12"/></g>`,
};
const wx = (k, size = 26) => h("span.wx-icon", { style: { width: `${size}px`, height: `${size}px` }, html: `<svg viewBox="0 0 24 24">${ICON[k]}</svg>` });

const CITIES = [
  { name: "San Francisco", time: "9:41 PM", sky: "fog", temp: 64, cond: "Fog", hi: 68, lo: 55, icon: "fog", uv: 0, wind: 12, dir: 250, hum: 84, vis: 3, feels: 62, sunset: "7:02 PM", sunrise: "6:58 AM", note: "Fog will continue through the night. Wind gusts are up to 18 mph." },
  { name: "Cupertino", time: "9:41 PM", sky: "night", temp: 72, cond: "Clear", hi: 91, lo: 62, icon: "moon", uv: 0, wind: 4, dir: 320, hum: 38, vis: 10, feels: 72, sunset: "7:05 PM", sunrise: "6:57 AM", note: "Clear conditions will continue for the rest of the night." },
  { name: "Tokyo", time: "1:41 PM", sky: "rain", temp: 71, cond: "Rain", hi: 74, lo: 66, icon: "rain", uv: 2, wind: 9, dir: 120, hum: 92, vis: 5, feels: 73, sunset: "5:36 PM", sunrise: "5:31 AM", note: "Rain expected around 4 PM. Take an umbrella." },
  { name: "Sydney", time: "2:41 PM", sky: "day", temp: 68, cond: "Partly Cloudy", hi: 72, lo: 57, icon: "cloud-sun", uv: 6, wind: 11, dir: 40, hum: 55, vis: 10, feels: 68, sunset: "5:48 PM", sunrise: "5:47 AM", note: "Partly cloudy conditions will continue for the rest of the day." },
  { name: "Reykjavik", time: "4:41 AM", sky: "night", temp: 41, cond: "Clear", hi: 45, lo: 36, icon: "moon", uv: 0, wind: 15, dir: 10, hum: 70, vis: 10, feels: 34, sunset: "7:21 PM", sunrise: "7:22 AM", note: "Aurora activity is high tonight. Skies stay clear until dawn." },
];
const SKY = { fog: ["#7b8a9c", "#aebbc9"], night: ["#0b1026", "#28427a"], rain: ["#3a4c61", "#6b7f96"], day: ["#2f7fe0", "#8ec5fc"] };

function sky(kind) {
  const el = h("div.sky", { style: { background: `linear-gradient(180deg, ${SKY[kind][0]}, ${SKY[kind][1]})` } });
  const rnd = (a, b) => a + Math.random() * (b - a);
  if (kind === "fog" || kind === "day" || kind === "rain")
    for (let i = 0; i < 7; i++) el.append(h("i.cloud", { style: { top: `${rnd(-5, 45)}%`, left: `${rnd(-20, 80)}%`, width: `${rnd(300, 600)}px`, height: `${rnd(90, 180)}px`, opacity: kind === "fog" ? rnd(0.25, 0.45) : rnd(0.15, 0.3), animationDuration: `${rnd(50, 90)}s`, animationDelay: `-${rnd(0, 60)}s` } }));
  if (kind === "rain") for (let i = 0; i < 80; i++) el.append(h("i.drop", { style: { left: `${rnd(0, 100)}%`, animationDuration: `${rnd(0.5, 0.9)}s`, animationDelay: `-${rnd(0, 1)}s`, opacity: rnd(0.2, 0.5) } }));
  if (kind === "night") for (let i = 0; i < 70; i++) el.append(h("i.star", { style: { left: `${rnd(0, 100)}%`, top: `${rnd(0, 70)}%`, animationDelay: `-${rnd(0, 4)}s`, transform: `scale(${rnd(0.5, 1.3)})` } }));
  if (kind === "day") el.append(h("i.sunglow"));
  return el;
}

function openWeather() {
  let city = CITIES[0];
  const sidebar = h("div");
  const main = h("div.wx-main");
  const bg = h("div.wx-bg");
  const win = createWindow({
    app: "weather", w: 1060, h: 700, sidebar, sidebarWidth: 250, overlaySidebar: true, className: "weather", content: h("div.wx", bg, main),
    toolbar: [h("div.grow"), pill(tb("list", { title: "Cities" })), pill(tb("plus", { title: "Add City" }))],
  });
  main.addEventListener("scroll", () => win.main.classList.toggle("scrolled", main.scrollTop > 2), { passive: true });

  function renderSide() {
    sidebar.replaceChildren(h("label.side-search", sym("search"), h("input", { placeholder: "Search for a city" })),
      ...CITIES.map((c) => h("button.city", { className: `city ${c === city ? "sel" : ""}`, style: { background: `linear-gradient(180deg, ${SKY[c.sky][0]}, ${SKY[c.sky][1]})` }, on: { click: () => { city = c; render(); } } },
        h("div", h("b", c === CITIES[0] ? "My Location" : c.name), h("small", c === CITIES[0] ? c.name : c.time), h("span.cc", c.cond)),
        h("div.cr", h("span.ct", `${c.temp}°`), h("small", `H:${c.hi}° L:${c.lo}°`)))));
  }

  function render() {
    renderSide();
    const old = bg.firstChild;
    const next = sky(city.sky);
    bg.append(next);
    animate(next, [{ opacity: 0 }, { opacity: 1 }], "smooth").then(() => old?.remove());
    const c = city;
    // Hour labels start from the city's local time.
    const [hh, rest] = c.time.split(":"), h0 = (+hh % 12) + (rest.includes("PM") ? 12 : 0);
    const hourLabel = (i) => { const hr = (h0 + i) % 24; return `${hr % 12 || 12}${hr < 12 ? "AM" : "PM"}`; };
    const hours = Array.from({ length: 12 }, (_, i) => [i ? hourLabel(i) : "Now", i === 0 ? c.icon : i < 4 ? c.icon : i < 8 ? (c.sky === "night" ? "moon" : "cloud") : c.sky === "night" ? "cloud-sun" : "sun", c.temp - Math.round(Math.sin(i / 3) * 4) - Math.floor(i / 3)]);
    const days = ["Today", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon"].map((d, i) => [d, ["cloud-sun", "sun", "cloud", "rain", "sun", "cloud-sun", "fog", "sun", "cloud", "sun"][(i + c.temp) % 10], c.lo - 3 + ((i * 7) % 6), c.hi - 2 + ((i * 5) % 7)]);
    const min = Math.min(...days.map((d) => d[2])), max = Math.max(...days.map((d) => d[3]));
    const tile = (icon, title, value, sub, extra) => h("div.wx-card.tile", h("div.wx-h", sym(icon), title), h("div.tv", value), extra ?? null, sub ? h("div.ts", sub) : null);
    main.replaceChildren(
      h("header.wx-hero", h("h1", c === CITIES[0] ? "My Location" : c.name), c === CITIES[0] ? h("div.home", c.name) : null, h("div.temp", `${c.temp}°`), h("div.cond", c.cond), h("div.hl", `H:${c.hi}°  L:${c.lo}°`)),
      h("div.wx-card.hourly", h("p", c.note), h("div.hours", hours.map(([t, i, v]) => h("div.hour", h("small", t), wx(i), h("b", `${v}°`))))),
      h("div.wx-grid",
        h("div.wx-card.tenday", h("div.wx-h", sym("calendar"), "10-Day Forecast"), ...days.map(([d, i, lo, hi], idx) => h("div.day",
          h("b", d), wx(i, 24), h("span.lo", `${lo}°`),
          h("span.t-range", h("i", { style: { left: `${((lo - min) / (max - min)) * 100}%`, right: `${100 - ((hi - min) / (max - min)) * 100}%` } }, idx === 0 ? h("em", { style: { left: `${((c.temp - lo) / Math.max(1, hi - lo)) * 100}%` } }) : null)),
          h("span.hi", `${hi}°`)))),
        h("div.tiles",
          tile("sun", "UV Index", String(c.uv), c.uv < 3 ? "Low for the rest of the day." : "Use sun protection until 4 PM.", h("div.uvbar", h("em", { style: { left: `${(c.uv / 11) * 100}%` } }))),
          tile("sunset", "Sunset", c.sunset, `Sunrise: ${c.sunrise}`, h("div.sunarc", { html: `<svg viewBox="0 0 100 34"><path d="M0 30 Q50 -18 100 30" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="1.5"/><line x1="0" y1="24" x2="100" y2="24" stroke="rgba(255,255,255,.3)" stroke-width=".8"/><circle cx="82" cy="18" r="3" fill="#fff"/></svg>` })),
          h("div.wx-card.tile.wind", h("div.wx-h", sym("wind"), "Wind"), h("div.dial", h("span.n", "N"), h("span.e", "E"), h("span.s", "S"), h("span.w", "W"),
            h("i.needle", { style: { transform: `rotate(${c.dir}deg)` } }), h("b", String(c.wind), h("small", "mph")))),
          tile("thermometer", "Feels Like", `${c.feels}°`, c.feels < c.temp ? "Wind is making it feel cooler." : "Similar to the actual temperature."),
          tile("drop", "Humidity", `${c.hum}%`, `The dew point is ${c.temp - Math.round((100 - c.hum) / 5)}° right now.`),
          tile("eye", "Visibility", `${c.vis} mi`, c.vis < 5 ? "Fog is reducing visibility." : "Perfectly clear view."))));
    main.scrollTop = 0;
    [...main.children].forEach((el, i) => animate(el, [{ opacity: 0, transform: "translateY(12px)" }, { opacity: 1, transform: "none" }], "snappy", { delay: i * 50 }));
  }
  render();
  return win;
}

registerApp("weather", openWeather, { View: [{ label: "Hourly Forecast" }, { label: "10-Day Forecast" }, "-", { label: "Fahrenheit", checked: true }, { label: "Celsius" }] });
