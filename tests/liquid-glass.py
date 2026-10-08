#!/usr/bin/env python3
"""Liquid Glass, system-wide (docs/LIQUID-GLASS.md):

- every shell surface drawn with Glass (and the menu bar's film) is a HyprGlass
  layer, with a mask threshold, in the compositor and in the preview harness;
- gg-hyprglass-sync, run against a stand-in hyprctl, sets the spec's physics,
  the specular rim per theme, window opacity per Glass setting, makes every
  window solid under Reduce Transparency and reloads once when it's turned off;
- hyprland.conf and the generated decoration block carry the spec's values,
  and every window and layer rule uses effects and match properties Hyprland
  0.56 knows (an unknown one is a config error, which stops the session).
"""
from __future__ import annotations

from pathlib import Path
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "compositor/hyprland/hyprglass-sync.sh"
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


# ------------------------------------------------------------ the surfaces
sync = SYNC.read_text()
names = re.search(r'layers:namespaces "([^"]+)"', sync).group(1).split(",")
thresholds = dict(p.split("=") for p in re.search(r'layers:namespace_mask_thresholds "([^"]+)"', sync).group(1).split(","))
for qml in sorted((ROOT / "shell").glob("*.qml")):
    text = qml.read_text()
    glassy = re.search(r"\bGlass\s*\{|component \w+: Glass", text) is not None or "HyprGlass" in text
    for ns in re.findall(r'namespace: "(gg-[^"]+)"', text):
        if ns in ("gg-wallpaper", "gg-launch", "gg-missioncontrol", "gg-lock-preview", "gg-applications"):
            continue  # no glass of their own (Applications draws its own blurred backdrop)
        if glassy:
            check(ns in names, f"{qml.name}: {ns} is drawn with Glass but isn't a HyprGlass layer")
for ns in names:
    check(ns in thresholds, f"{ns} has a mask threshold")
check(thresholds.get("gg-screenshot", "0") > "0.4", "the screenshot overlay's 40% dim never turns into glass")
preview = (ROOT / "tools/preview/qml/Quickshell/PreviewDesktop.qml").read_text()
listed = re.findall(r'"(gg-[^"]+)"', re.search(r"property var glass: \[(.*?)\]", preview, re.S).group(1))
check(sorted(listed) == sorted(names), f"the preview's glass list matches the compositor's: {sorted(set(names) ^ set(listed))}")
shown = dict(re.findall(r'"(gg-[^"]+)": ([\d.]+)', re.search(r"property var thresholds: \(\{(.*?)\}\)", preview, re.S).group(1)))
check(shown == thresholds, f"the preview's glass thresholds match the compositor's: {set(shown.items()) ^ set(thresholds.items())}")
for ns in ("gg-dock", "gg-controlcenter", "gg-spotlight", "gg-notifications", "gg-nearby", "gg-widgets"):
    # Glass casts a shadow up to ~22% opaque; its thinnest tint is 34%.
    check(0.22 < float(thresholds.get(ns, 0)) < 0.34, f"{ns}: shadows stay shadows and glass stays glass ({thresholds.get(ns)})")

# ---------------------------------------------------- the sync script, run
def run(theme: str, prefs: dict, flag: bool = False, built_for: str | None = "0.56.2",
        running: str = "0.56.2", incompatible: bool = False) -> tuple[list[str], bool, Path]:
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        (tmp / "bin").mkdir()
        log = tmp / "calls"
        (tmp / "bin/hyprctl").write_text('#!/bin/sh\necho "$*" >> "$CALLS"\n'
                                          'case "$1 $2" in "plugin list") echo "hyprglass hyprbars";; esac\nexit 0\n')
        (tmp / "bin/systemd-detect-virt").write_text("#!/bin/sh\necho none\n")
        (tmp / "bin/logger").write_text("#!/bin/sh\nexit 0\n")
        (tmp / "bin/pacman").write_text(f"#!/bin/sh\necho 'hyprland {running}-1'\n")
        for f in (tmp / "bin").iterdir():
            f.chmod(0o755)
        (tmp / "hyprglass.so").write_text("")
        if built_for:
            (tmp / "hyprglass.so.hyprland").write_text(built_for + "\n")
        if incompatible:
            (tmp / "hyprglass.so.incompatible").write_text("built for Hyprland 0.56.2; installed 0.57.0\n")
        (tmp / "config/golden-gate").mkdir(parents=True)
        (tmp / "config/golden-gate/desktop.json").write_text(json.dumps(prefs))
        (tmp / "run").mkdir()
        opaque = tmp / "run" / f"gg-glass-opaque-{os.getuid()}"
        if flag:
            opaque.write_text("")
        env = {**os.environ, "PATH": f"{tmp/'bin'}:/usr/bin:/bin", "CALLS": str(log), "XDG_CONFIG_HOME": str(tmp / "config"),
               "XDG_RUNTIME_DIR": str(tmp / "run"), "GG_HYPRGLASS_PLUGIN": str(tmp / "hyprglass.so"),
               "GG_HYPRBARS_PLUGIN": str(tmp / "none.so")}
        subprocess.run(["bash", str(SYNC), theme], env=env, check=True, timeout=30)
        return log.read_text().splitlines(), opaque.exists(), tmp


