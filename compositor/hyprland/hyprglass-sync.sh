#!/usr/bin/env bash
# Golden Gate → HyprGlass bridge.
# Loads the version-matched plugin if available and applies the current
# appearance/accessibility preferences. Safe to run repeatedly.
set -u

PLUGIN="${GG_HYPRGLASS_PLUGIN:-/usr/lib/golden-gate/hyprglass.so}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate/desktop.json"
THEME="${1:-}"

command -v hyprctl >/dev/null 2>&1 || exit 0
[ -r "$PLUGIN" ] || exit 0

if ! hyprctl plugin list 2>/dev/null | grep -qi 'hyprglass'; then
  if ! hyprctl plugin load "$PLUGIN" >/dev/null 2>&1; then
    logger -t gg-hyprglass "could not load $PLUGIN"
    exit 0
  fi
fi

if [ -z "$THEME" ]; then
  scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
  case "$scheme" in *dark*) THEME=dark ;; *) THEME=light ;; esac
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

kw() { hyprctl keyword "$1" "$2" >/dev/null 2>&1 || true; }

# HyprGlass owns backdrop blur/refraction. QML only paints the material/tint and
# control chrome, so there is one compositor optical pipeline rather than two.
kw plugin:hyprglass:enabled 1
kw plugin:hyprglass:manage_window_blur 1
kw plugin:hyprglass:default_theme "$THEME"
kw plugin:hyprglass:default_preset default
kw plugin:hyprglass:blur_strength 1.85
kw plugin:hyprglass:blur_iterations 3
kw plugin:hyprglass:refraction_strength 0.38
kw plugin:hyprglass:chromatic_aberration 0.14
kw plugin:hyprglass:fresnel_strength 0.46
kw plugin:hyprglass:specular_strength 0.58
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

if [ "$REDUCE" = 1 ]; then
  kw plugin:hyprglass:glass_opacity 0.96
  kw plugin:hyprglass:refraction_strength 0.16
  kw plugin:hyprglass:chromatic_aberration 0.04
elif [ "$GLASS" = tinted ]; then
  kw plugin:hyprglass:glass_opacity 0.90
  if [ "$THEME" = dark ]; then
    kw plugin:hyprglass:tint_color 0x283c6e70
  else
    kw plugin:hyprglass:tint_color 0xf5f7ff72
  fi
else
  kw plugin:hyprglass:glass_opacity 0.80
  if [ "$THEME" = dark ]; then
    kw plugin:hyprglass:tint_color 0x283c6e38
  else
    kw plugin:hyprglass:tint_color 0xffffff42
  fi
fi

# Only the shell surfaces that are intentionally made of glass are included.
# The menu bar and wallpaper stay optically clean.
kw plugin:hyprglass:layers:enabled 1
kw plugin:hyprglass:layers:namespaces "gg-dock,gg-controlcenter,gg-spotlight,gg-applications,gg-notifications"
kw plugin:hyprglass:layers:namespace_mask_thresholds "gg-dock=0.08,gg-controlcenter=0.08,gg-spotlight=0.08,gg-applications=0.06,gg-notifications=0.08"
kw plugin:hyprglass:layers:live_resample 1
kw plugin:hyprglass:layers:live_resample_fps 30
kw plugin:hyprglass:layers:manage_blur 1

logger -t gg-hyprglass "HyprGlass applied ($THEME, $GLASS, reduceTransparency=$REDUCE)"
