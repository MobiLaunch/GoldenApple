#!/usr/bin/env bash
# Import a folder of 1024 px app-icon PNGs (such as github.com/zagnut531/macos-27-icons,
# one folder per beta) as the CitronOS app icons.
#
#   icons/import-icon-pack.sh PACK_DIR
#   node icons/build.mjs
#
# For each name the newest folder wins (folders sorted by name, so "Beta 5" beats
# "Beta 3"). Icons go to icons/custom/apps/<key>.png for the apps the prototype and
# the Dock know by key, and to icons/custom/apps-extra/<freedesktop name>.png for
# Linux apps that have no key of their own. Resized to 512 px, the icon theme's size.
#
# Apple's icons are licensed for Apple platforms only: keep a build that contains
# them private (this repository and its ISO artifacts are).
set -euo pipefail
PACK="${1:?usage: icons/import-icon-pack.sh PACK_DIR}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS="$HERE/custom/apps" EXTRA="$HERE/custom/apps-extra"
mkdir -p "$APPS" "$EXTRA"

# Newest file for a name, across the pack's folders.
newest() { find "$PACK" -type f -name "$1.png" -not -path '*/.git/*' | sort -V | tail -n 1; }
put() { # put ICON_NAME DEST
  local src; src="$(newest "$1")"
  if [[ -z $src ]]; then echo "  missing in pack: $1"; return; fi
  convert "$src" -resize 512x512 -strip -define png:compression-level=9 "$2"
  echo "  $1 → ${2#"$HERE/"}"
}

echo "app keys"
declare -A KEYS=(
  [files]="Finder" [browser]="Safari" [mail]="Mail" [messages]="Messages" [music]="Music"
  [photos]="Photos" [settings]="System Settings" [terminal]="Terminal" [notes]="Notes"
  [calendar]="Calendar" [calculator]="Calculator" [maps]="Maps" [store]="App Store"
  [launcher]="Apps" [weather]="Weather"
)
for key in "${!KEYS[@]}"; do put "${KEYS[$key]}" "$APPS/$key.png"; done
# The Dock draws today's weekday and date on Calendar, like the Mac's live icon,
# over a blank of the same shape.
convert -size 512x512 gradient:'#ffffff-#f2f2f4' \
  \( "$APPS/calendar.png" -alpha extract -threshold 50% -blur 0x0.6 \) \
  -alpha off -compose CopyOpacity -composite "$APPS/calendar-blank.png"
echo "  Calendar → custom/apps/calendar-blank.png (for the Dock's live date)"

# Linux apps without a key, by the icon name their desktop file asks for.
echo "other apps"
declare -A EXTRAS=(
  [org.gnome.clocks]="Clock"
  [org.gnome.TextEditor]="TextEdit"
  [org.gnome.Loupe]="Preview"
  [org.gnome.SystemMonitor]="Activity Monitor"
  [org.gnome.font-viewer]="Font Book"
  [org.gnome.Contacts]="Contacts"
  [org.gnome.Podcasts]="Podcasts"
  [org.gnome.Showtime]="QuickTime Player"
  [org.gnome.Totem]="QuickTime Player"
  [org.gnome.Snapshot]="Photo Booth"
  [org.gnome.SoundRecorder]="Voice Memos"
  [org.gnome.DiskUtility]="Disk Utility"
  [org.gnome.Tour]="Tips"
  [org.gnome.Yelp]="Tips"
  [org.gnome.Characters]="Font Book"
  [org.gnome.baobab]="System Information"
  [org.gnome.Screenshot]="Screenshot"
  [applets-screenshooter]="Screenshot"
  [system-search]="Spotlight"
  [org.gnome.Chess]="Chess"
  [org.gnome.Books]="Books"
  [org.gnome.Notes]="Notes"
  [org.gnome.Evince]="Preview"
  [org.gnome.Papers]="Preview"
  [org.gnome.FileRoller]="Archive Utility"
  [org.gnome.Connections]="Screen Sharing"
)
for name in "${!EXTRAS[@]}"; do put "${EXTRAS[$name]}" "$EXTRA/$name.png"; done
echo "done; now run: node icons/build.mjs"
