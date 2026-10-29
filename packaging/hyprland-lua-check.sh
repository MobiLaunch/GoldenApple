#!/usr/bin/env bash
# CitronOS's Hyprland settings on Hyprland 0.57 and later, which read only
# Lua (T-2.3): Arch's current Hyprland (not the archive CitronOS is pinned to)
# checks the configuration it would start with, with Hyprland --verify-config.
# Run as root in an archlinux container, from the repository:
#
#   docker run --rm -v "$PWD:/repo" -w /repo archlinux:latest packaging/hyprland-lua-check.sh
#
# citronos-hyprland-config is staged into the system, and an account set up as
# CitronOS's are: the one-line hyprland.conf, and what gg-session, Settings
# (set-prefs.py's writers) and machine-conf.sh make in ~/.config/hypr/golden-gate.
# Then hyprland.lua (in /usr/share/golden-gate/hypr until the hold lifts, so
# given with -c) reads it all through hyprlang.lua, strictly:
# a line without a Lua form, or a setting Hyprland refuses, fails the check.
# Three machines: a desktop with a GPU, a virtual machine without one, and an
# account with its own lines in hyprland.conf.
set -euo pipefail
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }
fail() { echo "::error::$*"; FAILED=$((FAILED + 1)); }
FAILED=0

for try in 1 2 3; do
  pacman -Syu --noconfirm --needed hyprland python >/dev/null && break
  [[ $try == 3 ]] && exit 1
  sleep $((try * 20))
done
say "$(pacman -Q hyprland)"

stage=$(mktemp -d)
bash /repo/scripts/stage.sh hyprland-config "$stage" >/dev/null
# Its files only: not the staging folder's own mode onto /.
tar -C "$stage" -cf - . | tar -C / -xf - --no-overwrite-dir
[[ -f /usr/share/golden-gate/hypr/hyprland.lua && -f /usr/share/golden-gate/hypr/hyprlang.lua ]] || { fail "hyprland.lua isn't staged"; exit 1; }

