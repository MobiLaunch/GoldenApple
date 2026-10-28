#!/bin/sh
# gg-lock: lock the screen (hypridle's lock_cmd, ⌃⌘Q, Lock Screen in the menus).
# The lock screen is a process of its own (citronos-lock.service, or
# `gg-lock serve`), so a shell crash can't unlock the session, and a lock
# screen that crashes comes straight back locked: the marker below says the
# session is locked, and a lock screen that starts while it's there locks at
# once. The lock screen removes it when the session is unlocked.
# The lock screen beside the shell, found as `qs -c golden-gate` finds the
# shell: an account's own copy first, then the system's (/etc/xdg, from the
# citronos-shell package).
own="${XDG_CONFIG_HOME:-$HOME/.config}"
lock="$own/quickshell/golden-gate/lock-shell.qml"
IFS=:
for dir in $own ${XDG_CONFIG_DIRS:-/etc/xdg}; do
  if [ -e "$dir/quickshell/golden-gate/lock-shell.qml" ]; then lock="$dir/quickshell/golden-gate/lock-shell.qml"; break; fi
done
unset IFS
marker="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/citronos-locked"
# The lock screen only reads preferences (the wallpaper, Touch ID, its
# message): from the file, watched, with no D-Bus bridge to start beside it
# each time it starts (apps/lib/services/Preferences.qml).
export GG_PREFS_READONLY=1
# No crash handler: Quickshell's forks a reporter that writes a dump of the
# process (whatever password was being typed included) and holds its
# compositor connection, and so its lock, open until it's done, so the next
# lock screen couldn't lock until then. A crashed lock screen leaves no report;
# it comes straight back.
export QS_DISABLE_CRASH_HANDLER=1

if [ "${1:-}" = serve ]; then exec qs -p "$lock"; fi

: > "$marker"
qs -p "$lock" ipc call lock lock >/dev/null 2>&1 && exit 0
# It isn't running: start it, and it locks on its own.
systemctl --user start citronos-lock.service >/dev/null 2>&1 && exit 0
nohup qs -p "$lock" >/dev/null 2>&1 &
