#!/usr/bin/env bash
# Renders every shell surface and app, light and dark, into one folder for
# design review: tools/preview/gallery.sh [OUT_DIR] [FILTER]
# FILTER (a substring of the shot's name) renders only matching shots.
set -u
cd "$(dirname "$0")/../.."
OUT=${1:-tools/preview/out}
FILTER=${2:-}
mkdir -p "$OUT"
P="python3 tools/preview/preview.py"

shot() {   # name, then preview.py arguments (light and dark are both made)
  local name=$1; shift
  [[ -n $FILTER && $name != *$FILTER* ]] && return
  for look in light dark; do
    local extra=()
    [[ $look == dark ]] && extra=(--dark)
    timeout 120 $P "$@" "${extra[@]}" -o "$OUT/$name-$look.png" 2>"$OUT/$name-$look.log" >/dev/null ||
      echo "failed: $name-$look (see $OUT/$name-$look.log)"
    grep -v -E "RHI|QRhi|Vulkan|GBM|createPlatform|^$" "$OUT/$name-$look.log" | head -5 | sed "s/^/  $name-$look: /"
  done
}

shot desktop          shell
shot controlcenter    shell --do controlcenter.toggle
shot cc-wifi          shell --do controlcenter.detail:wifi
shot cc-bluetooth     shell --do controlcenter.detail:bluetooth
shot cc-sound         shell --do controlcenter.detail:sound
shot notifications    shell --notify
shot notification-center shell --notify --do notifications.toggleCenter
shot spotlight        shell --do spotlight.toggle
shot launchpad        shell --do launchpad.toggle
shot volume           shell --do osd.volume
shot logout           shell --do session.ask:logout
shot lock             shell --env GG_LOCK_PREVIEW=1
for app in settings files notes music photos weather calculator textedit messages maps calendar software airdrop lcode mail clock; do
  shot "app-$app" app "apps/$app.qml"
done
for pane in general wifi bluetooth displays sound desktop dock update users keyboard; do
  shot "settings-$pane" app apps/settings.qml --env "GG_SETTINGS_PANE=$pane"
done
echo "$OUT"
