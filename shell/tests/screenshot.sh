#!/usr/bin/env bash
# Run the Golden Gate shell for real inside a headless Sway session and capture
# screenshots of the desktop, Control Center and Spotlight.
#
#   shell/tests/screenshot.sh [out-dir]
#
# Needs: sway, grim, quickshell (QS=/path/to/quickshell to override), dbus-run-session.
# Works without a GPU: Mesa's llvmpipe renders through the same OpenGL path as real
# hardware. Sway has no blur, so glass appears as tint + rim only.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(dirname "$HERE")"
OUT="${1:-$PWD/shell-screenshots}"
QS="${QS:-quickshell}"
mkdir -p "$OUT"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(mktemp -d)}"
chmod 700 "$XDG_RUNTIME_DIR"
WALL="${GG_WALLPAPER:-/usr/share/backgrounds/golden-gate/tide.png}"
export GG_WALLPAPER="$WALL"
cat > "$XDG_RUNTIME_DIR/sway.conf" <<EOF
# No bg: the shell draws the wallpaper (a swaybg would cover it).
output HEADLESS-1 resolution 1440x900
default_border none
EOF

WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c "$XDG_RUNTIME_DIR/sway.conf" >"$OUT/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY $QSPID 2>/dev/null || true' EXIT
for _ in $(seq 50); do [[ -S $XDG_RUNTIME_DIR/wayland-1 ]] && break; sleep 0.1; done
export WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland QS_NO_RELOAD_POPUP=1
export LIBGL_ALWAYS_SOFTWARE=1 QSG_RHI_BACKEND=opengl

dbus-run-session -- "$QS" -p "$SHELL_DIR" >"$OUT/quickshell.log" 2>&1 &
QSPID=$!
for _ in $(seq 100); do grep -q "Configuration Loaded" "$OUT/quickshell.log" 2>/dev/null && break; sleep 0.2; done
grep -q "Configuration Loaded" "$OUT/quickshell.log" || { echo "shell failed to load:"; cat "$OUT/quickshell.log"; exit 1; }
sleep 2

ipc() { "$QS" -p "$SHELL_DIR" ipc call "$@" >/dev/null; }
grim "$OUT/desktop.png"
ipc controlcenter toggle; sleep 1.5; grim "$OUT/control-center.png"; ipc controlcenter toggle; sleep 0.8
ipc spotlight toggle; sleep 1; grim "$OUT/spotlight.png"; ipc spotlight toggle

kill -0 $QSPID 2>/dev/null || { echo "shell crashed:"; tail -20 "$OUT/quickshell.log"; exit 1; }
if grep -E "ERROR|Binding loop|TypeError|ReferenceError" "$OUT/quickshell.log" | grep -vE "pipewire|DBus"; then
  echo "warnings above (see $OUT/quickshell.log)"
fi
echo "screenshots in $OUT"
