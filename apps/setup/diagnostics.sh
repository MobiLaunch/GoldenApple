#!/usr/bin/env bash
# gg-diagnostics: writes a crash and diagnostics report you can read and send.
#
#   gg-diagnostics [--crash APP] [--send]
#
# The report (this computer's hardware and versions, recent crashes, errors
# logged this boot, and the end of the desktop's logs; never the contents of
# your files) is saved in ~/Documents/Diagnostics and opened for you to read.
# --send also opens a new bug report for the CitronOS developers with the
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
report="$dir/CitronOS Report $(date '+%Y-%m-%d at %H.%M.%S').txt"
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

{
  echo "CitronOS diagnostics report"
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
  echo "== Desktop services"
  printf 'xdg-desktop-portal: '
  systemctl --user is-active xdg-desktop-portal.service 2>/dev/null || true
  printf 'xdg-desktop-portal-hyprland: '
  systemctl --user is-active xdg-desktop-portal-hyprland.service 2>/dev/null || true
  printf 'secret service: '
  busctl --user --no-pager --list 2>/dev/null | grep -q 'org.freedesktop.secrets' && echo active || echo unavailable
  printf 'XDG_DATA_DIRS: %s\n' "${XDG_DATA_DIRS:-}"

  echo
  echo "== HyprGlass"
  hyprctl plugin list 2>/dev/null | sed -n '/hyprglass/,+8p' || true
  hyprctl getoption plugin:hyprglass:layers:enabled 2>/dev/null || true
  echo
  echo "== App Store"
  flatpak --user remotes --columns=name,url 2>/dev/null || true
  storelog="$HOME/.local/state/golden-gate/app-store.log"
  [ -f "$storelog" ] && tail -n 40 "$storelog" | cut -c1-240
  echo
  echo "== Mac app launches (Darling)"
  printf 'Darling executable: '
  command -v darling 2>/dev/null || echo unavailable
  pacman -Q darling-bin darling darling-git 2>/dev/null || true
  # Do not probe by launching Darling: an already broken loader would crash
  # again. Read the launch output that the App Store already captured instead.
  python3 - "${XDG_CACHE_HOME:-$HOME/.cache}/golden-gate" <<'PY'
from pathlib import Path
import sys

cache = Path(sys.argv[1])
logs = cache / "mac-logs"
try:
    launches = sorted((p for p in logs.glob("*.log")
                       if p.is_file() and not p.is_symlink()
                       and not p.name.startswith("install-")),
                      key=lambda p: p.stat().st_mtime, reverse=True)[:5]
    if not launches:
        print("No Mac app launch logs recorded.")
    for p in launches:
        print(f"\nLaunch log: {p}")
        # dyld's missing-library reason often precedes hundreds of unrelated
        # shutdown lines. Preserve both ends, with bounded memory and output.
        with p.open("rb") as stream:
            head = stream.read(65536)
            size = stream.seek(0, 2)
            if size > len(head):
                stream.seek(max(len(head), size - 65536))
                tail = stream.read(65536)
                lines = (head.decode(errors="replace").splitlines()[:60]
                         + ["... log excerpt; full log at the path above ..."]
                         + tail.decode(errors="replace").splitlines()[-60:])
            else:
                lines = head.decode(errors="replace").splitlines()
                if len(lines) > 120:
                    lines = lines[:60] + ["... omitted middle lines ..."] + lines[-60:]
        for line in lines:
            print(line[:240])
    setup = cache / "darling-setup.log"
    if setup.is_file() and not setup.is_symlink():
        print(f"\nSetup log (end): {setup}")
        with setup.open("rb") as stream:
            stream.seek(max(0, stream.seek(0, 2) - 65536))
            for line in stream.read(65536).decode(errors="replace").splitlines()[-40:]:
                print(line[:240])
except OSError as exc:
    print(f"Could not read Mac app logs: {exc}")
PY
  echo
  echo "== CitronOS shell"
  pgrep -a qs 2>/dev/null || true
  systemctl --user --no-pager status 'citronos-*' 2>/dev/null | head -n 40
  journalctl --user -u citronos-shell -u citronos-shell-safe -n 80 --no-pager -o short 2>/dev/null | cut -c1-240
  shelllog="$HOME/.local/state/golden-gate-shell.log"      # without a systemd user session
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
