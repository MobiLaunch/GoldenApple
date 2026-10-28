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
# 3. N cold starts (20 by default) of `qs -c golden-gate`; then the
#    performance baseline (tests/session/perf.py, T-0.3). A start fails if the shell died,
#    left a crash report (~/.cache/quickshell/crashes), printed "pure virtual"
#    (the theme-icon crash, CS2-004), or a QML error in CitronOS's own files.
# 4. Every surface opened through `qs ipc`, in light and in dark, screenshotted
#    into OUTDIR: the desktop, Control Center, Spotlight, Launchpad,
#    Notification Center, Mission Control; then the lock screen, locked with
#    gg-lock, and killed while locked 5 times (T-1.5: each time a new one
#    should be holding the lock within 3 s); then signed in on, typed with a
#    virtual keyboard (wtype): a wrong password first, then the account's.
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
  # A password for signing in on the lock screen, new each run (never printed).
  GG_TEST_PASSWORD="$(openssl rand -hex 12)"; export GG_TEST_PASSWORD
  echo "gg-session:$GG_TEST_PASSWORD" | chpasswd
  # The lock screen checks it through PAM's unix_chkpwd, which needs its setuid
  # bit to read /etc/shadow (an image or a copy can lose it).
  echo "unix_chkpwd: $(stat -c '%A %U' "$(command -v unix_chkpwd)" 2>&1)"
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
sway -V -c "$XDG_RUNTIME_DIR/sway.conf" >"$OUT/sway.log" 2>&1 &
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

# ---------------------------------------------------------------- 3b. performance
# T-0.3's baseline: time to the desktop, memory, idle CPU with glass windows on
# and off (OUTDIR/perf.json, perf.md and the job summary). PERF=0 skips it.
if [[ ${PERF:-1} == 1 ]]; then
  say "performance baseline (tests/session/perf.py)"
  python3 "$REPO/tests/session/perf.py" "$OUT" || fail "the performance baseline couldn't be measured"
  pkill -u "$(id -u)" -x qs 2>/dev/null || true; sleep 1
fi

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

# The lock screen in a process of its own, restarted 200 ms after it stops
# as citronos-lock.service is (Restart=always, RestartSec=200ms). `|| true`: under
# set -e the loop would end at the first crash.
( while :; do gg-lock serve >>"$OUT/lock.log" 2>&1 || true; sleep 0.2; done ) &
LOCK_LOOP=$!
LOCK_QML="$XDG_CONFIG_HOME/quickshell/golden-gate/lock-shell.qml"
# "true" once the compositor has confirmed a lock screen's lock, "false" while
# one runs unlocked, nothing while none answers.
lock_state() { timeout 2 qs -p "$LOCK_QML" ipc call lock isLocked 2>/dev/null | tr -d '[:space:]' || true; }
# The lock screen the loop runs. Quickshell relaunches a crashed instance in
# place, under the same pid, when it has run 10 s; the fork that writes its
# core dump has the same command line, but isn't the loop's child.
lock_pid() { pgrep -u "$(id -u)" -P "$LOCK_LOOP" -f "qs -p .*lock-shell.qml" | head -n1 || true; }
ms() { echo $(( $(date +%s%N) / 1000000 )); }
for _ in $(seq 50); do [[ $(lock_state) == false ]] && break; sleep 0.2; done
[[ $(lock_state) == false ]] || fail "the lock screen didn't start"
gg-lock
for _ in $(seq 25); do [[ $(lock_state) == true ]] && break; sleep 0.2; done
[[ $(lock_state) == true ]] || fail "gg-lock didn't lock the screen"
sleep 1
shot dark-lock; shots+=(dark-lock)
restored=0 times=()
touch "$OUT/.lock-kills-start"
for round in 1 2 3 4 5; do
  old=$(lock_pid)
  [[ -n $old ]] || { echo "  kill $round: no lock screen to kill"; break; }
  loaded_before=$(grep -c "Configuration Loaded" "$OUT/lock.log" 2>/dev/null || true)
  t0=$(ms)
  kill -SEGV "$old" 2>/dev/null || true
  sleep 0.2   # gone, or relaunching, before asking
  back=false spawned="" loaded=""
  while (( $(ms) - t0 < 3000 )); do
    # Where the time goes: the new process appearing, its configuration
    # loading, and the lock confirmed (asking takes a moment itself, so
    # it's known only to be back between asking and the answer).
    [[ -z $spawned && -n $(lock_pid) && $(lock_pid) != "$old" ]] && spawned=$(( $(ms) - t0 ))
    [[ -z $loaded && $(grep -c "Configuration Loaded" "$OUT/lock.log" 2>/dev/null || true) -gt ${loaded_before:-0} ]] && loaded=$(( $(ms) - t0 ))
    asked=$(( $(ms) - t0 ))
    [[ $(lock_state) == true ]] && { back=true; break; }
    sleep 0.1
  done
  took=$(( $(ms) - t0 ))
  if $back; then
    restored=$((restored + 1)); times+=("$took")
    echo "  kill $round (pid $old): locked again by ${asked}-${took} ms (process up after ${spawned:-?} ms, configuration loaded after ${loaded:-?} ms)"
  else
    echo "  kill $round (pid $old): no lock screen holding the lock within 3 s"
    ps -u "$(id -u)" -o pid=,ppid=,etimes=,stat=,args= | grep -E "qs|quickshell|gg-lock" | grep -v grep | sed "s/^/    /" || true
  fi
  # Give each new lock screen a moment, as a person would take to notice.
  for _ in $(seq 20); do [[ $(lock_state) == true ]] && break; sleep 0.25; done
  sleep 1
