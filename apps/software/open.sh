#!/bin/sh
# Golden Gate App Store launcher.
# GNOME Software on Arch is useful with its Flatpak plugin; ensure the per-user
# Flathub source exists before opening the UI. Network failures are non-fatal and
# are retried the next time the App Store is opened.
set -u

if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak --user remotes --columns=name 2>/dev/null | grep -qx flathub; then
    if command -v nm-online >/dev/null 2>&1; then nm-online -q -t 4 >/dev/null 2>&1 || true; fi
    timeout 15 flatpak --user remote-add --if-not-exists flathub       https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  fi
  # Refresh metadata without blocking the storefront.
  (flatpak --user update --appstream -y >/dev/null 2>&1 || true) &
fi

exec gnome-software "$@"
