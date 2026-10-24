#!/usr/bin/env bash
# Offers a crash report when one of your apps quits unexpectedly, if you chose
# to share crash and diagnostics logs in Setup Assistant (privacy.json).
# systemd-coredump saves a file per crash, readable by its owner; this polls
# for new ones and notifies, with Report… and Ignore.
set -u
conf="${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate/privacy.json"
grep -q '"shareDiagnostics": *true' "$conf" 2>/dev/null || exit 0
here="$(cd "$(dirname "$0")" && pwd)"
uid=$(id -u)
seen=$(ls /var/lib/systemd/coredump 2>/dev/null | grep "\.$uid\." | sort)
while sleep 10; do
  grep -q '"shareDiagnostics": *true' "$conf" 2>/dev/null || exit 0
  now=$(ls /var/lib/systemd/coredump 2>/dev/null | grep "\.$uid\." | sort)
  new=$(comm -13 <(printf '%s\n' "$seen") <(printf '%s\n' "$now") | grep -v '^$')
  seen=$now
  for f in $new; do
    app=${f#core.}; app=${app%%.*}
    # Other people's apps only if that was chosen too.
    case "$app" in quickshell|qs|Hyprland|.Hyprland-wrapp|nautilus|firefox|ghostty) ;; *)
      grep -q '"shareWithDevelopers": *true' "$conf" || continue ;;
    esac
    ( action=$(notify-send -a "CitronOS" -i dialog-warning -A report="Report…" -A ignore="Ignore" \
                 "$app quit unexpectedly" "Send a report to help fix it? You'll see it before anything is sent." 2>/dev/null)
      [ "$action" = report ] && bash "$here/diagnostics.sh" --crash "$app" --send ) &
  done
done
