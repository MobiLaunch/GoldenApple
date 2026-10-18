#!/usr/bin/env python3
"""Liquid Glass, system-wide (docs/LIQUID-GLASS.md):

- every CitronOS shell surface drawn with Glass is a HyprGlass layer, with a
  mask threshold, in the compositor and in the preview harness (MacShell's
  bar, Dock and menus draw their own Liquid Glass, shell/macshell);
- gg-hyprglass-sync writes golden-gate/glass.lua with the spec's physics, the
  specular rim per theme, the glass's opacity per Glass setting, and makes
  every window solid under Reduce Transparency;
- hyprland.lua and the generated decoration block carry the spec's values
  (tests/hyprland-lua.py checks every rule and option against Hyprland 0.56).
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
layers = dict(p.split("=") for p in re.search(r"for ns in ((?:gg-[a-z-]+=[\d.]+ ?)+); do", sync).group(1).split())
names, thresholds = list(layers), layers
check("gg-applications" not in names, "Launchpad's blurred wallpaper is never a full-screen glass lens")
for qml in sorted((ROOT / "shell").glob("*.qml")):
    text = qml.read_text()
    glassy = re.search(r"\bGlass\s*\{|component \w+: Glass", text) is not None or "HyprGlass" in text
    for ns in re.findall(r'namespace: "(gg-[^"]+)"', text):
        if ns in ("gg-wallpaper", "gg-missioncontrol", "gg-applications", "gg-citronpods"):
            continue  # no glass of their own (Applications draws its own blurred backdrop)
        if glassy:
            check(ns in names, f"{qml.name}: {ns} is drawn with Glass but isn't a HyprGlass layer")
for ns in re.findall(r'namespace: "(mac[a-z-]*)"', (ROOT / "shell/macshell/MacBar.qml").read_text()):
    check(ns not in names, f"MacShell's {ns} draws its own glass: HyprGlass leaves it alone")
preview = (ROOT / "tools/preview/qml/Quickshell/PreviewDesktop.qml").read_text()
listed = re.findall(r'"(gg-[^"]+)"', re.search(r"property var glass: \[(.*?)\]", preview, re.S).group(1))
check(sorted(listed) == sorted(names), f"the preview's glass list matches the compositor's: {sorted(set(names) ^ set(listed))}")
shown = dict(re.findall(r'"(gg-[^"]+)": ([\d.]+)', re.search(r"property var thresholds: \(\{(.*?)\}\)", preview, re.S).group(1)))
check(shown == thresholds, f"the preview's glass thresholds match the compositor's: {set(shown.items()) ^ set(thresholds.items())}")
check("gg-citronpods" not in names, "native AirPods glass must not be blurred as a rectangular HyprGlass layer")
for ns in ("gg-nearby", "gg-tablet-home"):
    # Glass casts a shadow up to ~22% opaque; its thinnest tint is 34%.
    check(0.22 < float(thresholds.get(ns, 0)) < 0.34, f"{ns}: shadows stay shadows and glass stays glass ({thresholds.get(ns)})")


# ---------------------------------------------------- the sync script, run
def run(theme: str, prefs: dict, built_for: str | None = "0.56.2", running: str = "0.56.2",
        incompatible: bool = False, virt: str = "none") -> str:
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        (tmp / "bin").mkdir()
        (tmp / "bin/systemd-detect-virt").write_text(f"#!/bin/sh\necho {virt}\n")
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
        out = tmp / "glass.lua"
        env = {**os.environ, "PATH": f"{tmp/'bin'}:/usr/bin:/bin", "XDG_CONFIG_HOME": str(tmp / "config"),
               "GG_GLASS_LUA": str(out), "GG_HYPRGLASS_PLUGIN": str(tmp / "hyprglass.so"),
               "GG_HYPRBARS_PLUGIN": str(tmp / "none.so")}
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        subprocess.run(["bash", str(SYNC), theme], env=env, check=True, timeout=30)
        return out.read_text()


def has(lua: str, *parts: str) -> bool:
    return all(p in lua for p in parts)


lua = run("dark", {})
for part in ("blur_strength = 0.95", "refraction_strength = 0.55", "chromatic_aberration = 0.08", "edge_thickness = 0.08",
             "lens_distortion = 0.42", "manage_window_blur = true", "manage_blur = true", 'mask_mode = "auto"',
             "vibrancy_darkness = 0.15", "active_opacity = 1.0, inactive_opacity = 1.0", "glass_opacity = 0.58",
             'active_border = { colors = { "rgba(ffffff66)", "rgba(ffffff11)" }, angle = 45 }',
             'inactive_border = { colors = { "rgba(ffffff22)", "rgba(00000011)" }, angle = 45 }',
             'default_theme = "dark"', "if hl.plugin.hyprglass then"):
    check(part in lua, f"dark, Clear glass: {part}")
check("gg-reduce-transparency" not in lua, "Clear glass: windows keep their own opacity rules")
lua = run("light", {"glass": "tinted"})
check(has(lua, '"rgba(ffffffb3)", "rgba(0000001f)"'), "light: the rim darkens on its far side")
check("glass_opacity = 0.76" in lua, "Tinted glass: the glass a little more solid")
check("active_opacity = 1.0" in lua, "Tinted glass: window contents solid too")
lua = run("dark", {"reduceTransparency": True})
check('hl.window_rule({ name = "gg-reduce-transparency", match = { class = ".*" }, opaque = true })' in lua,
      "Reduce Transparency: every window solid, over the per-app rules too")
check("glass_opacity = 0.96" in lua, "Reduce Transparency: the glass nearly solid")
lua = run("dark", {"glassSolidity": 0.5})
check("active_opacity = 1.0, inactive_opacity = 1.0" in lua, "the Transparency slider never fades window contents")
check("glass_opacity = 0.77" in lua, "the Transparency slider halfway: the glass halfway to solid")
lua = run("dark", {"glassSolidity": 1})
check("gg-reduce-transparency" in lua, "the Glass slider at Solid: every window solid")
lua = run("dark", {}, virt="kvm")
check("blur_strength = 1.5" in lua and "glass_opacity = 0.80" in lua, "a virtual GPU gets its own optical profile")
# The plugin goes only into the Hyprland it was built for; otherwise Hyprland's
# own blur keeps windows frosted and readable.
lua = run("dark", {})
check("blur = { enabled = false }" in lua, "with the plugin, Hyprland's blur is off (one pipeline)")
for case, kwargs in (("another Hyprland", {"running": "0.57.0"}), ("no build stamp", {"built_for": None}),
                     ("marked incompatible", {"incompatible": True})):
    lua = run("dark", {}, **kwargs)
    check("hyprglass.so" not in lua.replace("HyprGlass is not used", ""), f"{case}: the plugin isn't loaded")
    check("blur = { enabled = true, size = 10, passes = 3 }" in lua, f"{case}: Hyprland's own blur instead")
    check("hg.config" not in lua, f"{case}: no plugin settings")

# ------------------------------------------------------- the configuration
conf = (ROOT / "compositor/hyprland/hyprland.lua").read_text()
for part in ("gaps_in = 8", "gaps_out = 16", "border_size = 1",
             'active_border = { colors = { "rgba(ffffff66)", "rgba(ffffff11)" }, angle = 45 }',
             'inactive_border = { colors = { "rgba(ffffff22)", "rgba(00000011)" }, angle = 45 }',
             "active_opacity = 1.0", "inactive_opacity = 1.0", 'part("glass")'):
    check(part in conf, f"hyprland.lua: {part}")
deco = (ROOT / "design/dist/hyprland-motion.lua").read_text()
for part in ("size = 12", "passes = 4", "new_optimizations = true", "ignore_opacity = false", "vibrancy = 0.35",
             "vibrancy_darkness = 0.15", "contrast = 1.2", "brightness = 1.1", "noise = 0.015", "popups = true",
             "popups_ignorealpha = 0.3", "range = 46", "render_power = 2", 'color = "rgba(00000034)"', "offset = { 0, 9 }"):
    check(part in deco, f"blur and shadow: {part}")
check('opacity = "0.97 0.96"' in conf and "com\\.mitchellh\\.ghostty" in conf, "the terminal is a little clearer")
check(" override" not in "\n".join(l for l in conf.splitlines() if "opacity =" in l),
      "no app's opacity is fixed outright: the Glass slider moves every window")
check('match = { fullscreen = true }, opaque = true' in conf and 'match = { content = "^(video|game)$" }, opaque = true' in conf,
      "full screen, video and games stay solid")

# Shell menus get no compositor blur: blur_popups covers a popup's whole
# surface, which is bigger than the menu, so it showed as a box round it.
check("blur_popups" not in conf, "shell menus have no compositor blur box round them (no blur_popups)")

# What shell glass bends is never drawn in the surface itself, only into its
# texture: toggled with the texture, it could show for a frame as a box of
# wallpaper (or plain blue) filling a menu popup's spare room round the menu.
backdrop = (ROOT / "shell/components/DesktopBackdrop.qml").read_text()
root_block = backdrop.split("\n    Image {", 1)[0]
check(re.search(r"^    visible: false$", root_block, re.M) is not None, "the shell's backdrop is never drawn in its surface (visible: false)")
check("hideSource" not in backdrop, "the shell's backdrop doesn't depend on hideSource to stay off screen")
check(not re.search(r"Rectangle \{[^}]*color: \"#", backdrop), "the shell's backdrop has no coloured placeholder to show")

# Window captures behind shell glass let go of a window as it closes: at
# Hyprland's closewindow, and through Quickshell's own list of windows, never a
# reference kept from the last refresh (copying a closed window could crash).
check('event.name === "closewindow") bd.windowClosed(' in backdrop, "a capture stops at Hyprland's closewindow")
check("captureSource: bd.shown && frame && !bd.closing[modelData] ? bd.toplevelOf(modelData) : null" in backdrop,
      "each capture finds its window in Quickshell's own list")
check("toplevel: t.wayland" not in backdrop, "no window kept from the last refresh")
check("Prefs.glassWindows" in backdrop, "window captures can be turned off (glassWindows)")
# Captures run on a clock (at most 30 a second, only while glass is bending
# them), never streaming every frame; menus, made and dropped all the time,
# capture no windows at all.
check("live: false" in backdrop and "interval: 33" in backdrop and "captureFrame()" in backdrop,
      "window captures are taken at most 30 times a second")
menu = (ROOT / "shell/components/MenuPopup.qml").read_text()
check("includeWindows: false" in menu, "menus capture no windows")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Liquid Glass: every glass surface registered; spec physics, rims and opacity per setting; valid rules")
