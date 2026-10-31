#!/bin/sh
# Open AirDrop, optionally with files to share (Files ▸ Share ▸ AirDrop, or
# `gg-airdrop FILE…`): they wait in the window until you pick a device.
dir="$(dirname "$0")"
# gg-airdrop --set off|everyone-10min|everyone: who can send to this computer
# (Control Center). Receiving is off until it's turned on.
if [ "${1:-}" = --set ]; then exec python3 "$dir/airdropd.py" set "${2:-everyone-10min}"; fi
# gg-airdrop --serve: the service itself (citronos-airdrop.service).
if [ "${1:-}" = --serve ]; then exec python3 "$dir/airdropd.py" serve; fi
if [ "$#" -gt 0 ]; then
  f="${XDG_RUNTIME_DIR:-/tmp}/gg-airdrop-pending"
  : > "$f.tmp"
  for p in "$@"; do
    case "$p" in file://*) p="$(printf '%s' "${p#file://}" | sed 's/%20/ /g')" ;; esac
    realpath -- "$p" >> "$f.tmp" 2>/dev/null
  done
  mv "$f.tmp" "$f"
fi
exec qs -n -p "$dir/../airdrop.qml"
