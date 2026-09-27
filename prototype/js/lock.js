// Boot splash and lock screen. Boot: the bridge mark over a progress hairline on
// black. Lock: large clock over the wallpaper, glass password capsule; unlocking
// zooms the wallpaper back and springs the desktop in.
import { h, sym, animate, wait, bus } from "./util.js";

const desk = () => document.getElementById("desktop");

export async function boot() {
  const bar = h("i");
  const el = h("div#boot", h("span.boot-logo", sym("logo")), h("div.boot-bar", bar));
  document.body.append(el);
  await wait(250);
  await bar.animate([{ width: "0%" }, { width: "35%", offset: 0.3 }, { width: "62%", offset: 0.55 }, { width: "100%" }], { duration: 1500, easing: "cubic-bezier(.4,0,.2,1)", fill: "forwards" }).finished;
  await wait(150);
  await el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 450, fill: "forwards" }).finished;
  el.remove();
}

let locked = null;
export function lock({ fromBoot = false } = {}) {
  if (locked) return locked.done;
  const clock = h("div.lk-time"), date = h("div.lk-date");
  const tick = () => {
    const d = new Date();
    date.textContent = d.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" });
    clock.textContent = d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M/, "");
  };
  tick();
  const timer = setInterval(tick, 5000);
  const input = h("input", { type: "password", placeholder: "Enter Password", autocomplete: "off" });
  const go = h("button.lk-go", { title: "Unlock" }, sym("arrow-up"));
  const field = h("label.lk-field.glass-regular", input, go);
  const status = h("div.lk-status", h("span.bat", h("i")), sym("wifi"));
  const el = h("div#lock", h("div.lk-veil"), status,
    h("div.lk-clock", date, clock),
    h("div.lk-user", h("span.avatar.lk-avatar", "GU"), h("b", "Golden User"), field, h("small", "Enter any password · type “wrong” to see a shake")));
  desk().append(el);
  desk().classList.add("locked");
  let resolve;
  const done = new Promise((r) => (resolve = r));
  locked = { done };

  animate(el.querySelector(".lk-clock"), [{ opacity: 0, transform: "translateY(-18px) scale(.96)" }, { opacity: 1, transform: "none" }], "smooth", { delay: fromBoot ? 150 : 0 });
  animate(el.querySelector(".lk-user"), [{ opacity: 0, transform: "translateY(20px)" }, { opacity: 1, transform: "none" }], "smooth", { delay: fromBoot ? 300 : 120 });
  if (!fromBoot) animate(el.querySelector(".lk-veil"), [{ opacity: 0 }, { opacity: 1 }], "smooth");
  setTimeout(() => input.focus(), 400);
  input.addEventListener("input", () => go.classList.toggle("show", !!input.value));

  async function attempt() {
    if (input.value.toLowerCase() === "wrong") {
      // The classic "no" shake.
      field.animate([0, -14, 12, -10, 8, -5, 3, 0].map((x) => ({ transform: `translateX(${x}px)` })), { duration: 420, easing: "ease-out" });
      input.value = ""; go.classList.remove("show");
      return;
    }
    clearInterval(timer);
    input.blur();
    const kids = [el.querySelector(".lk-clock"), el.querySelector(".lk-user"), status];
    kids.forEach((k, i) => k.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: i ? "translateY(24px) scale(.96)" : "translateY(-24px) scale(1.04)" }], { duration: 320, easing: "cubic-bezier(.4,0,1,1)", fill: "forwards" }));
    await wait(160);
    desk().classList.remove("locked");
    const wall = document.getElementById("wallpaper");
    animate(wall, [{ transform: "scale(1.06)" }, { transform: "none" }], "smooth", { duration: 900 });
    ["#menubar", "#dock-wrap", "#windows", "#desktop-icons"].forEach((sel, i) => {
      const n = document.querySelector(sel);
      if (n) animate(n, [{ opacity: 0, transform: sel === "#dock-wrap" ? "translateY(40px)" : sel === "#menubar" ? "translateY(-12px)" : "scale(.97)" }, { opacity: 1, transform: "none" }], "window", { delay: 60 + i * 40 });
    });
    await el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 420, fill: "forwards" }).finished;
    el.remove();
    locked = null;
    resolve();
    bus.emit("unlocked");
  }
  input.addEventListener("keydown", (e) => { if (e.key === "Enter") attempt(); e.stopPropagation(); });
  go.addEventListener("click", attempt);
  el.addEventListener("mousedown", (e) => { e.stopPropagation(); if (e.target !== input) setTimeout(() => input.focus()); });
  return done;
}
export const isLocked = () => !!locked;
