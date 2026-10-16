#!/usr/bin/env bash
# CitronOS → HyprGlass bridge.
# Loads the version-matched plugins if available (HyprGlass, and hyprbars for
# title bars) and applies the current appearance/accessibility preferences.
# Safe to run repeatedly; runs at login, on every config reload and when the
# appearance changes.
set -u

PLUGIN="${GG_HYPRGLASS_PLUGIN:-/usr/lib/golden-gate/hyprglass.so}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate/desktop.json"
THEME="${1:-}"

command -v hyprctl >/dev/null 2>&1 || exit 0

if [ -z "$THEME" ]; then
  scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
  case "$scheme" in *dark*) THEME=dark ;; *) THEME=light ;; esac
fi

kw() { hyprctl keyword "$1" "$2" >/dev/null 2>&1 || true; }

# ------------------------------------------------------------- title bars
# Apps that leave their title bar to the compositor (Qt and Electron apps from
# the App Store, X11 apps) get a macOS one: traffic lights on the left, the
# title centred. GTK apps and CitronOS's own draw theirs (hyprbars is built
# to leave them alone, see distro/hyprbars/patch.py). Loading it reloads the
# config, which runs this script again (exec in hyprland.conf), so everything
# set here survives reloads; the plugin keeps one of each button.
BARS="${GG_HYPRBARS_PLUGIN:-/usr/lib/golden-gate/hyprbars.so}"
if [ -r "$BARS" ]; then
  if hyprctl plugin list 2>/dev/null | grep -qi 'hyprbars' || hyprctl plugin load "$BARS" >/dev/null 2>&1; then
    kw plugin:hyprbars:enabled 1
    kw plugin:hyprbars:bar_height 28
    kw plugin:hyprbars:bar_padding 13
    kw plugin:hyprbars:bar_button_padding 8
    kw plugin:hyprbars:bar_buttons_alignment left
    kw plugin:hyprbars:bar_text_font "Inter Variable"
    kw plugin:hyprbars:bar_text_size 10
    kw plugin:hyprbars:bar_text_weight semibold
    kw plugin:hyprbars:bar_text_align center
    kw plugin:hyprbars:bar_part_of_window 1
    kw plugin:hyprbars:bar_precedence_over_border 1
    kw plugin:hyprbars:icon_on_hover 1
    kw plugin:hyprbars:on_double_click "hyprctl dispatch fullscreen 1"
    if [ "$THEME" = dark ]; then
      kw plugin:hyprbars:bar_color "rgb(2c2c2e)"
      kw plugin:hyprbars:col.text "rgba(ffffffd9)"
      kw plugin:hyprbars:inactive_button_color "rgb(4a4a4d)"
    else
      kw plugin:hyprbars:bar_color "rgb(ececec)"
      kw plugin:hyprbars:col.text "rgba(000000d9)"
      kw plugin:hyprbars:inactive_button_color "rgb(d4d4d4)"
    fi
    # Close, minimise (as ⌘M), zoom: 13 px, 8 px apart, glyphs on hover (apps/lib/TrafficLights.qml).
    kw plugin:hyprbars:hyprbars-button "rgb(ff5f57), 13, ×, hyprctl dispatch killactive, rgb(8c1a10)"
    kw plugin:hyprbars:hyprbars-button "rgb(febc2e), 13, −, hyprctl dispatch movetoworkspacesilent special:minimized, rgb(8f591d)"
    kw plugin:hyprbars:hyprbars-button "rgb(28c840), 13, +, hyprctl dispatch fullscreen 1, rgb(0a6517)"
  else
    logger -t gg-hyprglass "could not load $BARS"
  fi
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
print(glass, "1" if reduce else "0", f"{s:.2f}")
PY
)
EOF

# ------------------------------------------------------------- windows
# The specular rim (a 1 px border lit from the top left). Windows are solid
# (their sidebars and toolbars are the glass, drawn see-through by the app
# over the compositor's blur); Reduce Transparency makes every window solid,
# terminals included.
if [ "$THEME" = dark ]; then
  kw general:col.active_border "rgba(ffffff66) rgba(ffffff11) 45deg"
  kw general:col.inactive_border "rgba(ffffff22) rgba(00000011) 45deg"
else
  # Over light glass a white rim alone disappears: its far side darkens.
  kw general:col.active_border "rgba(ffffffb3) rgba(0000001f) 45deg"
  kw general:col.inactive_border "rgba(ffffff59) rgba(00000014) 45deg"
