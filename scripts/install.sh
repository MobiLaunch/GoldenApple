#!/usr/bin/env bash
# Install the Golden Gate desktop.
#
#   scripts/install.sh                 into your home directory (existing Arch + Hyprland)
#   scripts/install.sh --system ROOT   into a root filesystem: /etc/skel + /usr/share
#                                      (used by distro/archiso/build.sh)
#
# Existing files are backed up next to themselves as *.bak-YYYYmmdd-HHMMSS.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=user
ROOT=""
if [[ "${1:-}" == "--system" ]]; then
  MODE=system
  ROOT="$(realpath -m "${2:?usage: install.sh --system ROOT}")"
fi

if [[ $MODE == user ]]; then
  CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
  DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
  BG_PATH="~/.local/share/backgrounds/golden-gate"
else
  CONF="$ROOT/etc/skel/.config"
  DATA="$ROOT/usr/share"
  BG_PATH="/usr/share/backgrounds/golden-gate"
fi
STAMP="$(date +%Y%m%d-%H%M%S)"

say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }
place() { # place SRC DEST: copy with backup of a differing existing file
  local src=$1 dest=$2
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest && ! -L $dest ]] && ! cmp -s "$src" "$dest"; then
    mv "$dest" "$dest.bak-$STAMP"
    say "backed up $(basename "$dest") → $(basename "$dest").bak-$STAMP"
  fi
  cp "$src" "$dest"
}

# 1. Regenerate themes from tokens (outputs are committed, so Node is optional).
if command -v node >/dev/null; then
  say "building design tokens and icons"
  node "$REPO/design/build.mjs" >/dev/null
  node "$REPO/icons/build.mjs" >/dev/null
fi

# 2. Compositor
say "Hyprland config → $CONF/hypr"
place "$REPO/compositor/hyprland/hyprland.conf" "$CONF/hypr/hyprland.conf"
place "$REPO/design/dist/hyprland-motion.conf" "$CONF/hypr/golden-gate/motion.conf"
place "$REPO/compositor/hyprland/hypridle.conf" "$CONF/hypr/hypridle.conf"
sed "s#~/.local/share/backgrounds/golden-gate#$BG_PATH#g" "$REPO/compositor/hyprland/hyprpaper.conf" > "$REPO/.hyprpaper.tmp"
place "$REPO/.hyprpaper.tmp" "$CONF/hypr/hyprpaper.conf"
rm -f "$REPO/.hyprpaper.tmp"

# 3. Shell
say "Quickshell shell → $CONF/quickshell/golden-gate"
rm -rf "$CONF/quickshell/golden-gate"
mkdir -p "$CONF/quickshell"
cp -a "$REPO/shell" "$CONF/quickshell/golden-gate"

# 4. Toolkit theming + fonts
say "GTK 4 / libadwaita overrides, fontconfig"
place "$REPO/design/dist/gtk.css" "$CONF/gtk-4.0/gtk.css"
place "$REPO/themes/fontconfig/60-golden-gate.conf" "$CONF/fontconfig/conf.d/60-golden-gate.conf"

# 5. Icons
say "icon theme → $DATA/icons/GoldenGate"
rm -rf "$DATA/icons/GoldenGate"
mkdir -p "$DATA/icons"
cp -a "$REPO/icons/GoldenGate" "$DATA/icons/GoldenGate"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f "$DATA/icons/GoldenGate" || true

# 6. Wallpapers (hyprpaper needs raster images)
BG_DIR="$DATA/backgrounds/golden-gate"
mkdir -p "$BG_DIR"
for svg in "$REPO"/prototype/assets/wallpapers/*.svg; do
  name="$(basename "$svg" .svg)"
  cp "$svg" "$BG_DIR/$name.svg"
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w 3840 -h 2400 -o "$BG_DIR/$name.png" "$svg"
  else
    say "rsvg-convert not found (install librsvg); skipping $name.png"
  fi
done

say "done. Log into a Hyprland session (or run: hyprctl reload && qs -c golden-gate)."
