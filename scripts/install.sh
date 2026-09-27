#!/usr/bin/env bash
# Install the Golden Gate desktop.
#
#   scripts/install.sh                 into your home directory (existing Arch + Hyprland)
#   scripts/install.sh --system ROOT   into a root filesystem: /etc/skel + /usr/share,
#                                      plus the system pieces below (used by the ISO build)
#   sudo scripts/install.sh --extras   only the system pieces, into / on this machine:
#                                      keyd ⌘ layer, SDDM login theme, Plymouth splash
#
# Existing files are backed up next to themselves as *.bak-YYYYmmdd-HHMMSS.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=user
ROOT=""
if [[ "${1:-}" == "--system" ]]; then
  MODE=system
  ROOT="$(realpath -m "${2:?usage: install.sh --system ROOT}")"
elif [[ "${1:-}" == "--extras" ]]; then
  MODE=extras
  ROOT=""
  [[ $EUID -eq 0 ]] || { echo "--extras writes to /etc and /usr: run with sudo"; exit 1; }
fi

say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }

# System pieces: keyd ⌘ layer, SDDM theme, Plymouth splash. $1 = root prefix.
install_extras() {
  local R=$1
  say "keyd ⌘ layer → $R/etc/keyd"
  mkdir -p "$R/etc/keyd"
  cp "$REPO/themes/keyd/default.conf" "$REPO/themes/keyd/app.conf" "$R/etc/keyd/"

  say "SDDM theme → $R/usr/share/sddm/themes/golden-gate"
  local T="$R/usr/share/sddm/themes/golden-gate"
  rm -rf "$T"; mkdir -p "$T/assets"
  cp "$REPO"/themes/sddm/golden-gate/* "$T/"
  cp -a "$REPO/shell/components" "$REPO/shell/theme" "$T/"
  cp -a "$REPO/shell/assets/symbols" "$T/assets/"
  mkdir -p "$R/etc/sddm.conf.d"
  printf '[Theme]\nCurrent=golden-gate\n\n[General]\nGreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell\n' > "$R/etc/sddm.conf.d/golden-gate.conf"

  say "Plymouth splash → $R/usr/share/plymouth/themes/golden-gate"
  local P="$R/usr/share/plymouth/themes/golden-gate"
  mkdir -p "$P"
  cp "$REPO"/themes/plymouth/golden-gate/* "$P/"
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w 96 -h 96 -o "$P/logo.png" "$REPO/shell/assets/symbols/logo.svg"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="180" height="5"><rect width="180" height="5" rx="2.5" fill="#fff" fill-opacity=".22"/></svg>' | rsvg-convert -o "$P/track.png"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="180" height="5"><rect width="180" height="5" rx="2.5" fill="#fff"/></svg>' | rsvg-convert -o "$P/fill.png"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="220" height="34"><rect x=".5" y=".5" width="219" height="33" rx="16.5" fill="#fff" fill-opacity=".14" stroke="#fff" stroke-opacity=".45"/></svg>' | rsvg-convert -o "$P/field.png"
  else
    say "rsvg-convert not found (install librsvg); Plymouth images skipped"
  fi
}

if [[ $MODE == extras ]]; then
  install_extras ""
  say "done. Enable with: systemctl enable --now keyd; systemctl enable sddm; plymouth-set-default-theme -R golden-gate"
  exit 0
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
BG_ABS="${BG_PATH/#\~/$HOME}"
sed "s#__GG_WALLPAPER__#$BG_ABS/tide.png#" "$REPO/compositor/hyprland/hyprland.conf" > "$REPO/.hyprland.tmp"
place "$REPO/.hyprland.tmp" "$CONF/hypr/hyprland.conf"
rm -f "$REPO/.hyprland.tmp"
place "$REPO/design/dist/hyprland-motion.conf" "$CONF/hypr/golden-gate/motion.conf"
place "$REPO/compositor/hyprland/hypridle.conf" "$CONF/hypr/hypridle.conf"
place "$REPO/compositor/hyprland/report-config-errors.sh" "$CONF/hypr/golden-gate/report-config-errors.sh"
chmod +x "$CONF/hypr/golden-gate/report-config-errors.sh"
place "$REPO/compositor/hyprland/machine-conf.sh" "$CONF/hypr/golden-gate/machine-conf.sh"
chmod +x "$CONF/hypr/golden-gate/machine-conf.sh"
if [[ $MODE == system ]]; then
  # An image is built on another machine: leave the file empty; gg-session fills
  # it in on the machine that boots.
  echo "# Filled in by machine-conf.sh when the session starts." > "$CONF/hypr/golden-gate/machine.conf"
else
  sh "$CONF/hypr/golden-gate/machine-conf.sh" "$CONF/hypr/golden-gate/machine.conf"
fi

# 3. Shell
say "Quickshell shell → $CONF/quickshell/golden-gate"
rm -rf "$CONF/quickshell/golden-gate"
mkdir -p "$CONF/quickshell"
cp -a "$REPO/shell" "$CONF/quickshell/golden-gate"

# Terminal: its own title bar and Terminal.app's look
place "$REPO/themes/ghostty/config" "$CONF/ghostty/config"
for f in "$REPO"/themes/ghostty/themes/*; do place "$f" "$CONF/ghostty/themes/$(basename "$f")"; done

# 4. Toolkit theming + fonts
say "GTK 4 / libadwaita overrides, fontconfig"
place "$REPO/design/dist/gtk.css" "$CONF/gtk-4.0/gtk.css"
place "$REPO/design/dist/gtk3.css" "$CONF/gtk-3.0/gtk.css"
place "$REPO/themes/fontconfig/60-golden-gate.conf" "$CONF/fontconfig/conf.d/60-golden-gate.conf"

# 5. Icons
say "icon theme → $DATA/icons/GoldenGate"
rm -rf "$DATA/icons/GoldenGate"
mkdir -p "$DATA/icons"
cp -a "$REPO/icons/GoldenGate" "$DATA/icons/GoldenGate"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f "$DATA/icons/GoldenGate" || true

# 6. Wallpapers: PNGs for the shell, lock screen and menu-bar sampling
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

if [[ $MODE == system ]]; then
  install_extras "$ROOT"
else
  say "system pieces (keyd ⌘ layer, login screen, boot splash): sudo scripts/install.sh --extras"
fi

say "done. Log into a Hyprland session (or run: hyprctl reload && qs -c golden-gate)."