fi
OPAQUE_FLAG="${XDG_RUNTIME_DIR:-/tmp}/gg-glass-opaque-$(id -u)"
if [ "$REDUCE" = 1 ]; then
  kw decoration:active_opacity 1.0
  kw decoration:inactive_opacity 1.0
  # The per-app opacity rules in hyprland.conf set theirs outright: this one
  # makes every window solid over them.
  kw windowrule "match:class .*, opaque on"
  touch "$OPAQUE_FLAG"
elif [ -e "$OPAQUE_FLAG" ]; then
  # Reduce Transparency was just turned off: a rule added at run time stays
  # until the config is loaded again. Reloading runs this script once more.
  rm -f "$OPAQUE_FLAG"
  hyprctl reload >/dev/null 2>&1 || true
  exit 0
else
  kw decoration:active_opacity 1.0
  kw decoration:inactive_opacity 1.0
fi

# ------------------------------------------------------------- HyprGlass
# Hyprland's own blur, for when the plugin can't be used: windows and panels
# stay frosted and readable instead of turning plain see-through.
fallback() {
  logger -t gg-hyprglass "$1; using Hyprland's blur"
  kw decoration:blur:enabled 1
  kw decoration:blur:size 10
  kw decoration:blur:passes 3
  exit 0
}
[ -r "$PLUGIN" ] || fallback "no plugin at $PLUGIN"
# Only into the Hyprland it was built for (its stamp, from the release pin).
BUILT_FOR="$(cat "$PLUGIN.hyprland" 2>/dev/null || true)"
RUNNING="$(pacman -Q hyprland 2>/dev/null | awk '{print $2}' | cut -d- -f1)"
[ -e "$PLUGIN.incompatible" ] && fallback "plugin marked incompatible: $(cat "$PLUGIN.incompatible")"
if [ -z "$BUILT_FOR" ] || { [ -n "$RUNNING" ] && [ "$BUILT_FOR" != "$RUNNING" ]; }; then
  fallback "plugin built for Hyprland ${BUILT_FOR:-unknown}, running ${RUNNING:-unknown}"
fi

if ! hyprctl plugin list 2>/dev/null | grep -qi 'hyprglass'; then
  if ! hyprctl plugin load "$PLUGIN" >/dev/null 2>&1; then
    fallback "could not load $PLUGIN"
  fi
fi
kw decoration:blur:enabled 0


# HyprGlass owns backdrop blur/refraction. QML only paints the material/tint and
# control chrome, so there is one compositor optical pipeline rather than two.
kw plugin:hyprglass:enabled 1
kw plugin:hyprglass:manage_window_blur 1
kw plugin:hyprglass:default_theme "$THEME"
kw plugin:hyprglass:default_preset default
# Real GPUs render HyprGlass' specular/brightness path much more strongly than
# llvmpipe/virtual GPUs. Preserve the existing VM profile, but use a restrained
# optical profile on physical hardware so light glass stays translucent instead
# of collapsing toward opaque white. The shell draws its own (faint) light catch
# and rim, so the compositor's specular and fresnel stay low in both profiles.
VIRT="$(systemd-detect-virt --vm 2>/dev/null || true)"
if [ -n "$VIRT" ] && [ "$VIRT" != none ]; then
  kw plugin:hyprglass:blur_strength 1.5
  kw plugin:hyprglass:blur_iterations 3
  kw plugin:hyprglass:refraction_strength 0.6
  kw plugin:hyprglass:chromatic_aberration 0.14
  kw plugin:hyprglass:fresnel_strength 0.36
  kw plugin:hyprglass:specular_strength 0.42
  kw plugin:hyprglass:edge_thickness 0.08
  kw plugin:hyprglass:lens_distortion 0.45
  kw plugin:hyprglass:dark:brightness 0.82
  kw plugin:hyprglass:dark:contrast 0.94
  kw plugin:hyprglass:dark:saturation 0.88
  kw plugin:hyprglass:dark:vibrancy 0.16
  kw plugin:hyprglass:dark:adaptive_dim 0.32
  kw plugin:hyprglass:light:brightness 1.08
  kw plugin:hyprglass:light:contrast 0.95
  kw plugin:hyprglass:light:saturation 0.90
  kw plugin:hyprglass:light:vibrancy 0.12
  kw plugin:hyprglass:light:adaptive_boost 0.28
