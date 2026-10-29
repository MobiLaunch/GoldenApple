#!/bin/bash
# The checks that need the real live session (systemd's user manager, the
# firewall, the lock screen as a service), run by citronos-selftest.service
# only when the kernel command line has gg.selftest: the boot test's std run
# (distro/archiso/boot-test.sh) adds it and reads the results from the serial
# log, where the journal is forwarded. Every line starts "gg-selftest:".
#
#   - the session's units are running;
#   - CitronOS is its packages, each file as packaged (pacman -Qkk), and the
#     account runs the system's shell;
#   - pacman.conf holds Hyprland at the version CitronOS is made for;
#   - AirDrop's service listens on nothing with receiving off (a new account's
#     default), and the firewall keeps AirDrop and AirPlay out of "public";
#   - the lock screen killed while locked: a new one holds the lock within 3 s,
#     5 of 5 times;
#   - the shell killed again and again: safe mode within five kills.
set -u
say() { echo "gg-selftest: $*"; }
fails=0
ok() { say "ok: $*"; }
bad() { say "FAIL: $*"; fails=$((fails + 1)); }
ms() { echo $(( $(date +%s%N) / 1000000 )); }
active() { systemctl --user is-active -q "$1"; }
main_pid() { systemctl --user show -p MainPID --value "$1"; }

# Wait for the shell, then for the boot test's screenshot (taken SETTLE, 40 s,
# after the shell loads) before anything is killed.
for _ in $(seq 120); do active citronos-shell.service && break; sleep 1; done
sleep "${GG_SELFTEST_DELAY:-75}"
say "start"

# ---------------------------------------------------------------- units
for unit in citronos-shell citronos-lock citronos-airdrop citronos-icon-resolver; do
  if active "$unit.service"; then ok "$unit is running"
  else bad "$unit is $(systemctl --user is-active "$unit.service")"; systemctl --user status --no-pager -n 8 "$unit.service" | sed 's/^/gg-selftest:   /'
  fi
done

# ---------------------------------------------------------------- the packages
# The image is an install of CitronOS's packages (T-2.1): every file of theirs
# as packaged, and the account runs the system's shell, with no copy of its own.
packages=$(pacman -Qq | grep '^citronos' | tr '\n' ' ')
if [[ -z $packages ]]; then bad "no citronos packages are installed"
elif changed=$(sudo -n pacman -Qkk $packages 2>&1 | grep -vE '^[a-z0-9-]+: [0-9]+ total files, 0 altered files$'); [[ -n $changed ]]; then
  bad "pacman -Qkk finds packaged files changed: $(echo "$changed" | head -n 3 | tr '\n' ' ')"
else ok "pacman -Qkk: every file of $packages as packaged"
fi
[[ ! -e ${XDG_CONFIG_HOME:-$HOME/.config}/quickshell ]] && ok "the shell is the system's (no ~/.config/quickshell)" \
  || bad "this account has a shell of its own in ~/.config/quickshell"

# ---------------------------------------------------------------- Hyprland held
# pacman.conf holds Hyprland (pacman-config.sh, by the pacman hook when the
# image was built), so a pacman -Syu on an installed system can't take 0.57,
# which no longer reads hyprland.conf; the installer copies this pacman.conf.
held=$(pacman-conf IgnorePkg 2>/dev/null | tr '\n' ' ')
[[ " $held " == *" hyprland "* ]] && ok "pacman holds Hyprland ($(pacman -Q hyprland))" \
  || bad "pacman.conf doesn't hold Hyprland (IgnorePkg: '${held:-none}')"

