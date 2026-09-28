#!/bin/bash
# gg-settings [pane]: open Settings, at a pane if one's given. Takes Golden
# Gate's pane ids (wifi, displays, …) and GNOME Settings' panel names (so
# `gnome-control-center display` lands in the right place). A running Settings
# switches to the pane; otherwise a new one opens there.
here=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  ""|wifi|bluetooth|network|battery|general|accessibility|appearance|dock|displays|wallpaper|focus|sound|privacy|users|keyboard|trackpad|about|update|storage|datetime|language) pane=${1:-} ;;
  wwan|vpn) pane=network ;;
  power) pane=battery ;;
  system|info-overview|info|about-page) pane=about ;;
  display|color|night-light) pane=displays ;;
  background) pane=wallpaper ;;
  notifications) pane=focus ;;
  privacy|location|diagnostics|security) pane=privacy ;;
  user-accounts|users) pane=users ;;
  mouse|touchpad|trackpad) pane=trackpad ;;
  universal-access|accessibility) pane=accessibility ;;
  datetime|date-time) pane=datetime ;;
  region|language) pane=language ;;
  multitasking|ubuntu) pane=dock ;;
  -*) pane= ;;
  *)
    # A panel Settings doesn't have (printers, online accounts, …): GNOME's.
    [ -x /usr/bin/gnome-control-center ] && XDG_CURRENT_DESKTOP=GNOME exec /usr/bin/gnome-control-center "$@"
    pane= ;;
esac
if [ -n "$pane" ] && qs -p "$here/settings.qml" ipc call settings open "$pane" 2>/dev/null; then
  exec hyprctl dispatch focuswindow class:org.goldengate.Settings >/dev/null 2>&1
fi
qs -p "$here/settings.qml" ipc show >/dev/null 2>&1 && exec hyprctl dispatch focuswindow class:org.goldengate.Settings >/dev/null 2>&1
GG_SETTINGS_PANE=$pane exec qs -n -p "$here/settings.qml"
