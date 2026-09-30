#!/bin/sh
# Golden Gate App Store launcher.
#
# GNOME Software's Flatpak plugin is reliable once the remote and AppStream
# metadata exist. Prepare that state before launching the UI, and never hide
# failures in an endless storefront retry loop.
set -u

state="${XDG_STATE_HOME:-$HOME/.local/state}/golden-gate"
mkdir -p "$state"
log="$state/app-store.log"
remote_url="https://dl.flathub.org/repo/flathub.flatpakrepo"

note() {
  command -v notify-send >/dev/null 2>&1 && notify-send "App Store" "$1" >/dev/null 2>&1 || true
}

{
  printf '\n== %s ==\n' "$(date -Is)"
  echo "Preparing App Store"
} >>"$log"

online=1
if command -v nm-online >/dev/null 2>&1; then
  nm-online -s -q -t 15 >/dev/null 2>&1 || online=0
fi

# NetworkManager can report connected before DNS/TLS is actually usable.
if [ "$online" = 1 ] && command -v curl >/dev/null 2>&1; then
  curl -fsSIL --connect-timeout 6 --max-time 12 "$remote_url" >/dev/null 2>>"$log" || online=0
fi

if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak --user remotes --columns=name 2>/dev/null | grep -qx flathub; then
    if [ "$online" = 1 ]; then
      if ! timeout 30 flatpak --user remote-add --if-not-exists --from flathub "$remote_url" >>"$log" 2>&1; then
        note "Flathub could not be configured. The App Store will open, but downloads may be unavailable."
      fi
    else
      note "Wi-Fi is connected, but the internet is not reachable yet. The App Store will retry next time."
    fi
  fi

  if flatpak --user remotes --columns=name 2>/dev/null | grep -qx flathub && [ "$online" = 1 ]; then
    # Do one bounded metadata refresh before the UI appears. A stale background
    # gnome-software process otherwise keeps surfacing the same connection error.
    timeout 45 flatpak --user update --appstream -y >>"$log" 2>&1 || true
  fi
fi

# Drop a stale background instance so it re-reads the now-prepared Flatpak state.
gnome-software --quit >/dev/null 2>&1 || true
sleep 0.25

exec gnome-software --mode=overview "$@"
