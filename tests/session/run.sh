#!/usr/bin/env bash
# The real shell in a clean account, under a headless compositor
# (CI: .github/workflows/session.yml; T-0.2).
#
#   tests/session/run.sh OUTDIR [--starts N] [--self-test]
#
# 1. scripts/install.sh into a new account, as on an existing Arch system.
# 2. Headless Sway (Hyprland needs a GPU render node, which CI hasn't got; the
#    ISO's boot test runs Hyprland itself in QEMU). Hyprland-only parts of the
#    shell (window lists, workspaces, the glass's window captures) show empty.
# 3. N cold starts (20 by default) of `qs -c golden-gate`. A start fails if the shell died,
#    left a crash report (~/.cache/quickshell/crashes), printed "pure virtual"
#    (the theme-icon crash, CS2-004), or a QML error in CitronOS's own files.
# 4. Every surface opened through `qs ipc`, in light and in dark, screenshotted
#    into OUTDIR: the desktop, Control Center, Spotlight, Launchpad,
#    Notification Center, Mission Control; then the lock screen, locked with
#    gg-lock, and killed while locked 5 times (T-1.5: each time a new one
#    should be locking within 3 s).
# 5. AirDrop's service with receiving off (a new account's default): nothing
#    listens on its port (T-1.8).
# 6. OUTDIR/summary.json, and tests/session/shots.py's contact sheet.
#
# --self-test proves the crash detection works: a shell killed with SIGSEGV,
# and a configuration that doesn't load, must both be caught. It exits 0 only
# if they were.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$(mkdir -p "${1:?usage: run.sh OUTDIR [--starts N] [--self-test]}" && cd "$1" && pwd)"
shift
STARTS=20 SELF_TEST=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --starts) STARTS=$2; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }
fail() { echo "::error::$*"; FAILED=$((FAILED + 1)); }

# A new, unprivileged account with its own session bus, as a login gives.
args=(--starts "$STARTS"); [[ $SELF_TEST == 1 ]] && args+=(--self-test)
if [[ $EUID == 0 ]]; then
  id gg-session >/dev/null 2>&1 || useradd -m gg-session
  chown -R gg-session "$OUT"
  # Its own copy of the tree, so nothing install.sh writes lands in the checkout.
  src=/home/gg-session/src
  rm -rf "$src"; cp -a "$REPO" "$src"; chown -R gg-session "$src"
  exec runuser -u gg-session -- "$src/tests/session/run.sh" "$OUT" "${args[@]}"
fi
# The account's directories come before its session bus: dconf-service, which
# the bus starts, tells GSettings readers about a change through
# $XDG_RUNTIME_DIR/dconf, so it has to be the readers' runtime directory (or
# every change reads back stale, and the shell never follows dark mode here).
if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  XDG_RUNTIME_DIR="$(mktemp -d)"; chmod 700 "$XDG_RUNTIME_DIR"; export XDG_RUNTIME_DIR
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
  exec dbus-run-session -- "$0" "$OUT" "${args[@]}"
fi
export LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$HOME/.local/bin:$PATH"
CRASHES="$XDG_CACHE_HOME/quickshell/crashes"
FAILED=0

# ---------------------------------------------------------------- 1. install
say "scripts/install.sh into a new account"
GG_SKIP_BUILD=1 bash "$REPO/scripts/install.sh" >"$OUT/install.log" 2>&1 || { tail -40 "$OUT/install.log"; exit 1; }
for f in "$XDG_CONFIG_HOME/quickshell/golden-gate/shell.qml" "$XDG_CONFIG_HOME/quickshell/golden-gate/lock-shell.qml" \
         "$HOME/.local/bin/gg-lock" "$HOME/.local/bin/gg-session-start"; do
  [[ -e $f ]] || { echo "::error::install.sh didn't install $f"; exit 1; }
done

# Hyprland's own check of the config install.sh wrote (no GPU needed for this).
if command -v Hyprland >/dev/null; then
  status=0
  Hyprland --verify-config -c "$XDG_CONFIG_HOME/hypr/hyprland.conf" >"$OUT/hyprland-verify.log" 2>&1 || status=$?
  if [[ $status != 0 ]] || grep -qiE "config error|unknown (keyword|config key)|invalid|error setting" "$OUT/hyprland-verify.log"; then
    fail "Hyprland rejects the installed hyprland.conf (exit $status)"
    grep -iE "error|invalid|unknown" "$OUT/hyprland-verify.log" | head -20
  else
    say "Hyprland accepts the installed hyprland.conf"
  fi
fi

