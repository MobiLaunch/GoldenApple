#!/bin/sh
# Log Hyprland config errors to the journal (tag: hyprland-config), so they are
# visible without looking at the screen; the ISO boot test fails on them.
# exec-once runs this while Hyprland is still starting, so wait until its IPC
# answers before asking: an early "IPC didn't respond" is not a config error.
out=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if out=$(hyprctl configerrors 2>&1) && ! printf '%s' "$out" | grep -qiE "respond in time|couldn't|connection refused|no such file"; then
    printf '%s\n' "$out" | grep . | logger -t hyprland-config
    exit 0
  fi
  sleep 2
done
logger -t golden-gate "config check skipped: Hyprland IPC never answered (last reply: $out)"
