#!/bin/sh
# Point pacman at the Arch Linux Archive as it was on CitronOS's pinned date
# (distro/archive-date, T-2.2), so CI and the ISO build install the packages
# CitronOS was made and tested with, not whatever reached the mirrors since.
# Moving the date is a change of its own, tested like any other.
#
#   distro/pin-archive.sh [ROOT]    then: pacman -Syuu (to the archive's versions)
#
# Why it exists: Hyprland 0.57 reached the mirrors on 2026-10-28 and no longer
# reads hyprland.conf at all, which CitronOS's desktop is written in.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
date=$(tr -d '[:space:]' < "$here/archive-date")
case $date in
  [0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]) ;;
  *) echo "pin-archive.sh: distro/archive-date should be YYYY/MM/DD, not '$date'" >&2; exit 2 ;;
esac
list="${1:-}/etc/pacman.d/mirrorlist"
mkdir -p "$(dirname "$list")"
printf '# Arch Linux Archive, %s (distro/archive-date)\nServer = https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "$date" "$date" > "$list"
echo "pacman: the Arch Linux Archive as of $date"