# What Settings writes by default (apps/settings/set-prefs.py), as an account has it.
fragments=$(mktemp -d)
python3 - "$fragments" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("set_prefs", "/repo/apps/settings/set-prefs.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
out = Path(sys.argv[1])
(out / "input.conf").write_text(m.input_conf({}))
(out / "windows.conf").write_text(m.windows_conf({}))
(out / "accessibility.conf").write_text(m.accessibility_conf({"reduceMotion": True}))
PY

account() { # account NAME VIRT
  local name=$1 virt=$2 home=/home/$1
  useradd -m "$name"
  local conf=$home/.config/hypr/golden-gate
  mkdir -p "$conf"
  cp "$fragments"/*.conf "$conf/"
  # Settings › Displays (DisplaysPane.qml writes "monitor = " lines).
  echo "monitor = Virtual-1, 1920x1080@60, 0x0, 1.25" > "$conf/displays.conf"
  # machine-conf.sh, as gg-session runs it, here with this machine's virtualisation.
  install -d /tmp/virt-$virt
  printf '#!/bin/sh\necho %s\n[ %s != none ]\n' "$virt" "$virt" > /tmp/virt-$virt/systemd-detect-virt
  chmod 755 /tmp/virt-$virt/systemd-detect-virt
  PATH=/tmp/virt-$virt:$PATH sh /usr/share/golden-gate/hypr/machine-conf.sh "$conf/machine.conf"
  chown -R "$name:" "$home"
}
run_check() { # run_check NAME → Hyprland's verdict, and the reader's count
  su "$1" -c 'cd ~ && XDG_RUNTIME_DIR=$(mktemp -d) GG_HYPRLANG_STRICT=1 Hyprland --verify-config -c /usr/share/golden-gate/hypr/hyprland.lua' 2>&1
}
binds_in() { # the bind lines hyprland.conf has, with what it sources from the package
  cat "$@" | sed 's/#.*//' | grep -cE '^\s*bind[a-z]*\s*='
}
verify() { # verify NAME WHAT BINDS
  local out read
  if out=$(run_check "$1"); then
    say "$2: config ok"
  else
    fail "$2: Hyprland refuses the configuration"
  fi
  echo "$out" | grep -vE "^\[LOG\]|^$|Socket 2" | grep -vi "debug" | tail -n 30 | sed "s/^/  /"
  # The reader made every bind (a reader that did nothing would pass too).
  read=$(echo "$out" | sed -n 's/^citronos hyprlang: [0-9]* lines, \([0-9]*\) binds.*/\1/p')
  [[ $read == "$3" ]] || fail "$2: the reader made ${read:-no} binds of $3"
}
refused() { # refused NAME WHAT: a line Hyprland or the reader can't take fails the check
  if run_check "$1" >/dev/null; then fail "$2 passed: the check doesn't catch it"; else say "$2: refused, as it should be"; fi
}

system=$(binds_in /usr/share/golden-gate/hypr/hyprland.conf)
account desktop none
verify desktop "a desktop" "$system"

account vm kvm
grep -q "^monitor = , preferred, auto, 1" /home/vm/.config/hypr/golden-gate/machine.conf || fail "machine-conf.sh didn't write the VM's monitor line"
verify vm "a virtual machine without a GPU" "$system"

account mine none
cat >> /home/mine/.config/hypr/hyprland.conf <<'EOF'
# My own lines, as an account might have them.
$term = ghostty
bind = SUPER, T, exec, $term
general:gaps_out = 24
decoration {
    rounding = 18
}
windowrule = match:class ^(org\.gnome\.Calculator)$, float on
EOF
chown mine: /home/mine/.config/hypr/hyprland.conf
verify mine "an account with its own lines" "$((system + 1))"

# Every dispatch CitronOS sends while the desktop is up (the shell, gg-tile,
# Settings, gg-idle, the title bars), bound to keys: 0.57 refuses a dispatcher
# it can't make when the bind is made, so this checks each Lua form the
# reader gives (citronos.dsp, which Hypr.qml and gg-hyprctl use).
account dispatches none
n=0
while IFS= read -r line; do
  [[ -z $line ]] && continue
  n=$((n + 1))
  name=${line%% *}; arg=""; [[ $line == *" "* ]] && arg=${line#* }
  echo "bind = SUPER CTRL ALT SHIFT, F$n, $name, $arg" >> /home/dispatches/.config/hypr/hyprland.conf
done <<'EOF'
exec gg-settings about
exit
workspace 3
workspace emptym
movetoworkspace 2,address:0x5f1a2b3c
movetoworkspacesilent special:hidden,address:0x5f1a2b3c
movetoworkspacesilent special:hidden,class:^(org\.goldengate\.Files)$
movetoworkspacesilent special:minimized
focuswindow address:0x5f1a2b3c
focuswindow class:org.goldengate.Settings
focusmonitor HEADLESS-1
fullscreen 0
fullscreen 1
killactive
dpms off
dpms on
setfloating address:0x5f1a2b3c
resizewindowpixel exact 720 450,address:0x5f1a2b3c
movewindowpixel exact 0 30,address:0x5f1a2b3c
EOF
verify dispatches "every dispatch CitronOS sends" "$((system + n))"

account wrongdsp none
echo "bind = SUPER, Y, nosuchdispatcher, x" >> /home/wrongdsp/.config/hypr/hyprland.conf
refused wrongdsp "a dispatcher the reader doesn't know"
account wrongkey none
echo "general:no_such_option = 3" >> /home/wrongkey/.config/hypr/hyprland.conf
refused wrongkey "an option Hyprland doesn't have"

# ---------------------------------------------------------------- live
# With a GPU render node (the workflow loads vkms and vgem when it can: vkms
# alone gives display nodes only, and Hyprland needs a render node), a real headless
# Hyprland runs CitronOS's settings, and what the shell, Settings and scripts
# send it while the desktop is up must do what it did: gg-hyprctl's dispatch,
# keyword and --batch, and the shell's own form (Hypr.qml: citronos.dsp).
if compgen -G "/dev/dri/renderD*" >/dev/null; then
  say "live: a headless Hyprland with CitronOS's settings"
  chmod a+rw /dev/dri/* 2>/dev/null || true
  install -Dm755 /repo/compositor/hyprland/hyprctl.py /usr/lib/golden-gate/hyprctl.py
  printf '#!/bin/sh\nexec python3 /usr/lib/golden-gate/hyprctl.py "$@"\n' > /usr/bin/gg-hyprctl
  chmod 755 /usr/bin/gg-hyprctl
  pacman -S --noconfirm --needed mesa >/dev/null
  cat > /home/desktop/live.sh <<'EOF'
set -u
export XDG_RUNTIME_DIR=$(mktemp -d)
HYPRLAND_HEADLESS_ONLY=1 Hyprland -c /usr/share/golden-gate/hypr/hyprland.lua >"$HOME/hyprland.log" 2>&1 &
for _ in $(seq 100); do hyprctl version >/dev/null 2>&1 && break; sleep 0.2; done
if ! hyprctl version >/dev/null 2>&1; then
  echo "started=no"
  exit 0
fi
echo "started=yes"
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -n 1)
ws() { hyprctl activeworkspace -j | python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])'; }
opt() { hyprctl getoption "$1" -j | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d.get("str", d.get("int", d.get("custom"))))'; }
echo "mode=$(gg-hyprctl mode)"
gg-hyprctl dispatch workspace 3 >/dev/null; echo "dispatch=$(ws)"
hyprctl dispatch 'citronos.dsp([[workspace 4]])' >/dev/null; echo "shell=$(ws)"
gg-hyprctl keyword input:kb_layout de >/dev/null; echo "keyword=$(opt input:kb_layout)"
gg-hyprctl --batch 'keyword general:gaps_out 30 ; dispatch workspace 5' >/dev/null; echo "batch=$(ws),$(opt general:gaps_out)"
gg-hyprctl dispatch exec touch "$HOME/exec-ran" >/dev/null; sleep 1; [ -e "$HOME/exec-ran" ] && echo "exec=ran"
gg-hyprctl dispatch nosuchdispatcher x >/dev/null; echo "unknown=$?"
hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || true
EOF
  chown desktop: /home/desktop/live.sh
  live=$(su desktop -c 'bash ~/live.sh' 2>&1) || true
  echo "$live" | sed 's/^/  /'
  want() { echo "$live" | grep -qx "$1" && say "live: $2" || fail "live: $2 (wanted $1)"; }
  if echo "$live" | grep -qx "started=yes"; then
    want "mode=lua" "gg-hyprctl sees Lua mode"
    want "dispatch=3" "gg-hyprctl dispatch workspace 3"
    want "shell=4" "the shell's citronos.dsp form"
    want "keyword=de" "gg-hyprctl keyword input:kb_layout de"
    want "batch=5,30" "gg-hyprctl --batch keyword and dispatch"
    want "exec=ran" "gg-hyprctl dispatch exec"
    want "unknown=1" "an unknown dispatcher fails"
  else
    # Hyprland didn't come up on this GPU: say why.
    fail "live: Hyprland didn't start with CitronOS's settings on $(ls /dev/dri | tr '\n' ' ')"
  fi
  if [[ $FAILED -gt 0 ]]; then
    grep -vE "^\[LOG\]|DEBUG" /home/desktop/hyprland.log | tail -n 25 | sed 's/^/    /'
  fi
elif [[ ${GG_HYPRLAND_LIVE:-} == required ]]; then
  fail "live: no GPU render node (/dev/dri/renderD*), so no Hyprland to run"
else
  echo "::warning::live: skipped, no GPU render node here ($(ls /dev/dri 2>/dev/null | tr '\n' ' ')); Hyprland needs one"
fi

if (( FAILED )); then echo "$FAILED problem(s)"; exit 1; fi
say "Hyprland $(pacman -Q hyprland | cut -d' ' -f2) runs CitronOS's settings"
