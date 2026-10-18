#!/usr/bin/env bash
# The shell in a clean Arch account, without a GPU (CI: .github/workflows/shell.yml).
#
#   tests/shell-shots.sh OUTDIR
#
# 1. scripts/install.sh into a new account (as on an existing Arch system).
# 2. Hyprland --verify-config on the hyprland.lua it installed, with every
#    golden-gate/*.lua part CitronOS writes; any error fails.
# 3. The shell (qs -c golden-gate: MacShell's bar, Dock and widgets with
#    CitronOS's surfaces) and the lock screen (qs -c golden-gate-lock, as a
#    preview window) in a headless Sway session: a QML error in CitronOS's or
#    MacShell's files fails; each is screenshotted into OUTDIR (and printed as
#    a base64 JPEG between "--- shot <name> ---" and "--- end ---").
# Hyprland itself needs a GPU render node to run, so Sway hosts the layer
# surfaces here; Hyprland-only parts (window lists, the glass's window
# capture) show empty. The ISO's boot test (QEMU) runs the real session.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mkdir -p "${1:?usage: shell-shots.sh OUTDIR}" && cd "$1" && pwd)"
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }

if [[ $EUID == 0 ]]; then
  id gg-shell >/dev/null 2>&1 || useradd -m gg-shell
  chown -R gg-shell "$OUT"
  exec runuser -u gg-shell -- env ${SHOTS_B64:+SHOTS_B64=$SHOTS_B64} "$0" "$OUT"
fi
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || exec dbus-run-session -- "$0" "$OUT"

XDG_RUNTIME_DIR="$(mktemp -d)"; chmod 700 "$XDG_RUNTIME_DIR"; export XDG_RUNTIME_DIR
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export LANG=C.UTF-8 LC_ALL=C.UTF-8

# ---------------------------------------------------------------- 1. install
say "scripts/install.sh"
GG_SKIP_BUILD=1 bash "$REPO/scripts/install.sh" >"$OUT/install.log" 2>&1 || { tail -40 "$OUT/install.log"; exit 1; }
HYPR="$XDG_CONFIG_HOME/hypr"
test -f "$HYPR/hyprland.lua" && test -f "$HYPR/golden-gate/motion.lua"
test -f "$XDG_CONFIG_HOME/quickshell/golden-gate/shell.qml" && test -f "$XDG_CONFIG_HOME/quickshell/golden-gate-lock/shell.qml"

# ---------------------------------------------------------------- 2. Hyprland's own check
say "Hyprland $(Hyprland --version 2>/dev/null | head -n 1 | cut -c1-60)"
# Every part, as Setup Assistant, Settings and the session write them.
python3 "$REPO/apps/settings/set-prefs.py" input layout='"de"' tapToClick=false >/dev/null
python3 "$REPO/apps/settings/set-prefs.py" accessibility reduceMotion=true >/dev/null
python3 "$REPO/apps/settings/set-prefs.py" windows snapEnabled=false >/dev/null
LIBGL_ALWAYS_SOFTWARE=1 sh "$HYPR/golden-gate/machine-conf.sh" "$HYPR/golden-gate/machine.lua"
printf 'hl.monitor({ output = "HEADLESS-1", mode = "1600x1000@60", position = "0x0", scale = 1 }) -- display HEADLESS-1\n' > "$HYPR/golden-gate/displays.lua"
GG_GLASS_LUA="$HYPR/golden-gate/glass.lua" bash "$REPO/compositor/hyprland/hyprglass-sync.sh" dark
verify() {
  local log="$OUT/verify-$1.log" status=0
  Hyprland --verify-config -c "$HYPR/hyprland.lua" >"$log" 2>&1 || status=$?
  # It exits non-zero on any config error; its messages name the file and line.
  grep -vE '^\s*$' "$log" | tail -n 40
  if [[ $status != 0 ]] || grep -qE "unknown config key|error setting|config error|attempt to call|bad argument" "$log"; then
    echo "::error::Hyprland rejected hyprland.lua ($1, exit $status)"; return 1
  fi
  say "Hyprland accepts hyprland.lua ($1)"
}
verify all-parts
rm -f "$HYPR/golden-gate/"{glass,input,accessibility,windows,machine,displays}.lua
verify new-account

# ---------------------------------------------------------------- 3. the shell in Sway
cat > "$XDG_RUNTIME_DIR/sway.conf" <<EOF
output HEADLESS-1 resolution 1600x1000 scale 1 bg #1b3f9e solid_color
default_border none
EOF
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 LIBGL_ALWAYS_SOFTWARE=1
sway -c "$XDG_RUNTIME_DIR/sway.conf" >"$OUT/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY 2>/dev/null || true; pkill -u "$(id -u)" -x qs 2>/dev/null || true' EXIT
for _ in $(seq 300); do ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock >/dev/null 2>&1 && break; sleep 0.1; done
ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock >/dev/null 2>&1 || { echo "Sway did not start:"; tail -30 "$OUT/sway.log"; exit 1; }
SWAYSOCK="$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock)"; export WAYLAND_DISPLAY=wayland-1 SWAYSOCK
export QT_QPA_PLATFORM=wayland GG_WALLPAPER="$XDG_DATA_HOME/backgrounds/golden-gate/tide.png"
gsettings set org.gnome.desktop.interface color-scheme default 2>/dev/null || true

failed=0
shoot() { # shoot NAME LOG SECONDS COMMAND...
  local name=$1 log=$2 wait=$3; shift 3
  "$@" >"$OUT/$log" 2>&1 &
  local pid=$!
  sleep "$wait"
  grim "$OUT/$name.png" || true
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  # QML that didn't load or threw, in CitronOS's or MacShell's files.
  local errs
  errs=$(grep -E '(golden-gate|golden-gate-lock|shell|macshell)/[^ ]*\.qml.*(is not a type|is not defined|Cannot assign|Type error|TypeError|ReferenceError|failed to load|Unable to assign|Non-existent)|Failed to load configuration|QML .* Error|ERROR: ' "$OUT/$log" | grep -v 'Hyprland\|HYPRLAND_INSTANCE' | head -n 40 || true)
  if [[ -n $errs ]]; then
    echo "::error::$name: QML errors"; printf '%s\n' "$errs"; failed=1
  fi
  say "$name: $(grep -c . "$OUT/$log") log lines"
}
shoot shell shell.log 25 qs -c golden-gate
shoot lock lock.log 12 env MACLOCK_PREVIEW=1 qs -c golden-gate-lock

if [[ ${SHOTS_B64:-0} == 1 ]] && command -v magick >/dev/null; then
  for f in "$OUT"/*.png; do
    echo "--- shot $(basename "$f" .png) ---"; magick "$f" -resize 1200x -quality 82 jpg:- | base64 -w0; echo; echo "--- end ---"
  done
fi
exit $failed
