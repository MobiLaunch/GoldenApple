#!/usr/bin/env bash
# Screenshot GTK apps with the Golden Gate theme, light and dark, in a headless
# Sway session. No GPU needed.
#
#   design/gtk/tests/app-shots.sh OUTDIR [shot...]
#
# Shots (default: all that are installed):
#   gallery gallery-menu gallery-dialog gallery-finder   every control (tests/gallery.js)
#   files text-editor calculator settings clocks calendar weather maps
#   loupe music software fractal ghostty
# Writes OUTDIR/<shot>-light.png and -dark.png: the window plus 40 px around it,
# over the default wallpaper. SHOTS_B64=1 also prints each as a JPEG in base64
# ("--- shot <name> ---" … "--- end ---"), so they can be read from a CI log.
# Needs: sway, swaybg, grim, jq, gjs, rsvg-convert, dbus-run-session.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
OUT="$(mkdir -p "${1:?usage: app-shots.sh OUTDIR [shot...]}" && cd "$1" && pwd)"; shift
# Files refuses to run as root (CI containers run as root): use a plain user.
if [[ $EUID == 0 ]]; then
  # Settings won't start without a system bus (containers have none).
  if ! dbus-send --system --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.GetId >/dev/null 2>&1; then
    rm -f /run/dbus/pid /run/dbus/system_bus_socket; mkdir -p /run/dbus
    dbus-daemon --system --fork 2>/dev/null || true
  fi
  id gg-shots >/dev/null 2>&1 || useradd -m gg-shots
  chown -R gg-shots "$OUT"
  exec runuser -u gg-shots -- env ${SHOTS_B64:+SHOTS_B64=$SHOTS_B64} ${SETTLE:+SETTLE=$SETTLE} "$0" "$OUT" "$@"