# ---------------------------------------------------------------- 2. the compositor
cat > "$XDG_RUNTIME_DIR/sway.conf" <<EOF
output HEADLESS-1 resolution 1440x900 scale 1 bg #1b3f9e solid_color
default_border none
EOF
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 LIBGL_ALWAYS_SOFTWARE=1
sway -c "$XDG_RUNTIME_DIR/sway.conf" >"$OUT/sway.log" 2>&1 &
SWAY=$!
trap 'kill $SWAY 2>/dev/null || true; pkill -u "$(id -u)" -x qs 2>/dev/null || true; pkill -u "$(id -u)" -f "gg-lock serve" 2>/dev/null || true' EXIT
for _ in $(seq 300); do compgen -G "$XDG_RUNTIME_DIR/sway-ipc.*.sock" >/dev/null && break; sleep 0.1; done
compgen -G "$XDG_RUNTIME_DIR/sway-ipc.*.sock" >/dev/null || { echo "::error::Sway did not start"; tail -30 "$OUT/sway.log"; exit 1; }
SWAYSOCK="$(compgen -G "$XDG_RUNTIME_DIR/sway-ipc.*.sock" | head -n1)"
export SWAYSOCK WAYLAND_DISPLAY=wayland-1
# The environment the session gives the shell: hyprland.conf's env lines (the
# icon theme, the wallpaper, the Qt platform theme), as install.sh wrote them.
while IFS=$'\t' read -r key value; do export "$key=$value"; done < <(python3 - "$XDG_CONFIG_HOME/hypr/hyprland.conf" <<'PY'
import re, sys
for line in open(sys.argv[1]):
    m = re.match(r"\s*env\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([^#\n]*?)\s*(#.*)?$", line)
    if m:
        print(f"{m.group(1)}\t{m.group(2)}")
PY
)
say "session environment: QS_ICON_THEME=${QS_ICON_THEME:-} QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-} GG_WALLPAPER=${GG_WALLPAPER:-}"
gsettings set org.gnome.desktop.interface color-scheme default 2>/dev/null || true

