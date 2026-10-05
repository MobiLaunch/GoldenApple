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

# ------------------------------------------------------------- HyprGlass
[ -r "$PLUGIN" ] || exit 0

if ! hyprctl plugin list 2>/dev/null | grep -qi 'hyprglass'; then
  if ! hyprctl plugin load "$PLUGIN" >/dev/null 2>&1; then
    logger -t gg-hyprglass "could not load $PLUGIN"
    exit 0
  fi
fi

read -r GLASS REDUCE <<EOF
$(python3 - "$CONFIG" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    d = {}
print(d.get("glass", "clear"), "1" if d.get("reduceTransparency", False) else "0")
PY
)
EOF

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
  kw plugin:hyprglass:blur_strength 1.85
  kw plugin:hyprglass:blur_iterations 3
  kw plugin:hyprglass:refraction_strength 0.38
  kw plugin:hyprglass:chromatic_aberration 0.14
  kw plugin:hyprglass:fresnel_strength 0.36
  kw plugin:hyprglass:specular_strength 0.42
  kw plugin:hyprglass:edge_thickness 0.045
  kw plugin:hyprglass:lens_distortion 0.28
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
  kw plugin:hyprglass:blur_strength 1.42
  kw plugin:hyprglass:blur_iterations 3
  kw plugin:hyprglass:refraction_strength 0.24
  kw plugin:hyprglass:chromatic_aberration 0.055
  kw plugin:hyprglass:fresnel_strength 0.22
  kw plugin:hyprglass:specular_strength 0.16
  kw plugin:hyprglass:edge_thickness 0.032
  kw plugin:hyprglass:lens_distortion 0.18
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

if [ "$REDUCE" = 1 ]; then
  kw plugin:hyprglass:glass_opacity 0.96
  kw plugin:hyprglass:refraction_strength 0.16
  kw plugin:hyprglass:chromatic_aberration 0.04
elif [ "$GLASS" = tinted ]; then
  if [ -n "$VIRT" ] && [ "$VIRT" != none ]; then
    kw plugin:hyprglass:glass_opacity 0.90
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e70 || kw plugin:hyprglass:tint_color 0xf5f7ff72
  else
    kw plugin:hyprglass:glass_opacity 0.76
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e42 || kw plugin:hyprglass:tint_color 0xf5f7ff38
  fi
else
  if [ -n "$VIRT" ] && [ "$VIRT" != none ]; then
    kw plugin:hyprglass:glass_opacity 0.80
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e38 || kw plugin:hyprglass:tint_color 0xffffff42
  else
    kw plugin:hyprglass:glass_opacity 0.48
    [ "$THEME" = dark ] && kw plugin:hyprglass:tint_color 0x283c6e24 || kw plugin:hyprglass:tint_color 0x7f879018
  fi
fi

# Only the shell surfaces that are intentionally made of glass are included.
# The menu bar and wallpaper stay optically clean.
kw plugin:hyprglass:layers:enabled 1
kw plugin:hyprglass:layers:namespaces "gg-dock,gg-controlcenter,gg-spotlight,gg-applications,gg-notifications,gg-nearby,gg-widgets,gg-widget-gallery"
kw plugin:hyprglass:layers:namespace_mask_thresholds "gg-dock=0.08,gg-controlcenter=0.08,gg-spotlight=0.08,gg-applications=0.06,gg-notifications=0.08,gg-nearby=0.08,gg-widgets=0.2,gg-widget-gallery=0.2"
kw plugin:hyprglass:layers:live_resample 1
kw plugin:hyprglass:layers:live_resample_fps 30
kw plugin:hyprglass:layers:manage_blur 1

logger -t gg-hyprglass "HyprGlass applied ($THEME, $GLASS, reduceTransparency=$REDUCE, virt=${VIRT:-none})"