fi
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || exec dbus-run-session -- "$0" "$OUT" "$@"
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- what each shot runs
declare -A CMD=(
  [gallery]="gjs -m $HERE/gallery.js main"
  [gallery-menu]="gjs -m $HERE/gallery.js menu"
  [gallery-dialog]="gjs -m $HERE/gallery.js dialog"
  [gallery-finder]="gjs -m $HERE/gallery.js finder"
  [files]='nautilus --new-window --select $HOME/Documents'
  [text-editor]='gnome-text-editor --standalone $HOME/Documents/Notes.txt'   # expanded below
  [calculator]="gnome-calculator"
  [settings]="env XDG_CURRENT_DESKTOP=GNOME gnome-control-center background"
  [clocks]="gnome-clocks"
  [calendar]="gnome-calendar"
  [weather]="gnome-weather"
  [maps]="gnome-maps"
  [loupe]="loupe"
  [music]="gnome-music"
  [software]="gnome-software"
  [fractal]="fractal"
  [ghostty]="ghostty"
)
ORDER=(gallery gallery-menu gallery-dialog gallery-finder files text-editor calculator settings clocks calendar weather maps loupe music software fractal ghostty)
shots=("$@"); [[ ${#shots[@]} -gt 0 ]] || shots=("${ORDER[@]}")

# ---------------------------------------------------------------- a clean home with the theme
export HOME="$(mktemp -d)" XDG_RUNTIME_DIR="$(mktemp -d)"
chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
for c in "${!CMD[@]}"; do CMD[$c]="${CMD[$c]//\$HOME/$HOME}"; done
mkdir -p "$XDG_CONFIG_HOME/gtk-4.0" "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/fontconfig/conf.d" "$XDG_DATA_HOME/icons"
cp "$REPO/design/dist/gtk.css" "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"
[[ -f $REPO/design/dist/gtk3.css ]] && cp "$REPO/design/dist/gtk3.css" "$XDG_CONFIG_HOME/gtk-3.0/gtk.css"
cp "$REPO/themes/fontconfig/60-golden-gate.conf" "$XDG_CONFIG_HOME/fontconfig/conf.d/"
mkdir -p "$XDG_CONFIG_HOME/ghostty" && cp -r "$REPO"/themes/ghostty/* "$XDG_CONFIG_HOME/ghostty/"
[[ -d $REPO/icons/GoldenGate ]] && cp -a "$REPO/icons/GoldenGate" "$XDG_DATA_HOME/icons/"
for d in gtk-4.0 gtk-3.0; do
  printf '[Settings]\ngtk-icon-theme-name=GoldenGate\ngtk-font-name=%s\ngtk-decoration-layout=close,minimize,maximize:\n' \
    "${GG_FONT:-Inter Variable 10}" > "$XDG_CONFIG_HOME/$d/settings.ini"
done
# GTK 4 on Wayland takes these from GSettings (the session sets them the same way
# in hyprland.conf), not from settings.ini.
gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
gsettings set org.gnome.desktop.interface icon-theme GoldenGate
gsettings set org.gnome.desktop.interface font-name "${GG_FONT:-Inter Variable 10}"
gsettings set org.gnome.desktop.interface monospace-font-name "JetBrains Mono 10"
gsettings set org.gnome.desktop.interface accent-color blue 2>/dev/null || true
# A Secret Service (Fractal won't start without one), unlocked without a prompt.
if command -v gnome-keyring-daemon >/dev/null; then
  eval "$(printf '' | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)" || true
fi
# Something to look at in Files and Text Editor.
mkdir -p "$HOME"/{Desktop,Documents,Downloads,Music,Pictures,Videos}
for d in DESKTOP:Desktop DOCUMENTS:Documents DOWNLOAD:Downloads MUSIC:Music PICTURES:Pictures VIDEOS:Videos; do
  echo "XDG_${d%%:*}_DIR=\"\$HOME/${d#*:}\""
done > "$XDG_CONFIG_HOME/user-dirs.dirs"
printf 'Golden Gate\n\nA Linux desktop with Liquid Glass.\n' > "$HOME/Documents/Notes.txt"
for f in "Budget 2026.ods" "Trip itinerary.pdf" "Presentation.odp"; do : > "$HOME/Documents/$f"; done
rsvg-convert -w 1600 "$REPO/prototype/assets/wallpapers/tide.svg" -o "$HOME/Pictures/Tide.png"

# ---------------------------------------------------------------- Sway
cat > "$XDG_RUNTIME_DIR/sway.conf" <<EOF
output HEADLESS-1 resolution ${GG_RES:-1600x1000} scale ${GG_SCALE:-1} bg $HOME/Pictures/Tide.png fill
default_border none
default_floating_border none
for_window [app_id=".*"] floating enable, move position center
EOF
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export LIBGL_ALWAYS_SOFTWARE=1 GDK_BACKEND=wayland NO_AT_BRIDGE=1 GTK_A11Y=none
sway -c "$XDG_RUNTIME_DIR/sway.conf" >"$OUT/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY 2>/dev/null || true' EXIT
for _ in $(seq 300); do [[ -S $XDG_RUNTIME_DIR/wayland-1 ]] && ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock >/dev/null 2>&1 && break; sleep 0.1; done
if ! ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock >/dev/null 2>&1; then echo "Sway did not start:"; tail -30 "$OUT/sway.log"; exit 1; fi
export WAYLAND_DISPLAY=wayland-1 SWAYSOCK="$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock)"

window() { swaymsg -t get_tree | jq -r '[.. | objects | select(.pid? != null)] | last | if . == null then empty else "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)" end'; }

shoot() { # shoot NAME SCHEME
  local name=$1 scheme=$2 cmd=${CMD[$1]} bin geo=
  bin=${cmd##*env XDG_CURRENT_DESKTOP=GNOME }; bin=${bin%% *}
  command -v "$bin" >/dev/null || { say "$name: $bin not installed, skipped"; return; }
  env -u GTK_THEME ADW_DEBUG_COLOR_SCHEME=prefer-$scheme ADW_DEBUG_ACCENT_COLOR=blue $cmd >"$OUT/$name-$scheme.log" 2>&1 &
  local pid=$!
  for _ in $(seq 60); do geo=$(window); [[ -n $geo ]] && break; sleep 0.5; done
  if [[ -z $geo ]]; then say "$name ($scheme): no window"; tail -5 "$OUT/$name-$scheme.log"; kill $pid 2>/dev/null || true; return; fi
  sleep "${SETTLE:-3}"
  geo=$(window)   # apps resize after their first frame
  local x=${geo%%,*} rest=${geo#*,}; local y=${rest%% *} size=${rest#* }; local w=${size%x*} h=${size#*x}
  local res=${GG_RES:-1600x1000}; local W=${res%x*} H=${res#*x}
  local x0=$(( x > 40 ? x - 40 : 0 )) y0=$(( y > 40 ? y - 40 : 0 ))
  local x1=$(( x + w + 40 < W ? x + w + 40 : W )) y1=$(( y + h + 40 < H ? y + h + 40 : H ))
  grim -g "$x0,$y0 $((x1 - x0))x$((y1 - y0))" "$OUT/$name-$scheme.png"
  say "$name ($scheme): ${w}x${h}"
  swaymsg '[pid=".*"] kill' >/dev/null 2>&1 || true
  kill $pid 2>/dev/null || true; wait $pid 2>/dev/null || true
  pkill -f gnome-software 2>/dev/null || true   # it keeps a service running
  sleep 0.5
}

for s in "${shots[@]}"; do
  [[ -n ${CMD[$s]:-} ]] || { echo "unknown shot: $s"; exit 1; }
  for scheme in light dark; do shoot "$s" "$scheme"; done
done

if [[ ${SHOTS_B64:-0} == 1 ]]; then
  for f in "$OUT"/*.png; do
    echo "--- shot $(basename "$f" .png) ---"
    convert "$f" -quality 88 jpg:- | base64 -w0; echo; echo "--- end ---"
  done
fi