def kw(calls: list[str], key: str) -> str | None:
    found = [c[len("keyword " + key) + 1:] for c in calls if c.startswith(f"keyword {key} ")]
    return found[-1] if found else None


calls, _, _ = run("dark", {})
for key, value in [("plugin:hyprglass:blur_strength", "0.95"), ("plugin:hyprglass:refraction_strength", "0.55"),
                   ("plugin:hyprglass:chromatic_aberration", "0.08"), ("plugin:hyprglass:edge_thickness", "0.08"),
                   ("plugin:hyprglass:lens_distortion", "0.42"), ("plugin:hyprglass:skip_opaque_windows", "1"),
                   ("plugin:hyprglass:manage_window_blur", "1"), ("plugin:hyprglass:layers:manage_blur", "1"),
                   ("plugin:hyprglass:layers:mask_mode", "auto"), ("plugin:hyprglass:dark:vibrancy_darkness", "0.15"),
                   ("decoration:active_opacity", "1.0"), ("decoration:inactive_opacity", "1.0"),
                   ("plugin:hyprglass:glass_opacity", "0.58"),
                   ("general:col.active_border", "rgba(ffffff66) rgba(ffffff11) 45deg"),
                   ("general:col.inactive_border", "rgba(ffffff22) rgba(00000011) 45deg")]:
    check(kw(calls, key) == value, f"dark, Clear glass: {key} = {value} (got {kw(calls, key)!r})")
calls, _, _ = run("light", {"glass": "tinted"})
check(kw(calls, "general:col.active_border") == "rgba(ffffffb3) rgba(0000001f) 45deg", "light: the rim darkens on its far side")
check(kw(calls, "decoration:active_opacity") == "1.0", "Tinted glass: window contents solid too")
check(kw(calls, "plugin:hyprglass:glass_opacity") == "0.76", "Tinted glass: the glass a little more solid")
calls, flagged, _ = run("dark", {"reduceTransparency": True})
check(kw(calls, "decoration:active_opacity") == "1.0" and kw(calls, "decoration:inactive_opacity") == "1.0",
      "Reduce Transparency: windows solid")
check("keyword windowrule match:class .*, opaque on" in calls and flagged, "Reduce Transparency: solid over the per-app rules too")
calls, _, _ = run("dark", {"glassSolidity": 0.5})
check((kw(calls, "decoration:active_opacity"), kw(calls, "decoration:inactive_opacity")) == ("1.0", "1.0"),
      "the Transparency slider never fades window contents")
check(kw(calls, "plugin:hyprglass:glass_opacity") == "0.77",
      f"the Transparency slider halfway: the glass halfway to solid (got {kw(calls, 'plugin:hyprglass:glass_opacity')})")
calls, flagged, _ = run("dark", {"glassSolidity": 1})
check(kw(calls, "decoration:active_opacity") == "1.0" and flagged, "the Glass slider at Solid: every window solid")
# The plugin goes only into the Hyprland it was built for; otherwise Hyprland's
# own blur keeps windows frosted and readable.
calls, _, _ = run("dark", {})
check(kw(calls, "decoration:blur:enabled") == "0", "with the plugin, Hyprland's blur is off (one pipeline)")
for case, kwargs in (("another Hyprland", {"running": "0.57.0"}), ("no build stamp", {"built_for": None}),
                     ("marked incompatible", {"incompatible": True})):
    calls, _, _ = run("dark", {}, **kwargs)
    check(not any(c.startswith("plugin load") and "hyprglass" in c for c in calls), f"{case}: the plugin isn't loaded")
    check(kw(calls, "decoration:blur:enabled") == "1", f"{case}: Hyprland's own blur instead")
    check(kw(calls, "plugin:hyprglass:enabled") is None, f"{case}: no plugin settings")
