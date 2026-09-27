// Global interaction polish: pointer-following light on glass, glass tooltips,
// and the icon-style / glass-material appearance settings.
import { h, state, bus, animate } from "./util.js";

const GLASS = ".pill, .cc-mod, #dock, #spotlight .field, #spotlight .cat, .dock-stack, .banner, .lk-field";

export function initPolish() {
  // Light follows the pointer across glass controls.
  let lit = null;
  addEventListener("pointermove", (e) => {
    const el = e.target.closest?.(GLASS);
    if (el !== lit) lit = el;
    if (!el) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty("--mx", `${e.clientX - r.left}px`);
    el.style.setProperty("--my", `${e.clientY - r.top}px`);
  }, { passive: true });

  // Tooltips: native title attributes become small glass labels after a pause.
  const tip = h("div.gg-tip.glass-menu", { hidden: true });
  document.getElementById("desktop").append(tip);
  let timer = 0, owner = null;
  const hide = () => { clearTimeout(timer); tip.hidden = true; if (owner?.dataset.tip) { owner.title = owner.dataset.tip; delete owner.dataset.tip; } owner = null; };
  addEventListener("mouseover", (e) => {
    const el = e.target.closest?.("#windows [title], #cc [title], #spotlight [title], .lights button");
    if (el === owner) return;
    hide();
    if (!el || !el.title) return;
    owner = el;
    el.dataset.tip = el.title;
    el.removeAttribute("title");                 // suppress the browser tooltip
    timer = setTimeout(() => {
      if (!el.isConnected) return;
      tip.textContent = el.dataset.tip;
      tip.hidden = false;
      const r = el.getBoundingClientRect(), t = tip.getBoundingClientRect();
      tip.style.left = `${Math.max(6, Math.min(innerWidth - t.width - 6, r.left + r.width / 2 - t.width / 2))}px`;
      tip.style.top = `${r.bottom + 8 + t.height > innerHeight ? r.top - t.height - 8 : r.bottom + 8}px`;
      animate(tip, [{ opacity: 0, transform: "translateY(-3px)" }, { opacity: 1, transform: "none" }], "snappy");
    }, 700);
  });
  addEventListener("mouseout", (e) => { if (owner && !owner.contains(e.relatedTarget)) hide(); });
  addEventListener("mousedown", hide, true);

  // Appearance: icon style and Liquid Glass material.
  const HUES = { blue: 180, purple: 240, pink: 300, red: 320, orange: 350, yellow: 10, green: 90, graphite: 0 };
  const apply = () => {
    const root = document.documentElement;
    root.dataset.icons = state.iconStyle ?? "default";
    root.dataset.glass = state.glass ?? "clear";
    root.style.setProperty("--tint-hue", `${HUES[state.accent] ?? 180}deg`);
  };
  bus.on("state", ({ key }) => { if (["iconStyle", "glass", "accent"].includes(key)) apply(); });
  apply();
}
