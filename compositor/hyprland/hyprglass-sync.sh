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

# ------------------------------------------------------------- windows
# The specular rim (a 1 px border lit from the top left) and how see-through
# windows are: the Liquid Glass look, a little more solid with the Tinted
# glass style, and fully solid with Reduce Transparency.
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
elif [ "$GLASS" = tinted ]; then
  kw decoration:active_opacity 0.95
  kw decoration:inactive_opacity 0.90
else
  kw decoration:active_opacity 0.88
  kw decoration:inactive_opacity 0.78
fi

# ------------------------------------------------------------- HyprGlass
[ -r "$PLUGIN" ] || exit 0

if ! hyprctl plugin list 2>/dev/null | grep -qi 'hyprglass'; then
  if ! hyprctl plugin load "$PLUGIN" >/dev/null 2>&1; then
    logger -t gg-hyprglass "could not load $PLUGIN"
    exit 0
  fi
fi


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
  # The Liquid Glass physics (docs/LIQUID-GLASS.md): a soft blur, edge
  # refraction you notice only as the glass moves over something, and a
  # trace of dispersion at the rim.
  kw plugin:hyprglass:blur_strength 1.2
  kw plugin:hyprglass:blur_iterations 3
  kw plugin:hyprglass:refraction_strength 0.08
  kw plugin:hyprglass:chromatic_aberration 0.03
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

# Vibrancy lifts colour through the glass but holds back in the darks.
kw plugin:hyprglass:dark:vibrancy_darkness 0.15
kw plugin:hyprglass:light:vibrancy_darkness 0.15
# No glass under a window nothing shows through (saves the GPU), and layer
# glass where the surface asks for blur, else where it draws.
kw plugin:hyprglass:skip_opaque_windows 1
kw plugin:hyprglass:layers:mask_mode auto

if [ "$REDUCE" = 1 ]; then
  kw plugin:hyprglass:glass_opacity 0.96
  kw plugin:hyprglass:refraction_strength 0.04
  kw plugin:hyprglass:chromatic_aberration 0.0
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

# ------------------------------------------------------------- shell glass
# Every shell surface made of glass, and for each the opacity above which its
# pixels become glass: above its shadow (and, for the screenshot overlay, its
# 40% dim), below its tint. The menu bar is a faint film (8%), so all of it is.
kw plugin:hyprglass:layers:enabled 1
kw plugin:hyprglass:layers:namespaces "gg-menubar,gg-dock,gg-controlcenter,gg-spotlight,gg-applications,gg-notifications,gg-notification-center,gg-nearby,gg-widgets,gg-widget-gallery,gg-osd,gg-alert,gg-switcher,gg-screenshot,gg-screenshot-thumbnail,gg-citron"
kw plugin:hyprglass:layers:namespace_mask_thresholds "gg-menubar=0.05,gg-dock=0.08,gg-controlcenter=0.08,gg-spotlight=0.08,gg-applications=0.06,gg-notifications=0.08,gg-notification-center=0.3,gg-nearby=0.08,gg-widgets=0.2,gg-widget-gallery=0.2,gg-osd=0.3,gg-alert=0.3,gg-switcher=0.3,gg-screenshot=0.5,gg-screenshot-thumbnail=0.3,gg-citron=0.5"
kw plugin:hyprglass:layers:live_resample 1
kw plugin:hyprglass:layers:live_resample_fps 30
kw plugin:hyprglass:layers:manage_blur 1

logger -t gg-hyprglass "HyprGlass applied ($THEME, $GLASS, reduceTransparency=$REDUCE, virt=${VIRT:-none})"
