// Calendar: month, week, day and year views with a mini-month sidebar,
// calendar toggles, sliding navigation and glass event popovers.
import { h, sym, animate } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp } from "../apps.js";

const TODAY = new Date(2026, 8, 26);
const CALS = { home: ["Home", "#0a84ff"], work: ["Work", "#bf5af2"], family: ["Family", "#30d158"], gg: ["Golden Gate", "#ff9f0a"] };
const EV = [
  [2026, 8, 1, 10, 1, "Sprint planning", "work"], [2026, 8, 3, 18.5, 2, "Climbing", "home"], [2026, 8, 7, 0, 24, "Labor Day", "family"],
  [2026, 8, 9, 14, 1, "Icon review", "gg"], [2026, 8, 11, 9, 1.5, "Motion workshop", "gg"], [2026, 8, 14, 12, 1, "Lunch with Rosa", "home"],
  [2026, 8, 16, 16, 1, "Dentist", "home"], [2026, 8, 18, 19, 2, "Jonah's birthday", "family"], [2026, 8, 21, 10, 1, "1:1 Maya", "work"],
  [2026, 8, 22, 15, 1.5, "Hyprland plugin sync", "gg"], [2026, 8, 24, 9, 1, "Standup", "work"], [2026, 8, 25, 13, 1, "Quickshell pairing", "gg"],
  [2026, 8, 26, 10, 1, "Design review · Liquid Glass", "work"], [2026, 8, 26, 14, 0.75, "Ship Golden Gate 0.1", "gg"], [2026, 8, 26, 18.75, 1.5, "Sunset walk, Crissy Field", "home"],
  [2026, 8, 28, 11, 1, "ISO smoke test", "gg"], [2026, 8, 29, 17, 1, "Yoga", "home"], [2026, 8, 30, 9, 2, "Quarterly review", "work"],
  [2026, 9, 2, 20, 2, "Movie night", "family"], [2026, 9, 5, 10, 1, "Accessibility audit", "gg"], [2026, 7, 28, 10, 1, "Offsite", "work"],
].map(([y, m, d, start, len, title, cal]) => ({ date: new Date(y, m, d), start, len, title, cal }));
const sameDay = (a, b) => a.toDateString() === b.toDateString();
const fmtTime = (hrs) => { const hh = Math.floor(hrs), mm = Math.round((hrs - hh) * 60); return `${((hh + 11) % 12) + 1}:${String(mm).padStart(2, "0")} ${hh < 12 ? "AM" : "PM"}`; };
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

