// Music: album grid with hover play buttons, album detail with a live
// equaliser on the playing row, and a glass "LCD" player in the toolbar that
// drives the system Now Playing module.
import { h, sym, genArt, animate, state, bus } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp } from "../apps.js";

const ALBUMS = [
  ["Fog Horns", "The Presidio Quartet", "Chamber · 2026"], ["Golden Hour", "Marina Lights", "Electronic · 2026"], ["Bay Drive", "Coastline", "Indie · 2025"],
  ["Cable Cars", "Hyde & Powell", "Jazz · 2025"], ["Night Market", "Neon Tides", "Synthwave · 2026"], ["Karl the Fog", "Sutro", "Ambient · 2024"],
  ["Ocean Beach", "The Breakers", "Surf Rock · 2025"], ["Lombard", "Switchbacks", "Pop · 2026"], ["Twin Peaks", "Summit", "Alternative · 2024"],
  ["Mission Murals", "Valencia St.", "Latin · 2025"], ["Alcatraz Blues", "The Rock", "Blues · 2023"], ["Sunset District", "Ninth Avenue", "Lo-fi · 2026"],
];
const TRACKS = ["Opening", "Low Tide", "Crosswinds", "Under the Span", "Marine Layer", "Anchor", "Headlands", "Last Ferry"];
const art = (a) => genArt(a[0] + a[1]);

function openMusic() {
  const sidebar = h("div");
  const body = h("div.music-body");
  let view = "grid", album = null, progressTimer = 0;

  // Toolbar player
  const lcdArt = h("img.lcd-art", { alt: "" });
  const lcdTitle = h("b"), lcdSub = h("span");
  const lcdBar = h("i");
  const playBtn = tb("play", { title: "Play", click: () => (state.playing = !state.playing) });
  const lcd = h("div.pill.lcd", lcdArt, h("div.lcd-text", lcdTitle, lcdSub), h("div.lcd-progress", lcdBar));
  const win = createWindow({
    app: "music", w: 1080, h: 680, sidebar, sidebarWidth: 210, className: "music", content: body,
    toolbar: [pill(tb("shuffle", { title: "Shuffle" }), tb("backward", { title: "Previous", click: () => step(-1) }), playBtn, tb("forward", { title: "Next", click: () => step(1) }), tb("repeat", { title: "Repeat" })),
      h("div.grow"), lcd, h("div.grow"), pill(tb("quote", { title: "Lyrics" }), tb("list", { title: "Playing Next" })), pill(tb("airplay", { title: "AirPlay" }))],
  });

  const side = (icon, label, on) => h("div.side-row", { className: `side-row ${on ? "sel" : ""}`, on: { click: () => { view = "grid"; album = null; render(); } } }, sym(icon), label);
  sidebar.replaceChildren(h("label.side-search", sym("search"), h("input", { placeholder: "Search" })),
    side("house", "Home"), side("sparkles", "New"), side("broadcast", "Radio"),
    h("div.sec", "Library"), side("clock", "Recently Added", true), side("person", "Artists"), side("rectangle-fill", "Albums"), side("music", "Songs"),
    h("div.sec", "Playlists"), side("list", "Golden Hour"), side("list", "Deep Focus"), side("list", "Bay Drive"));

  function play(a, track = 0) {
    state.nowPlaying = { title: TRACKS[track], artist: a[1], album: a[0], art: art(a), track, albumIndex: ALBUMS.indexOf(a), progress: 0 };
    state.playing = true;
  }
  function step(d) {
    const np = state.nowPlaying; if (!np?.albumIndex && np?.albumIndex !== 0) return;
    const a = ALBUMS[np.albumIndex];
    play(a, (np.track + d + TRACKS.length) % TRACKS.length);
  }

  function render() {
    if (view === "album" && album) return renderAlbum();
    body.replaceChildren(h("h1.large-title", "Recently Added"),
      h("div.albums", ALBUMS.map((a) => h("div.album", { on: { click: (e) => { if (!e.target.closest(".play-over")) { album = a; view = "album"; render(); } } } },
        h("div.cover", h("img", { src: art(a), alt: "" }), h("button.play-over.glass-regular", { title: "Play", on: { click: () => play(a) } }, sym("play"))),
        h("b", a[0]), h("span", a[1])))));
    animate(body, [{ opacity: 0 }, { opacity: 1 }], "smooth");
  }
  function renderAlbum() {
    const a = album, np = state.nowPlaying;
    body.replaceChildren(h("button.back-link", { on: { click: () => { view = "grid"; render(); } } }, sym("chevron-left"), "Recently Added"),
      h("div.album-head", h("img.album-art", { src: art(a), alt: "" }),
        h("div", h("h1", a[0]), h("h2", a[1]), h("span.meta", a[2]),
          h("div.album-actions", h("button.btn.primary", { on: { click: () => play(a) } }, sym("play"), "Play"), h("button.btn", { on: { click: () => play(a, Math.floor(Math.random() * TRACKS.length)) } }, sym("shuffle"), "Shuffle")))),
      h("div.tracks", TRACKS.map((t, i) => {
        const playing = np?.album === a[0] && np.track === i;
        return h("div.track", { className: `track ${playing ? "playing" : ""}`, on: { dblclick: () => play(a, i) } },
          h("span.no", playing ? h("span.eq", { className: `eq ${state.playing ? "" : "paused"}` }, h("i"), h("i"), h("i")) : String(i + 1)),
          h("span.t", t), h("span.d", `${3 + (i % 3)}:${String((i * 17) % 60).padStart(2, "0")}`));
      })));
    const img = body.querySelector(".album-art");
    animate(img, [{ transform: "scale(.92)", opacity: 0.4 }, { transform: "none", opacity: 1 }], "bouncy");
  }

  function syncPlayer() {
    const np = state.nowPlaying;
    playBtn.replaceChildren(sym(state.playing ? "pause" : "play"));
    lcd.classList.toggle("empty", !np);
    if (np) { lcdArt.src = np.art ?? art(ALBUMS[0]); lcdTitle.textContent = np.title; lcdSub.textContent = `${np.artist} — ${np.album}`; }
    else { lcdTitle.textContent = ""; lcdSub.textContent = ""; }
    lcdBar.style.width = `${(np?.progress ?? 0) * 100}%`;
    if (view === "album") renderAlbum();
  }
  const offs = [bus.on("state:nowPlaying", syncPlayer), bus.on("state:playing", syncPlayer)];
  progressTimer = setInterval(() => {
    const np = state.nowPlaying;
    if (!state.playing || !np) return;
    np.progress = Math.min(1, (np.progress ?? 0) + 1 / 200);
    lcdBar.style.width = `${np.progress * 100}%`;
    if (np.progress >= 1) step(1);
  }, 1000);
  win.onClose = () => { clearInterval(progressTimer); offs.forEach((off) => off()); };

  render();
  syncPlayer();
  return win;
}

registerApp("music", openMusic, {
  Controls: [{ label: "Play", kbd: "Space", action: () => (state.playing = !state.playing) }, { label: "Next", kbd: "⌘→" }, { label: "Previous", kbd: "⌘←" }, "-", { label: "Shuffle", icon: "shuffle" }, { label: "Repeat", icon: "repeat" }],
});
export { ALBUMS };