# ---------------------------------------------------------------- checks
# check NAME PID LOG: did the process survive, cleanly?
check() {
  local name=$1 pid=$2 log=$3 bad=""
  kill -0 "$pid" 2>/dev/null || bad="the shell quit"
  compgen -G "$CRASHES/*" >/dev/null && bad="${bad:+$bad; }a crash report was written"
  grep -q "pure virtual" "$log" && bad="${bad:+$bad; }\"pure virtual\" in its log"
  local errs
  errs=$(grep -E 'golden-gate/[^ ]*\.qml.*(is not a type|is not defined|Cannot assign|TypeError|ReferenceError|failed to load|Unable to assign|Non-existent)|Failed to load configuration' "$log" | head -n 20 || true)
  [[ -n $errs ]] && bad="${bad:+$bad; }QML errors"
  if [[ -n $bad ]]; then
    echo "$name: $bad"
    [[ -n $errs ]] && printf '  %s\n' "$errs"
    tail -n 60 "$log" | sed 's/^/  | /'
    for d in "$CRASHES"/*/; do [[ -d $d ]] && cp -r "$d" "$OUT/crash-$name" 2>/dev/null; done
    rm -rf "$CRASHES"
    return 1
  fi
}
# wait_loaded LOG: until Quickshell says the configuration loaded (or failed).
wait_loaded() {
  for _ in $(seq 300); do
    grep -qE "Configuration Loaded|Failed to load configuration" "$1" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}
start_shell() { # start_shell LOG [CONFIG] → $SHELL_PID
  qs -c "${2:-golden-gate}" >"$1" 2>&1 &
  SHELL_PID=$!
  wait_loaded "$1" || true
}
stop() { kill "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }
ipc() { qs -c golden-gate ipc call "$@" >/dev/null 2>&1; }
shot() { grim "$OUT/$1.png" 2>/dev/null || echo "::warning::grim couldn't take $1"; }

# ---------------------------------------------------------------- self-test
if [[ $SELF_TEST == 1 ]]; then
  caught=0
  say "self-test: a shell killed with SIGSEGV"
  start_shell "$OUT/selftest-segv.log"; sleep 3
  kill -SEGV "$SHELL_PID" 2>/dev/null || true; sleep 4
  if check selftest-segv "$SHELL_PID" "$OUT/selftest-segv.log" >/dev/null; then echo "::error::a crashed shell wasn't caught"; else caught=$((caught + 1)); fi
  stop "$SHELL_PID"; pkill -u "$(id -u)" -x qs 2>/dev/null || true; rm -rf "$CRASHES"
  say "self-test: a configuration that doesn't load"
  mkdir -p "$XDG_CONFIG_HOME/quickshell/golden-gate-broken"
  printf 'import Quickshell\nShellRoot {\n  Item { this is not QML\n}\n' > "$XDG_CONFIG_HOME/quickshell/golden-gate-broken/shell.qml"
  start_shell "$OUT/selftest-broken.log" golden-gate-broken; sleep 2
  if grep -q "Failed to load configuration" "$OUT/selftest-broken.log"; then caught=$((caught + 1)); else
    echo "::error::a configuration that doesn't load wasn't caught"; tail -20 "$OUT/selftest-broken.log"; fi
  stop "$SHELL_PID"
  say "self-test: $caught of 2 caught"
  [[ $caught == 2 ]]; exit
fi

# ---------------------------------------------------------------- 3. cold starts
crashed=0
for i in $(seq "$STARTS"); do
  log="$OUT/start-$i.log"
  start_shell "$log"; sleep 6
  if check "start-$i" "$SHELL_PID" "$log"; then say "cold start $i/$STARTS: ok"; else crashed=$((crashed + 1)); fail "cold start $i/$STARTS crashed"; fi
  stop "$SHELL_PID"; pkill -u "$(id -u)" -x qs 2>/dev/null || true; sleep 1
done

# ---------------------------------------------------------------- 4. surfaces
SURFACES=(desktop:: controlcenter:controlcenter:toggle spotlight:spotlight:toggle launchpad:launchpad:toggle
          notifications:notifications:toggleCenter missioncontrol:missioncontrol:toggle)
shots=()
start_shell "$OUT/surfaces.log"; sleep 6
for theme in light dark; do
  gsettings set org.gnome.desktop.interface color-scheme "$([[ $theme == dark ]] && echo prefer-dark || echo default)" || true
  sleep 2
  # The shell answers a change of color-scheme by setting gtk-theme to match.
  say "$theme: color-scheme $(gsettings get org.gnome.desktop.interface color-scheme 2>&1), gtk-theme $(gsettings get org.gnome.desktop.interface gtk-theme 2>&1)"
  for s in "${SURFACES[@]}"; do
    IFS=: read -r name target fn <<<"$s"
    [[ -n $target ]] && ipc "$target" "$fn"
    sleep 1.6
    shot "$theme-$name"; shots+=("$theme-$name")
    [[ -n $target ]] && { ipc "$target" "$fn"; sleep 1; }
  done
done
check surfaces "$SHELL_PID" "$OUT/surfaces.log" || fail "the shell crashed while its surfaces were opened"
echo "::group::The shell's log while its surfaces were opened (last 60 lines)"
tail -n 60 "$OUT/surfaces.log"
echo "::endgroup::"

# The lock screen, in a process of its own, kept running as citronos-lock.service would.
( while :; do gg-lock serve >>"$OUT/lock.log" 2>&1; sleep 1; done ) &
LOCK_LOOP=$!
sleep 4
gg-lock; sleep 3
shot dark-lock; shots+=(dark-lock)
lock_pids() { pgrep -u "$(id -u)" -f "qs -p .*lock-shell.qml" || true; }
restored=0
[[ -n $(lock_pids) ]] || fail "the lock screen didn't start"
for round in 1 2 3 4 5; do
  old=$(lock_pids | head -n1)
  [[ -n $old ]] || break
  kill -SEGV "$old" 2>/dev/null || true
  back=false
  for _ in $(seq 30); do
    new=$(lock_pids | grep -vx "$old" | head -n1 || true)
    [[ -n $new && -e $XDG_RUNTIME_DIR/citronos-locked ]] && { back=true; break; }
    sleep 0.1
  done
  if $back; then restored=$((restored + 1)); else echo "kill $round: no lock screen within 3 s"; fi
  sleep 2
done
shot dark-lock-restored; shots+=(dark-lock-restored)
say "lock screen killed while locked: back within 3 s, $restored of 5"
[[ $restored == 5 ]] || fail "the lock screen came back within 3 s only $restored of 5 times"
kill "$LOCK_LOOP" 2>/dev/null || true
stop "$SHELL_PID"

# ---------------------------------------------------------------- 5. AirDrop off
gg-airdrop --serve >"$OUT/airdrop.log" 2>&1 &
AIRDROP=$!
sleep 4
listening=$(ss -Hlntup 2>/dev/null | grep -E ':53317\b' || true)
if ! kill -0 "$AIRDROP" 2>/dev/null; then fail "AirDrop's service didn't stay up"; tail -20 "$OUT/airdrop.log"
elif [[ -n $listening ]]; then fail "AirDrop listens on the network with receiving off: $listening"
else say "AirDrop's service is up, and nothing listens on 53317"; fi
stop "$AIRDROP"

# ---------------------------------------------------------------- 5. summary
python3 - "$OUT/summary.json" "$STARTS" "$crashed" "$restored" "${listening:-}" "${shots[@]}" <<'PY'
import json, sys
out, starts, crashed, restored, listening, *shots = sys.argv[1:]
json.dump({"coldStarts": int(starts), "crashed": int(crashed), "lockRestored": int(restored), "lockKills": 5,
           "airdropListening": bool(listening), "shots": shots}, open(out, "w"), indent=2)
PY
python3 "$REPO/tests/session/shots.py" "$OUT" || FAILED=$((FAILED + 1))
say "cold starts: $((STARTS - crashed))/$STARTS clean; failures: $FAILED"
exit $((FAILED > 0))
