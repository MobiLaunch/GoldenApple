#!/bin/bash
# gg-settings [pane]: open Settings, at a pane if one's given. Takes Golden
# Gate's pane ids (wifi, displays, …) and GNOME Settings' panel names (so
# `gnome-control-center display` lands in the right place). A running Settings
# switches to the pane; otherwise a new one opens there.
here=$(cd "$(dirname "$0")/.." && pwd)
case "${1:-}" in
  # Every pane and sub-page in settings.qml opens as itself (tests/settings-open.py).
  ""|wifi|bluetooth|network|battery|general|intelligence|accessibility|appearance|controlcenter|dock|menubar|displays|spotlight|wallpaper|notifications|focus|sound|lockscreen|touchid|privacy|users|keyboard|trackpad|about|update|storage|datetime|language|finishsetup) pane=${1:-} ;;
  wwan|vpn) pane=network ;;
  power) pane=battery ;;
  system|info-overview|info|about-page) pane=about ;;
  display|color|night-light) pane=displays ;;
  background) pane=wallpaper ;;
  location|diagnostics|security) pane=privacy ;;
  fingerprint) pane=touchid ;;
  screensaver|lock-screen) pane=lockscreen ;;
  user-accounts) pane=users ;;
  mouse|touchpad) pane=trackpad ;;
  universal-access) pane=accessibility ;;
  date-time) pane=datetime ;;
  region) pane=language ;;
  multitasking|ubuntu) pane=dock ;;
  sharing|apps|default-apps) pane=general ;;
  -*) pane= ;;
  *)
    # Keep the user inside CitronOS. Unknown legacy panel names land on
    # General until a native pane is implemented instead of switching desktops.
    pane=general ;;
esac
if [ -n "$pane" ] && qs -p "$here/settings.qml" ipc call settings open "$pane" 2>/dev/null; then
  exec hyprctl dispatch focuswindow class:org.goldengate.Settings >/dev/null 2>&1
fi
qs -p "$here/settings.qml" ipc show >/dev/null 2>&1 && exec hyprctl dispatch focuswindow class:org.goldengate.Settings >/dev/null 2>&1
GG_SETTINGS_PANE=$pane exec qs -n -p "$here/settings.qml"