# ---------------------------------------------------------------- AirDrop and the firewall
if ss -Hlntup | grep -q ':53317\b'; then bad "something listens on AirDrop's port with receiving off: $(ss -Hlntup | grep ':53317\b')"
else ok "nothing listens on AirDrop's port (53317) with receiving off"
fi
if [[ $(sudo -n firewall-cmd --state 2>&1) == running ]]; then
  ok "firewalld is running"
  iface=$(ip -o route show default | awk '{print $5; exit}')
  zone=$(sudo -n firewall-cmd --get-zone-of-interface="$iface" 2>&1)
  # QEMU's network is wired: home, by 50-citronos-zone.
  [[ $zone == home ]] && ok "the wired network ($iface) is in the home zone" || bad "the wired network ($iface) is in zone '$zone', not home"
  for service in citronos-airdrop citronos-airplay; do
    sudo -n firewall-cmd --zone=public --query-service="$service" >/dev/null 2>&1 \
      && bad "the public zone lets $service in" || ok "the public zone keeps $service out"
    sudo -n firewall-cmd --zone=home --query-service="$service" >/dev/null 2>&1 \
      && ok "the home zone lets $service in" || bad "the home zone doesn't know $service"
  done
else
  bad "firewalld isn't running: $(sudo -n firewall-cmd --state 2>&1)"
fi

# ---------------------------------------------------------------- the lock screen
# Where gg-lock finds it: the account's own copy, else the system's (/etc/xdg).
lock_qml="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/golden-gate/lock-shell.qml"
[[ -e $lock_qml ]] || lock_qml=/etc/xdg/quickshell/golden-gate/lock-shell.qml
lock_state() { timeout 2 qs -p "$lock_qml" ipc call lock isLocked 2>/dev/null | tr -d '[:space:]'; }
gg-lock
for _ in $(seq 25); do [[ $(lock_state) == true ]] && break; sleep 0.2; done
if [[ $(lock_state) == true ]]; then
  ok "gg-lock locked the screen"
  restored=0 times=()
  for round in 1 2 3 4 5; do
    pid=$(main_pid citronos-lock.service)
    t0=$(ms); kill -SEGV "$pid" 2>/dev/null; sleep 0.2
    back=false
    while (( $(ms) - t0 < 3000 )); do [[ $(lock_state) == true ]] && { back=true; break; }; sleep 0.1; done
    took=$(( $(ms) - t0 ))
    if $back; then restored=$((restored + 1)); times+=("$took"); else say "  kill $round (pid $pid): nothing holding the lock after 3 s"; fi
    for _ in $(seq 20); do [[ $(lock_state) == true ]] && break; sleep 0.25; done
    sleep 1
  done
  [[ $restored == 5 ]] && ok "the lock screen killed while locked held the lock again within 3 s, 5 of 5 (${times[*]} ms)" \
    || bad "the lock screen killed while locked held the lock again within 3 s only $restored of 5 times (${times[*]:-} ms)"
else
  bad "gg-lock didn't lock the screen"
fi

# ---------------------------------------------------------------- safe mode
safe_after=""
for kill in 1 2 3 4 5 6 7; do
  pid=$(main_pid citronos-shell.service)
  systemctl --user kill -s KILL citronos-shell.service
  for _ in $(seq 40); do
    active citronos-shell-safe.service && break
    new=$(main_pid citronos-shell.service)
    active citronos-shell.service && [[ $new != 0 && $new != "$pid" ]] && break
    sleep 0.25
  done
  if active citronos-shell-safe.service; then safe_after=$kill; break; fi
  active citronos-shell.service || { say "  after kill $kill the shell is $(systemctl --user is-active citronos-shell.service)"; }
done
if [[ -n $safe_after ]]; then
  pid=$(main_pid citronos-shell-safe.service)
  tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qx GG_SAFE=1 && safe_env=", with GG_SAFE=1" || safe_env=", but without GG_SAFE=1"
  (( safe_after <= 5 )) && ok "safe mode took over after $safe_after kills$safe_env" \
    || bad "safe mode took over only after $safe_after kills (five should do)$safe_env"
else
  bad "seven kills and no safe mode (the shell is $(systemctl --user is-active citronos-shell.service))"
fi

say "done: $fails failed"