calls, flagged, _ = run("dark", {}, flag=True)
check("reload" in calls and not flagged, "turning Reduce Transparency off reloads once to drop that rule")

# ------------------------------------------------------- the configuration
conf = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
for line in ("gaps_in = 8", "gaps_out = 16", "border_size = 1", "col.active_border = rgba(ffffff66) rgba(ffffff11) 45deg",
             "col.inactive_border = rgba(ffffff22) rgba(00000011) 45deg", "active_opacity = 1.0", "inactive_opacity = 1.0"):
    check(line in conf, f"hyprland.conf: {line}")
deco = (ROOT / "design/dist/hyprland-motion.conf").read_text()
for line in ("size = 12", "passes = 4", "new_optimizations = true", "ignore_opacity = false", "vibrancy = 0.35",
             "vibrancy_darkness = 0.15", "contrast = 1.2", "brightness = 1.1", "noise = 0.015", "popups = true",
             "popups_ignorealpha = 0.3", "range = 30", "render_power = 4", "color = rgba(00000045)"):
    check(line in deco, f"blur and shadow: {line}")
check("opacity 0.97 0.96" in conf and "com\\.mitchellh\\.ghostty" in conf, "the terminal is a little clearer")
check(" override" not in "\n".join(l for l in conf.splitlines() if "opacity" in l and l.startswith("windowrule")),
      "no app's opacity is fixed outright: the Glass slider moves every window")
check("match:fullscreen 1, opaque on" in conf and "match:content ^(video|game)$, opaque on" in conf, "full screen, video and games stay solid")

# Effects and match properties in Hyprland 0.56.2 (src/desktop/rule/…).
WINDOW_EFFECTS = {"float", "tile", "fullscreen", "maximize", "fullscreen_state", "move", "size", "center", "pseudo",
                  "monitor", "workspace", "no_initial_focus", "pin", "group", "suppress_event", "content", "no_close_for",
                  "scrolling_width", "rounding", "rounding_power", "persistent_size", "animation", "border_color",
                  "idle_inhibit", "opacity", "tag", "max_size", "min_size", "border_size", "allows_input", "dim_around",
                  "decorate", "focus_on_activate", "keep_aspect_ratio", "nearest_neighbor", "no_anim", "no_blur", "no_dim",
                  "no_focus", "no_follow_mouse", "no_max_size", "no_shadow", "no_shortcuts_inhibit", "opaque", "force_rgbx",
                  "sync_fullscreen", "immediate", "xray", "render_unfocused", "no_screen_share", "no_vrr", "no_auto_hdr",
                  "tonemap", "scroll_mouse", "scroll_touchpad", "stay_focused", "confine_pointer"}
LAYER_EFFECTS = {"no_anim", "blur", "blur_popups", "ignore_alpha", "dim_around", "xray", "animation", "order", "above_lock",
                 "no_screen_share"}
PROPS = {"class", "title", "initial_class", "initial_title", "float", "tag", "xwayland", "fullscreen", "pin", "focus",
         "group", "modal", "fullscreen_state_internal", "fullscreen_state_client", "workspace", "content", "xdg_tag",
         "namespace"}
for kind, effects in (("windowrule", WINDOW_EFFECTS), ("layerrule", LAYER_EFFECTS)):
    for rule in re.findall(rf"^{kind} = (.+?)(?:\s+#.*)?$", conf, re.M):
        for part in [p.strip() for p in rule.split(",")]:
            word = part.split()[0]
            if word.startswith("match:"):
                check(word[6:] in PROPS, f"{kind}: unknown match property {word!r}")
            else:
                check(word in effects, f"{kind}: unknown effect {word!r} in {rule!r}")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Liquid Glass: every glass surface registered; spec physics, rims and opacity per setting; valid rules")
