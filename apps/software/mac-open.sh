#!/bin/sh
# gg-mac-open TOKEN: open a Mac app with Darling, as its Launchpad icon does.
# If it doesn't open, say so in a notification rather than doing nothing.
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=$(python3 "$here/macapps.py" open "$1" | tail -n 1)
case "$out" in
  *'"event":"error"'*)
    msg=$(printf '%s' "$out" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("message", ""))')
    notify-send -a "App Store" -i system-software-install "Mac app" "$msg" 2>/dev/null || printf '%s\n' "$msg" >&2
    exit 1 ;;
esac
