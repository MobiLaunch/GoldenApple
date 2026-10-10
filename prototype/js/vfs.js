// In-memory filesystem backing the Files app, Spotlight and the Desktop.
export const USER = "golden";

const d = (s) => new Date(s);
const f = (name, kind, date, size, extra = {}) => ({ name, kind, date: d(date), size, ...extra });
const dir = (name, children, date = "2026-09-01T10:00") => ({ name, kind: "folder", date: d(date), children });
const app = (name, id, date = "2026-09-15T09:00") => ({ name, kind: "app", app: id, date: d(date), size: 0 });

export const root = dir("System HD", [
  dir("Applications", [
    app("Calculator", "calculator"), app("Calendar", "calendar"), app("Files", "files"), app("Mail", "mail"),
    app("Maps", "maps"), app("Messages", "messages"), app("Music", "music"), app("Notes", "notes"),
    app("Photos", "photos"), app("Software", "store"), app("System Settings", "settings"), app("Terminal", "terminal"),
    app("Weather", "weather"), app("Web", "browser"),
  ]),
  dir("Users", [
    dir(USER, [
      dir("Desktop", [dir("Projects", [f("golden-gate-notes.md", "doc", "2026-09-24T18:02", 4200)]), f("Wallpaper Draft.png", "image", "2026-09-25T11:30", 2_400_000)]),
      dir("Documents", [
        dir("Design", [f("Liquid Glass Spec.pdf", "doc", "2026-09-20T15:10", 1_800_000), f("Motion Curves.key", "doc", "2026-09-18T09:44", 12_000_000)]),
        f("Roadmap.md", "doc", "2026-09-22T13:00", 8_100), f("Budget 2027.numbers", "doc", "2026-08-30T17:20", 310_000),
        f("Release Notes.txt", "doc", "2026-09-26T08:15", 2_100),
      ]),
      dir("Downloads", [f("inter-4.1.zip", "doc", "2026-09-10T12:00", 5_400_000), f("hyprland-0.51.tar.gz", "doc", "2026-09-12T19:40", 9_800_000), f("screenshot-ui.png", "image", "2026-09-26T20:05", 820_000)]),
      dir("Pictures", Array.from({ length: 9 }, (_, i) => f(`IMG_${1142 + i}.HEIC`, "image", `2026-06-${19 + (i % 9)}T19:${10 + i}`, 3_100_000 + i * 90_000))),
      dir("Music", [
        dir("Audio Files", [f("Field Recording 01.m4a", "audio", "2026-06-30T10:00", 6_000_000)], "2026-06-30T10:00"),
        f("zoo.m4a", "audio", "2026-06-30T12:20", 3_400_000), f("Strand.m4a", "audio", "2026-07-15T09:15", 4_100_000),
        f("Jetty.m4a", "audio", "2026-07-15T09:16", 3_900_000), f("Mistral.m4a", "audio", "2026-07-15T09:17", 5_200_000),
        f("Shoreline.m4a", "audio", "2026-07-15T09:18", 4_700_000), f("Drift.mov", "video", "2026-07-15T09:20", 48_000_000),
      ]),
      dir("Movies", [f("Bridge Timelapse.mov", "video", "2026-05-04T06:30", 310_000_000)]),
      dir("Cloud Drive", [dir("Shared Albums", [], "2026-09-02T10:00"), f("Trip Itinerary.pdf", "doc", "2026-09-14T08:30", 640_000), f("Keynote Draft.key", "doc", "2026-09-21T16:45", 22_000_000)], "2026-09-21T16:45"),
    ]),
  ]),
]);

export const home = () => resolve(`/Users/${USER}`);
export function resolve(path) {
  let node = root;
  for (const part of path.split("/").filter(Boolean)) {
    node = node.children?.find((c) => c.name === part);
    if (!node) return null;
  }
  return node;
}
export const join = (path, name) => (path === "/" ? "/" : path + "/") + name;
export const parentOf = (path) => path.split("/").slice(0, -1).join("/") || "/";

export function* walk(node = root, path = "") {
  for (const c of node.children ?? []) {
    const p = `${path}/${c.name}`;
    yield [c, p];
    if (c.children) yield* walk(c, p);
  }
}

export const iconFor = (n) => (n.kind === "app" ? n.app : { folder: "folder", doc: "document", image: "image", audio: "audio", video: "document" }[n.kind] ?? "document");
export const kindLabel = (n) => ({ folder: "Folder", app: "Application", doc: "Document", image: "Image", audio: "Audio", video: "Movie" }[n.kind]);
export function fmtSize(n) {
  if (n.kind === "folder") return "--";
  if (n.kind === "app") return "Zero KB";
  const u = ["bytes", "KB", "MB", "GB"];
  let s = n.size, i = 0;
  while (s >= 1000 && i < 3) { s /= 1000; i++; }
  return `${s < 10 && i ? s.toFixed(1) : Math.round(s)} ${u[i]}`;
}
export function fmtDate(date) {
  const now = new Date("2026-09-26T21:40");
  const t = date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  if (date.toDateString() === now.toDateString()) return `Today at ${t}`;
  if (now - date < 2 * 864e5 && now.getDate() - date.getDate() === 1) return `Yesterday at ${t}`;
  return `${date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })} at ${t}`;
}

// ------------------------------------------------------------------ mutations
export const TRASH = [];
export function remove(path) {
  const parent = resolve(parentOf(path));
  const i = parent?.children?.findIndex((c) => c.name === path.split("/").pop()) ?? -1;
  return i >= 0 ? parent.children.splice(i, 1)[0] : null;
}
export function uniqueName(dirPath, base) {
  const dir = resolve(dirPath);
  const taken = new Set((dir?.children ?? []).map((c) => c.name));
  if (!taken.has(base)) return base;
  const m = base.match(/^(.*?)(\.[^.]+)?$/);
  for (let i = 2; ; i++) if (!taken.has(`${m[1]} ${i}${m[2] ?? ""}`)) return `${m[1]} ${i}${m[2] ?? ""}`;
}
export function moveTo(path, destDir) {
  if (destDir === path || destDir.startsWith(path + "/") || parentOf(path) === destDir) return false;
  const dest = resolve(destDir);
  if (!dest?.children) return false;
  const node = remove(path);
  if (!node) return false;
  node.name = uniqueName(destDir, node.name);
  dest.children.push(node);
  return true;
}
export function trash(path) {
  const node = remove(path);
  if (node) TRASH.push(node);
  return node;
}
