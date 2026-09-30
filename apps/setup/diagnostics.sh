#!/usr/bin/env bash
# gg-diagnostics: writes a crash and diagnostics report you can read and send.
#
#   gg-diagnostics [--crash APP] [--send]
#
# The report (this computer's hardware and versions, recent crashes, errors
# logged this boot, and the end of the desktop's logs; never the contents of
# your files) is saved in ~/Documents/Diagnostics and opened for you to read.
# --send also opens a new bug report for the Golden Gate developers with the
# report's summary filled in; nothing is sent until you submit it there.
set -u
# Percent-encodes a string byte by byte (no jq or Python needed).
urlencode() {
  local LC_ALL=C s=$1 out="" c h i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in [a-zA-Z0-9.~_-]) out+=$c ;; *) printf -v h '%%%02X' "'$c"; out+=$h ;; esac
  done
  printf '%s' "$out"
}
crash="" send=0
while [ $# -gt 0 ]; do
  case "$1" in --crash) crash=${2:-}; shift ;; --send) send=1 ;; esac
  shift
done
dir="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")/Diagnostics"
mkdir -p "$dir"
report="$dir/Golden Gate Report $(date '+%Y-%m-%d at %H.%M.%S').txt"
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

{
  echo "Golden Gate diagnostics report"
  echo "Written $(date -R)${crash:+ after $crash quit unexpectedly}"
  echo
  echo "== System"
  grep -E '^(PRETTY_NAME|BUILD_ID|VERSION_ID)=' /etc/os-release 2>/dev/null
  echo "Kernel: $(uname -r) ($(uname -m))"
  echo "CPU: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
  echo "Memory: $(awk '/MemTotal/ {printf "%.1f GB", $2/1048576}' /proc/meminfo)"
  for d in /sys/class/drm/card*/device; do
    [ -e "$d/uevent" ] && echo "Graphics: $(grep -h '^DRIVER=' "$d/uevent" | cut -d= -f2) $(cat "$d/vendor" "$d/device" 2>/dev/null | tr '\n' ' ')"
  done | sort -u
  systemd-detect-virt -q 2>/dev/null && echo "Virtual machine: $(systemd-detect-virt)"
  echo "Hyprland: $(hyprctl version -j 2>/dev/null | grep -m1 '"tag"' | cut -d'"' -f4)"
  echo "Quickshell: $(qs --version 2>/dev/null | head -n1)"
  echo "Screens: $(hyprctl monitors -j 2>/dev/null | grep -E '"(width|height|scale)"' | tr -d ' ,\n')"
  echo
  echo "== Recent crashes"
  ls -t /var/lib/systemd/coredump 2>/dev/null | grep "\.$(id -u)\." | head -n 10 | sed 's/^core\.//; s/\.[0-9a-f]\{32\}\..*//' || true
  coredumpctl list --no-pager -q 2>/dev/null | tail -n 10 || true
  echo
  echo "== Errors this boot"
  journalctl --user -b -p warning --no-pager -q -n 80 2>/dev/null | cut -c1-240
  echo
  echo "== Golden Gate shell"
  pgrep -a qs 2>/dev/null || true
  shelllog="$HOME/.local/state/golden-gate-shell.log"
  [ -f "$shelllog" ] && tail -n 80 "$shelllog" | cut -c1-240
  echo
  echo "== Desktop log (end)"
  log=$(ls -t "$runtime"/hypr/*/hyprland.log 2>/dev/null | head -n1)
  [ -n "$log" ] && tail -n 40 "$log" | cut -c1-240
  qlog=$(ls -t "$runtime"/quickshell/by-id/*/log.log 2>/dev/null | head -n1)
  [ -n "$qlog" ] && tail -n 40 "$qlog" | cut -c1-240
} > "$report" 2>&1

echo "$report"
xdg-open "$report" >/dev/null 2>&1 &
if [ "$send" = 1 ]; then
  url=$(cat /etc/golden-gate/report-url 2>/dev/null || echo "https://github.com/mobilaunch/goldenapple/issues/new")
  body=$(urlencode "$(head -c 5500 "$report")")
  title=$(urlencode "${crash:+$crash quit unexpectedly}")
  xdg-open "$url?title=${title:-Diagnostics%20report}&body=$body" >/dev/null 2>&1 &
fi
