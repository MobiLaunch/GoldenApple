#!/bin/sh
# gg-session-start: the CitronOS desktop's own services, once Hyprland is up
# (exec-once in hyprland.conf). The shell, AirDrop and the icon resolver run
# as systemd user units under citronos-session.target, which restart them,
# fall back to safe mode, and keep their output in the journal:
#   systemctl --user status 'citronos-*'     journalctl --user -u citronos-shell
# Without a systemd user manager, the shell is kept running here instead.

# What the units need from this session, imported before they start (the
# exec-once lines run at the same time, so it can't be left to another one).
vars="WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_DATA_DIRS PATH LIBGL_ALWAYS_SOFTWARE GG_RENDERER QT_QPA_PLATFORMTHEME"

if systemctl --user show-environment >/dev/null 2>&1 &&
   systemctl --user cat citronos-session.target >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  systemctl --user import-environment $vars 2>/dev/null
  # A shell that hit its limit in an earlier session starts afresh; restart
  # (not start) so a target left running from that session gets this one's
  # display.
  systemctl --user reset-failed 'citronos-*' 2>/dev/null
  exec systemctl --user restart citronos-session.target
fi

logger -t gg-session "no systemd user session; supervising the shell directly"
# The lock screen too, in a process of its own (gg-lock).
( while :; do gg-lock serve; sleep 1; done ) &
log="$HOME/.local/state/golden-gate-shell.log"
mkdir -p "${log%/*}"
while :; do
  [ "$(stat -c %s "$log" 2>/dev/null || echo 0)" -gt 4000000 ] && mv -f "$log" "$log.old"
  if touch "$log" 2>/dev/null; then qs -c golden-gate >>"$log" 2>&1; else qs -c golden-gate; fi
  logger -t gg-shell "Quickshell exited; restarting in 2s"
  sleep 2
done