done
if [[ $restored != 5 ]]; then
  echo "::group::The lock screen's log (last 80 lines)"
  tail -n 80 "$OUT/lock.log" || true
  echo "--- crash reports"
  for f in "$HOME"/.cache/quickshell/crashes/*/report.txt; do
    [[ -e $f ]] || continue; echo "## $f"; sed -n '/Instance Information/,/Log Tail/p' "$f"
  done
  echo "--- Sway on locking"
  grep -iE "lock|abandon" "$OUT/sway.log" | tail -n 40 || true
  echo "::endgroup::"
fi
shot dark-lock-restored; shots+=(dark-lock-restored)
# gg-lock turns Quickshell's crash handler and core dumps off for the lock
# screen: a crashed one leaves no dump of its memory (a password being typed),
# and nothing holds its lock open after it while one is written.
# (The crash reports' folder is made by the first report: none, no folder.)
lock_dumps=$( { find "$CRASHES" -mindepth 1 -maxdepth 1 -newer "$OUT/.lock-kills-start" 2>/dev/null || true; } | wc -l)
say "the killed lock screens left no crash dump ($lock_dumps)"
[[ $lock_dumps == 0 ]] || fail "the killed lock screens left $lock_dumps crash dumps"

# Signing in, typed on the lock screen with a virtual keyboard: a wrong
# password keeps it locked; the account's own unlocks it and clears the marker.
signed_in=0
if [[ -n ${GG_TEST_PASSWORD:-} && $(lock_state) == true ]]; then
  # wtype sends its own keymap each time, and the first key after it is lost
  # (the field got 27 of 28 characters, and a Return sent alone never came):
  # each entry goes in one call, after a Shift that may be lost harmlessly.
  type() { wtype -d 15 -k Shift_L "$@" || fail "wtype couldn't type on the lock screen"; }
  type; sleep 1                               # wakes it: the field appears
  lock_status() { timeout 2 qs -p "$LOCK_QML" ipc call lock status 2>/dev/null || true; }
  type "not-$GG_TEST_PASSWORD" -k Return; sleep 5
  echo "  after Return: $(lock_status)"
  if [[ $(lock_state) != true || ! -e $XDG_RUNTIME_DIR/citronos-locked ]]; then
    fail "a wrong password unlocked the screen"
  elif [[ $(lock_status) != *'"failures":1'* ]]; then
    fail "the wrong password wasn't checked and refused (the lock screen: $(lock_status))"
  else
    say "a wrong password: checked, refused, still locked"
  fi
  type "$GG_TEST_PASSWORD" -k Return
  for _ in $(seq 40); do [[ $(lock_state) == false ]] && break; sleep 0.25; done
  sleep 1
  if [[ $(lock_state) == false && ! -e $XDG_RUNTIME_DIR/citronos-locked ]]; then
    signed_in=1; say "signed in on the lock screen: unlocked, and the marker is gone"
  else
    fail "signing in didn't unlock (lock screen: '$(lock_state)', marker $([[ -e $XDG_RUNTIME_DIR/citronos-locked ]] && echo still there || echo gone))"
    echo "::group::Why signing in didn't work"
    set +e
    # Does the account's password check out without the lock screen? (PAM's
    # helper, as the lock screen's PAM uses it; the password isn't printed.)
    # 7 is PAM_AUTH_ERR.
    echo "  the lock screen: $(lock_status)"
    # (unix_chkpwd reads NUL-terminated passwords, as PAM gives them.)
    printf '%s\0' "$GG_TEST_PASSWORD" | unix_chkpwd gg-session nullok; echo "unix_chkpwd: exit $?"
    ls -l "$(command -v unix_chkpwd)"; getcap "$(command -v unix_chkpwd)"
    id; grep -c '^gg-session:\$' /etc/shadow 2>/dev/null; sudo -n true 2>/dev/null; echo "shadow readable here: $([[ -r /etc/shadow ]] && echo yes || echo no)"
    faillock --user gg-session 2>&1 | tail -n 5
    grep -hv '^#' /etc/pam.d/login /etc/pam.d/system-login /etc/pam.d/system-auth 2>/dev/null | grep -v '^$' | sed 's/^/  pam: /'
    tail -n 20 "$OUT/lock.log"
    set -e
    echo "::endgroup::"
  fi
  sleep 2; shot dark-unlocked; shots+=(dark-unlocked)
else
  fail "no lock screen holding the lock to sign in on"
fi
say "lock screen killed while locked: back within 3 s, $restored of 5 (${times[*]:-} ms)"
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
python3 - "$OUT/summary.json" "$STARTS" "$crashed" "$restored" "$signed_in" "${listening:-}" "${shots[@]}" <<'PY'
import json, sys
out, starts, crashed, restored, signed_in, listening, *shots = sys.argv[1:]
json.dump({"coldStarts": int(starts), "crashed": int(crashed), "lockRestored": int(restored), "lockKills": 5, "signedIn": bool(int(signed_in)),
           "airdropListening": bool(listening), "shots": shots}, open(out, "w"), indent=2)
PY
python3 "$REPO/tests/session/shots.py" "$OUT" || FAILED=$((FAILED + 1))
say "cold starts: $((STARTS - crashed))/$STARTS clean; failures: $FAILED"
exit $((FAILED > 0))
