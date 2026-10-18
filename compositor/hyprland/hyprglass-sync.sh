#!/usr/bin/env bash
# CitronOS → HyprGlass bridge.
# Writes ~/.config/hypr/golden-gate/glass.lua, which hyprland.lua loads: the
# version-matched plugins if available (HyprGlass, and hyprbars for title bars)
# and the current appearance/accessibility preferences. Hyprland reloads its
# config when the file changes, so it is only rewritten when something did.
# Safe to run repeatedly; runs at login and when the appearance changes.
#
#   gg-hyprglass-sync [dark|light]     (default: the gsettings colour scheme)
#   GG_GLASS_LUA=FILE                  write there instead (tests)
set -u

PLUGIN="${GG_HYPRGLASS_PLUGIN:-/usr/lib/golden-gate/hyprglass.so}"
BARS="${GG_HYPRBARS_PLUGIN:-/usr/lib/golden-gate/hyprbars.so}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate/desktop.json"
OUT="${GG_GLASS_LUA:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/golden-gate/glass.lua}"
THEME="${1:-}"

if [ -z "$THEME" ]; then
  scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
  case "$scheme" in *dark*) THEME=dark ;; *) THEME=light ;; esac
fi

LUA=""
add() { LUA="$LUA$1
"; }
# A Lua string literal (the values here are ours, but quote them anyway).
q() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

add "-- Written by gg-hyprglass-sync ($THEME) from Settings › Appearance and Accessibility."
add "-- It is rewritten when they change; your own settings go in hyprland.lua."

# ------------------------------------------------------------- title bars
# Apps that leave their title bar to the compositor (Qt and Electron apps from
# the App Store, X11 apps) get a macOS one: traffic lights on the left, the
# title centred. GTK apps and CitronOS's own draw theirs (hyprbars is built
# to leave them alone, see distro/hyprbars/patch.py).
if [ -r "$BARS" ]; then
  if [ "$THEME" = dark ]; then bar=2c2c2e; text=ffffffd9; idle=4a4a4d; else bar=ececec; text=000000d9; idle=d4d4d4; fi
  add "hl.plugin.load($(q "$BARS"))"
  add "if hl.plugin.hyprbars then"
  add "    hl.config({ plugin = { hyprbars = {"
  add "        enabled = true, bar_height = 28, bar_padding = 13, bar_button_padding = 8,"
  add "        bar_buttons_alignment = \"left\", bar_text_font = \"Inter Variable\", bar_text_size = 10,"
  add "        bar_text_weight = \"semibold\", bar_text_align = \"center\", bar_part_of_window = true,"
  add "        bar_precedence_over_border = true, icon_on_hover = true,"
  add "        on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })']],"
  add "        bar_color = \"rgb($bar)\", col = { text = \"rgba($text)\" }, inactive_button_color = \"rgb($idle)\","
  add "    } } })"
  # Close, minimise (as ⌘M), zoom: 13 px, 8 px apart, glyphs on hover (apps/lib/TrafficLights.qml).
  add "    hl.plugin.hyprbars.add_button({ bg_color = \"rgb(ff5f57)\", fg_color = \"rgb(8c1a10)\", size = 13, icon = \"×\","
  add "        action = [[hyprctl dispatch 'hl.dsp.window.close()']] })"
  add "    hl.plugin.hyprbars.add_button({ bg_color = \"rgb(febc2e)\", fg_color = \"rgb(8f591d)\", size = 13, icon = \"−\","
  add "        action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = \"special:minimized\", follow = false })']] })"
  add "    hl.plugin.hyprbars.add_button({ bg_color = \"rgb(28c840)\", fg_color = \"rgb(0a6517)\", size = 13, icon = \"+\","
  add "        action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })']] })"
  add "end"
fi

# glassSolidity (Settings › Appearance › Transparency, 0 clear … 1 solid)
# moves the glass (sidebars, the Dock, menus, panels) continuously from the
# style's look to fully solid. Window contents are never see-through: a
# document's text and pictures read the same over any wallpaper.
read -r GLASS REDUCE SOLID <<EOF
$(python3 - "$CONFIG" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    d = {}
glass = d.get("glass", "clear")
try:
    s = min(1.0, max(0.0, float(d.get("glassSolidity", 0))))
except (TypeError, ValueError):
    s = 0.0
reduce = d.get("reduceTransparency", False) or s >= 0.999
print(glass if glass in ("clear", "tinted") else "clear", "1" if reduce else "0", f"{s:.2f}")
PY
)
EOF

# ------------------------------------------------------------- windows
# The specular rim (a 1 px border lit from the top left). Windows are solid
# (their sidebars and toolbars are the glass, drawn see-through by the app
# over the compositor's blur); Reduce Transparency makes every window solid,
# terminals included.
if [ "$THEME" = dark ]; then
  rim='"rgba(ffffff66)", "rgba(ffffff11)"'; rim_idle='"rgba(ffffff22)", "rgba(00000011)"'
else
  # Over light glass a white rim alone disappears: its far side darkens.
  rim='"rgba(ffffffb3)", "rgba(0000001f)"'; rim_idle='"rgba(ffffff59)", "rgba(00000014)"'
fi
add "hl.config({"
add "    general = { col = { active_border = { colors = { $rim }, angle = 45 }, inactive_border = { colors = { $rim_idle }, angle = 45 } } },"
add "    decoration = { active_opacity = 1.0, inactive_opacity = 1.0 },"
add "})"
if [ "$REDUCE" = 1 ]; then
  # The per-app opacity rules in hyprland.lua set theirs outright: this one,
  # loaded after them, makes every window solid over them.
  add "hl.window_rule({ name = \"gg-reduce-transparency\", match = { class = \".*\" }, opaque = true })"
fi

# ------------------------------------------------------------- HyprGlass
# Hyprland's own blur, for when the plugin can't be used: windows and panels
# stay frosted and readable instead of turning plain see-through.
fallback() {
  logger -t gg-hyprglass "$1; using Hyprland's blur"
  add "-- HyprGlass is not used: $1."
  add "hl.config({ decoration = { blur = { enabled = true, size = 10, passes = 3 } } })"
}
VIRT="$(systemd-detect-virt --vm 2>/dev/null || true)"
# Only into the Hyprland it was built for (its stamp, from the release pin).
BUILT_FOR="$(cat "$PLUGIN.hyprland" 2>/dev/null || true)"
RUNNING="$(pacman -Q hyprland 2>/dev/null | awk '{print $2}' | cut -d- -f1)"
if [ ! -r "$PLUGIN" ]; then
  fallback "no plugin at $PLUGIN"
elif [ -e "$PLUGIN.incompatible" ]; then
  fallback "plugin marked incompatible: $(cat "$PLUGIN.incompatible")"
elif [ -z "$BUILT_FOR" ] || { [ -n "$RUNNING" ] && [ "$BUILT_FOR" != "$RUNNING" ]; }; then
  fallback "plugin built for Hyprland ${BUILT_FOR:-unknown}, running ${RUNNING:-unknown}"
else
  # The Liquid Glass physics (docs/LIQUID-GLASS.md). Real GPUs render
  # HyprGlass' specular/brightness path much more strongly than llvmpipe /
  # virtual GPUs, so physical hardware gets a restrained optical profile and
  # light glass stays translucent instead of collapsing toward opaque white.
  if [ -n "$VIRT" ] && [ "$VIRT" != none ]; then
    physics="blur_strength = 1.5, blur_iterations = 3, refraction_strength = 0.6, chromatic_aberration = 0.14,
        fresnel_strength = 0.36, specular_strength = 0.42, edge_thickness = 0.08, lens_distortion = 0.45,
        dark = { brightness = 0.82, contrast = 0.94, saturation = 0.88, vibrancy = 0.16, adaptive_dim = 0.32, vibrancy_darkness = 0.15 },
        light = { brightness = 1.08, contrast = 0.95, saturation = 0.90, vibrancy = 0.12, adaptive_boost = 0.28, vibrancy_darkness = 0.15 },"
  else
    # Thick glass: what's behind bends at the edge, where a wide bevel pulls
    # in what lies just beyond it, and swells a little under the middle (the
    # dome lens); a lighter blur so the shapes stay readable through it, two
    # passes, and a trace of dispersion at the rim.
    physics="blur_strength = 0.95, blur_iterations = 2, refraction_strength = 0.55, chromatic_aberration = 0.08,
        fresnel_strength = 0.22, specular_strength = 0.16, edge_thickness = 0.08, lens_distortion = 0.42,
        dark = { brightness = 0.80, contrast = 0.98, saturation = 0.92, vibrancy = 0.08, adaptive_dim = 0.24, vibrancy_darkness = 0.15 },
        light = { brightness = 0.88, contrast = 1.01, saturation = 0.94, vibrancy = 0.06, adaptive_boost = 0.03, vibrancy_darkness = 0.15 },"
  fi
  # The glass's own opacity, from the style's look toward solid (0.96) as the
  # Transparency slider moves.
  opacity() { awk -v g="$1" -v s="$SOLID" 'BEGIN { printf "%.2f", g + (0.96 - g) * s }'; }
  virtual=0; [ -n "$VIRT" ] && [ "$VIRT" != none ] && virtual=1
  if [ "$REDUCE" = 1 ]; then
    look="glass_opacity = 0.96, refraction_strength = 0.04, chromatic_aberration = 0.0,"
  elif [ "$GLASS" = tinted ]; then
    if [ $virtual = 1 ]; then o=$(opacity 0.90); [ "$THEME" = dark ] && t=0x283c6e70 || t=0xf5f7ff72
    else o=$(opacity 0.76); [ "$THEME" = dark ] && t=0x283c6e42 || t=0xf5f7ff38; fi
    look="glass_opacity = $o, tint_color = $t,"
  else
    if [ $virtual = 1 ]; then o=$(opacity 0.80); [ "$THEME" = dark ] && t=0x283c6e38 || t=0xffffff42
    else o=$(opacity 0.58); [ "$THEME" = dark ] && t=0x283c6e24 || t=0x7f879018; fi
    look="glass_opacity = $o, tint_color = $t,"
  fi
  add "hl.plugin.load($(q "$PLUGIN"))"
  add "if hl.plugin.hyprglass then"
  add "    local hg = hl.plugin.hyprglass"
  # HyprGlass owns backdrop blur/refraction. QML only paints the material/tint and
  # control chrome, so there is one compositor optical pipeline rather than two.
  add "    hl.config({ decoration = { blur = { enabled = false } } })"
  add "    hg.config({"
  add "        enabled = true, manage_window_blur = true, default_theme = \"$THEME\", default_preset = \"default\","
  add "        $physics"
  add "        $look"
  # Layer glass where the surface asks for blur, else where it draws.
  add "        layers = { enabled = true, mask_mode = \"auto\", live_resample = true, live_resample_fps = 60, manage_blur = true },"
  add "    })"
  # The shell surfaces CitronOS draws, and for each the opacity above which
  # its pixels become glass: above its shadow, below its tint. MacShell's bar,
  # Dock and menus draw their own Liquid Glass (shell/macshell/liquidglass.frag),
  # so HyprGlass leaves them alone.
  for ns in gg-nearby=0.25 gg-tablet-home=0.25 gg-alert=0.3 gg-citron=0.5; do
    add "    hg.layer(\"${ns%%=*}\", { mask_threshold = ${ns#*=} })"
  done
  add "end"
  logger -t gg-hyprglass "HyprGlass set ($THEME, $GLASS, reduceTransparency=$REDUCE, virt=${VIRT:-none})"
fi

mkdir -p "$(dirname "$OUT")"
if [ -e "$OUT" ] && [ "$(cat "$OUT")" = "${LUA%
}" ]; then
  exit 0   # unchanged: no reload
fi
new=1; [ -e "$OUT" ] && new=0
tmp="$(mktemp "$OUT.XXXXXX")" || exit 0
printf '%s' "$LUA" > "$tmp" && mv -f "$tmp" "$OUT"
# Hyprland reloads a config file it loaded when it changes; a file that
# wasn't there when it last loaded isn't watched yet, so ask.
if [ $new = 1 ] && command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprctl reload >/dev/null 2>&1
fi
exit 0