else
  # The Liquid Glass physics (docs/LIQUID-GLASS.md): thick glass. What's behind
  # bends at the edge, where a wide bevel pulls in what lies just beyond it,
  # and swells a little under the middle (the dome lens), so it visibly morphs
  # as the glass moves over it; a lighter blur so the shapes stay readable
  # through it, and a trace of dispersion at the rim.
  kw plugin:hyprglass:blur_strength 0.95
  # Two passes: the shell's glass draws its own bent backdrop over this, so
  # the compositor's blur mostly shows in app sidebars, where two is plenty.
  kw plugin:hyprglass:blur_iterations 2
  kw plugin:hyprglass:refraction_strength 0.55
  kw plugin:hyprglass:chromatic_aberration 0.08
  kw plugin:hyprglass:fresnel_strength 0.22
  kw plugin:hyprglass:specular_strength 0.16
  kw plugin:hyprglass:edge_thickness 0.08
  kw plugin:hyprglass:lens_distortion 0.42
  kw plugin:hyprglass:dark:brightness 0.80
  kw plugin:hyprglass:dark:contrast 0.98
  kw plugin:hyprglass:dark:saturation 0.92
  kw plugin:hyprglass:dark:vibrancy 0.08
  kw plugin:hyprglass:dark:adaptive_dim 0.24
  kw plugin:hyprglass:light:brightness 0.88
  kw plugin:hyprglass:light:contrast 1.01
  kw plugin:hyprglass:light:saturation 0.94
  kw plugin:hyprglass:light:vibrancy 0.06
  kw plugin:hyprglass:light:adaptive_boost 0.03
fi

# Vibrancy lifts colour through the glass but holds back in the darks.
kw plugin:hyprglass:dark:vibrancy_darkness 0.15
kw plugin:hyprglass:light:vibrancy_darkness 0.15
# No glass under a window nothing shows through (saves the GPU), and layer
# glass where the surface asks for blur, else where it draws.
kw plugin:hyprglass:skip_opaque_windows 1
kw plugin:hyprglass:layers:mask_mode auto

# The glass's own opacity, from the style's look toward solid (0.96) as the
# Transparency slider moves.
glass_opacity() { kw plugin:hyprglass:glass_opacity "$(awk -v g="$1" -v s="$SOLID" 'BEGIN { printf "%.2f", g + (0.96 - g) * s }')"; }
if [ "$REDUCE" = 1 ]; then
  kw plugin:hyprglass:glass_opacity 0.96
  kw plugin:hyprglass:refraction_strength 0.04
  kw plugin:hyprglass:chromatic_aberration 0.0
elif [ "$GLASS" = tinted ]; then
  if [ -n "$VIRT" ] && [ "$VIRT" != none ]; then
    glass_opacity 0.90
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e70 || kw plugin:hyprglass:tint_color 0xf5f7ff72
  else
    glass_opacity 0.76
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e42 || kw plugin:hyprglass:tint_color 0xf5f7ff38
  fi
else
  if [ -n "$VIRT" ] && [ "$VIRT" != none ]; then
    glass_opacity 0.80
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e38 || kw plugin:hyprglass:tint_color 0xffffff42
  else
    glass_opacity 0.58
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e24 || kw plugin:hyprglass:tint_color 0x7f879018
  fi
fi

# ------------------------------------------------------------- shell glass
# Every shell surface made of glass, and for each the opacity above which its
# pixels become glass: above its shadow (and, for the screenshot overlay, its
# 40% dim), below its tint. The menu bar is a faint film (8%), so all of it is.
kw plugin:hyprglass:layers:enabled 1
# Control Center already owns a live Quickshell DesktopBackdrop and rounded
# per-module refraction. Re-applying HyprGlass to its full rectangular layer
# silhouette caused the opaque, block-like shadow around the whole panel.
# Leave that layer to its individual glass controls instead.
kw plugin:hyprglass:layers:namespaces "gg-menubar,gg-dock,gg-spotlight,gg-notifications,gg-notification-center,gg-nearby,gg-widgets,gg-widget-gallery,gg-tablet-home,gg-osd,gg-alert,gg-switcher,gg-screenshot,gg-screenshot-thumbnail,gg-citron"
kw plugin:hyprglass:layers:namespace_mask_thresholds "gg-menubar=0.05,gg-dock=0.25,gg-spotlight=0.25,gg-notifications=0.25,gg-notification-center=0.3,gg-nearby=0.25,gg-widgets=0.25,gg-widget-gallery=0.25,gg-tablet-home=0.25,gg-osd=0.3,gg-alert=0.3,gg-switcher=0.3,gg-screenshot=0.5,gg-screenshot-thumbnail=0.3,gg-citron=0.5"
kw plugin:hyprglass:layers:live_resample 1
kw plugin:hyprglass:layers:live_resample_fps 60
kw plugin:hyprglass:layers:manage_blur 1

logger -t gg-hyprglass "HyprGlass applied ($THEME, $GLASS, reduceTransparency=$REDUCE, virt=${VIRT:-none})"