function openCalendar() {
  const st = { view: "month", cursor: new Date(TODAY), hidden: new Set() };
  const sidebar = h("div");
  const body = h("div.cal-body");
  const title = h("div.title");
  const seg = Object.fromEntries(["day", "week", "month", "year"].map((v) => [v, tb(v[0].toUpperCase() + v.slice(1), { text: true, click: () => { st.view = v; render(0); } })]));
  const win = createWindow({
    app: "calendar", w: 1100, h: 700, sidebar, sidebarWidth: 220, className: "calendar", content: body,
    toolbar: [title, h("div.grow"), pill(tb("Today", { text: true, click: () => { st.cursor = new Date(TODAY); render(0); } })),
      pill(tb("chevron-left", { title: "Previous", click: () => move(-1) }), div(), tb("chevron-right", { title: "Next", click: () => move(1) })),
      pill(seg.day, seg.week, seg.month, seg.year), pill(tb("plus", { title: "New Event" })), h("label.pill.search", sym("search"), h("input", { placeholder: "Search" }))],
  });

  function move(d) {
    const c = st.cursor;
    if (st.view === "month") c.setMonth(c.getMonth() + d, 1);
    else if (st.view === "year") c.setFullYear(c.getFullYear() + d);
    else c.setDate(c.getDate() + d * (st.view === "week" ? 7 : 1));
    render(d);
  }
  const visible = (e) => !st.hidden.has(e.cal);

  function miniMonth() {
    const y = TODAY.getFullYear(), m = st.cursor.getMonth();
    const first = new Date(y, m, 1).getDay(), days = new Date(y, m + 1, 0).getDate();
    return h("div.mini", h("b", `${MONTHS[m]} ${st.cursor.getFullYear()}`),
      h("div.mini-grid", ..."SMTWTFS".split("").map((d) => h("span.dow", d)), ...Array.from({ length: first }, () => h("span")),
        ...Array.from({ length: days }, (_, i) => {
          const d = new Date(st.cursor.getFullYear(), m, i + 1);
          return h("span", { className: `${sameDay(d, TODAY) ? "today" : ""} ${EV.some((e) => sameDay(e.date, d)) ? "has" : ""}`, on: { click: () => { st.cursor = d; st.view = "day"; render(0); } } }, String(i + 1));
        })));
  }
  function renderSide() {
    sidebar.replaceChildren(miniMonth(), h("div.sec", "Golden"),
      ...Object.entries(CALS).map(([k, [name, color]]) => h("div.side-row.cal-row", { on: { click: () => { st.hidden.has(k) ? st.hidden.delete(k) : st.hidden.add(k); render(0); } } },
        h("span.check", { className: `check ${st.hidden.has(k) ? "" : "on"}`, style: { "--c": color } }, sym("checkmark")), name)));
  }

  function eventPopover(e, anchor) {
    document.querySelector(".cal-pop")?.remove();
    const r = anchor.getBoundingClientRect();
    const pop = h("div.cal-pop.glass-menu", h("div.cp-title", { style: { "--c": CALS[e.cal][1] } }, e.title),
      h("div.cp-row", sym("clock"), e.len >= 24 ? "All day" : `${e.date.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })} · ${fmtTime(e.start)} – ${fmtTime(e.start + e.len)}`),
      h("div.cp-row", sym("calendar"), CALS[e.cal][0]), h("div.cp-row", sym("bell"), "15 minutes before"));
    document.getElementById("desktop").append(pop);
    const pr = pop.getBoundingClientRect();
    pop.style.left = `${Math.min(innerWidth - pr.width - 8, r.right + 8)}px`;
    pop.style.top = `${Math.max(36, Math.min(innerHeight - pr.height - 8, r.top - 10))}px`;
    animate(pop, [{ opacity: 0, transform: "scale(.92)" }, { opacity: 1, transform: "none" }], "popover");
    const close = (ev) => { if (!pop.contains(ev.target)) { pop.remove(); removeEventListener("mousedown", close, true); } };
    setTimeout(() => addEventListener("mousedown", close, true));
  }
  const evChip = (e) => h("button.ev-chip", { style: { "--c": CALS[e.cal][1] }, on: { click: (ev) => { ev.stopPropagation(); eventPopover(e, ev.currentTarget); } } },
    h("i"), h("span", e.title), e.len < 24 ? h("small", fmtTime(e.start).replace(":00", "")) : null);

  function monthView() {
    const y = st.cursor.getFullYear(), m = st.cursor.getMonth();
    const start = new Date(y, m, 1 - new Date(y, m, 1).getDay());
    const cells = Array.from({ length: 42 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
    return h("div.month",
      h("div.m-head", ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((d) => h("span", d))),
      h("div.m-grid", cells.map((d) => {
        const evs = EV.filter((e) => sameDay(e.date, d) && visible(e)).sort((a, b) => a.start - b.start);
        return h("div.m-cell", { className: `m-cell ${d.getMonth() !== m ? "out" : ""} ${sameDay(d, TODAY) ? "today" : ""}`, on: { dblclick: () => { st.cursor = d; st.view = "day"; render(0); } } },
          h("span.num", d.getDate() === 1 ? `${MONTHS[d.getMonth()].slice(0, 3)} 1` : String(d.getDate())),
          ...evs.slice(0, 3).map(evChip), evs.length > 3 ? h("span.more", `${evs.length - 3} more`) : null);
      })));
  }

  function timeView(days) {
    const HOUR = 46;
    const col = (d) => {
      const evs = EV.filter((e) => sameDay(e.date, d) && visible(e) && e.len < 24);
      return h("div.t-col", { className: `t-col ${sameDay(d, TODAY) ? "today" : ""}` },
        ...evs.map((e) => h("button.t-ev", { style: { top: `${e.start * HOUR}px`, height: `${Math.max(22, e.len * HOUR - 3)}px`, "--c": CALS[e.cal][1] }, on: { click: (ev) => eventPopover(e, ev.currentTarget) } },
          h("b", e.title), h("span", fmtTime(e.start)))),
        sameDay(d, TODAY) ? h("div.now", { style: { top: `${21.68 * HOUR}px` } }) : null);
    };
    const grid = h("div.t-grid", { style: { "--hour": `${HOUR}px`, "--days": days.length } },
      h("div.t-gutter", Array.from({ length: 24 }, (_, i) => h("span", i ? fmtTime(i).replace(":00", "") : ""))),
      ...days.map(col));
    const wrap = h("div.week",
      h("div.w-head", { style: { "--days": days.length } }, h("span"), ...days.map((d) => h("div", { className: sameDay(d, TODAY) ? "today" : "" },
        h("small", d.toLocaleDateString("en-US", { weekday: "short" })), h("b", String(d.getDate()))))),
      h("div.w-allday", { style: { "--days": days.length } }, h("span", "all-day"), ...days.map((d) => h("div", EV.filter((e) => sameDay(e.date, d) && e.len >= 24 && visible(e)).map(evChip)))),
      h("div.w-scroll", grid));
    setTimeout(() => (wrap.querySelector(".w-scroll").scrollTop = 7.5 * HOUR));
    return wrap;
  }

  function yearView() {
    const y = st.cursor.getFullYear();
    return h("div.year", Array.from({ length: 12 }, (_, m) => {
      const first = new Date(y, m, 1).getDay(), days = new Date(y, m + 1, 0).getDate();
      return h("div.y-month", { on: { click: () => { st.cursor = new Date(y, m, 1); st.view = "month"; render(0); } } }, h("b", { className: m === TODAY.getMonth() && y === TODAY.getFullYear() ? "cur" : "" }, MONTHS[m]),
        h("div.mini-grid", ..."SMTWTFS".split("").map((d) => h("span.dow", d)), ...Array.from({ length: first }, () => h("span")),
          ...Array.from({ length: days }, (_, i) => h("span", { className: sameDay(new Date(y, m, i + 1), TODAY) ? "today" : "" }, String(i + 1)))));
    }));
  }

  function render(dir) {
    const c = st.cursor;
    Object.entries(seg).forEach(([k, b]) => b.classList.toggle("on", k === st.view));
    const weekStart = new Date(c.getFullYear(), c.getMonth(), c.getDate() - c.getDay());
    const label = st.view === "year" ? String(c.getFullYear()) : st.view === "day" ? c.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" }) : `${MONTHS[(st.view === "week" ? weekStart : c).getMonth()]} ${c.getFullYear()}`;
    title.replaceChildren(h("span.cal-title", h("b", label.split(" ")[0]), " ", label.split(" ").slice(1).join(" ")));
    body.className = `cal-body view-${st.view}`;
    body.replaceChildren(st.view === "month" ? monthView() : st.view === "year" ? yearView()
      : timeView(st.view === "day" ? [new Date(c)] : Array.from({ length: 7 }, (_, i) => new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + i))));
    if (dir) animate(body.firstChild, [{ transform: `translateX(${dir * 40}px)`, opacity: 0 }, { transform: "none", opacity: 1 }], "snappy");
    renderSide();
  }
  render(0);
  return win;
}

registerApp("calendar", openCalendar, {
  Calendar: [{ label: "New Event", kbd: "⌘N" }, { label: "New Calendar" }, "-", { label: "Go to Today", kbd: "⌘T" }, { label: "Go to Date…", kbd: "⇧⌘T" }],
});
