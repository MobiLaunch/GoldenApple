#!/bin/sh
# gg-lock: lock the screen (hypridle's lock_cmd, ⌃⌘Q, Lock Screen in the menus).
# The lock screen is a process of its own (citronos-lock.service, or
# `gg-lock serve`), so a shell crash can't unlock the session, and a lock
# screen that crashes comes straight back locked: the marker below says the
# session is locked, and a lock screen that starts while it's there locks at
# once. The lock screen removes it when the session is unlocked.
lock="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/golden-gate/lock-shell.qml"
marker="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/citronos-locked"

if [ "${1:-}" = serve ]; then exec qs -p "$lock"; fi

: > "$marker"
qs -p "$lock" ipc call lock lock >/dev/null 2>&1 && exit 0
# It isn't running: start it, and it locks on its own.
systemctl --user start citronos-lock.service >/dev/null 2>&1 && exit 0
nohup qs -p "$lock" >/dev/null 2>&1 &
