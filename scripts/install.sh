#!/usr/bin/env bash
# Install the Golden Gate desktop.
#
#   scripts/install.sh                 into your home directory (existing Arch + Hyprland)
#   scripts/install.sh --system ROOT   into a root filesystem: /etc/skel + /usr/share,
#                                      plus the system pieces below (used by the ISO build)
#   sudo scripts/install.sh --extras   system integration + shared runtime for new accounts
#   scripts/install.sh --extras ROOT   same operation staged under ROOT (CI/testing)
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
  ROOT="${2:-}"
  if [[ -n $ROOT ]]; then
    ROOT="$(realpath -m "$ROOT")"
  else
    [[ $EUID -eq 0 ]] || { echo "--extras writes to /etc and /usr: run with sudo"; exit 1; }
  fi
fi

say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }

# System pieces: keyd ⌘ layer, SDDM theme, Plymouth splash. $1 = root prefix.
install_extras() {
  local R=$1
  say "local account setup helper → $R/usr/lib/golden-gate"
  install -Dm644 "$REPO/third_party/hyprglass/LICENSE" "$R/usr/share/licenses/golden-gate/hyprglass/LICENSE"
  install -Dm755 "$REPO/apps/setup/account-helper.py" "$R/usr/lib/golden-gate/account-helper.py"
  install -Dm644 "$REPO/apps/setup/save-preferences.py" "$R/usr/lib/golden-gate/save-preferences.py"
  install -Dm755 "$REPO/apps/setup/pref-helper.py" "$R/usr/lib/golden-gate/pref-helper.py"
  install -Dm755 "$REPO/compositor/hyprland/hyprglass-sync.sh" "$R/usr/lib/golden-gate/hyprglass-sync.sh"
  install -Dm755 "$REPO/compositor/hyprland/apply-preferences.sh" "$R/usr/lib/golden-gate/apply-preferences.sh"
  # Standard password-authenticated administration for accounts created in Hello.
  install -d -m755 "$R/etc/sudoers.d"
  if [[ ! -e "$R/etc/sudoers.d/20-golden-wheel" ]]; then
    printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$R/etc/sudoers.d/20-golden-wheel"
    chmod 440 "$R/etc/sudoers.d/20-golden-wheel"
  fi

  # Account creation happens before the new user has ever logged in. Install a
  # root-owned shared runtime plus a Golden Gate /etc/skel so useradd produces a
  # usable desktop instead of a bare Hyprland account on existing Arch systems.
  # In --system mode the same files already exist; refreshing them is harmless.
  say "shared Golden Gate runtime → $R/usr/share/golden-gate"
  local SHARE="$R/usr/share/golden-gate"
  local BIN="$R/usr/local/bin"
  mkdir -p "$SHARE" "$R/usr/share/applications" "$R/usr/share/icons" "$R/usr/share/backgrounds/golden-gate" "$BIN"
  # One canonical UI component store. Every Golden Gate app imports lib/, but
  # lib is now a link to this shared copy rather than a per-app component fork.
  rm -rf "$SHARE/ui" "$SHARE/apps"
  cp -a "$REPO/apps/lib" "$SHARE/ui"
  cp -a "$REPO/apps" "$SHARE/apps"
  rm -rf "$SHARE/apps/lib"
  ln -s ../ui "$SHARE/apps/lib"
  rm -rf "$SHARE/apps/desktop"
  for f in "$REPO"/apps/desktop/*.desktop; do
    sed 's#@APPS@#/usr/share/golden-gate/apps#g' "$f" > "$R/usr/share/applications/$(basename "$f")"
  done
  # Ghostty is the terminal engine, but Golden Gate Terminal owns its user-facing
  # desktop identity. Shadow the upstream launcher so Applications shows one Terminal.
  mkdir -p "$R/usr/local/share/applications"
  cat > "$R/usr/local/share/applications/com.mitchellh.ghostty.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Ghostty
Exec=ghostty
NoDisplay=true
EOF
  printf '#!/bin/sh\nexec bash /usr/share/golden-gate/apps/setup/diagnostics.sh "$@"\n' > "$BIN/gg-diagnostics"
  printf '#!/bin/sh\nexec bash /usr/share/golden-gate/apps/settings/open.sh "$@"\n' > "$BIN/gg-settings"
  printf '#!/bin/sh\nexec sh /usr/share/golden-gate/apps/browser/launch.sh "$@"\n' > "$BIN/gg-web"
  printf '#!/bin/sh\nexec sh /usr/share/golden-gate/apps/installer/launch.sh "$@"\n' > "$BIN/gg-install"
  printf '#!/bin/sh\nexec sh /usr/share/golden-gate/apps/software/open.sh "$@"\n' > "$BIN/gg-software"
  printf '#!/bin/sh\nexec sh /usr/share/golden-gate/apps/files/open.sh "$@"\n' > "$BIN/gg-files"
  printf '#!/bin/sh\nexec python3 /usr/lib/golden-gate/pref-helper.py "$@"\n' > "$BIN/gg-pref"
  printf '#!/bin/sh\nexec /usr/lib/golden-gate/hyprglass-sync.sh "$@"\n' > "$BIN/gg-hyprglass-sync"
  printf '#!/bin/sh\nexec /usr/lib/golden-gate/apply-preferences.sh "$@"\n' > "$BIN/gg-apply-preferences"
  cp "$REPO/distro/archiso/overlay/usr/local/bin/gg-session" "$BIN/gg-session"
  chmod 755 "$BIN/gg-diagnostics" "$BIN/gg-settings" "$BIN/gg-web" "$BIN/gg-install" "$BIN/gg-software" "$BIN/gg-files" "$BIN/gg-pref" "$BIN/gg-hyprglass-sync" "$BIN/gg-apply-preferences" "$BIN/gg-session"
  mkdir -p "$R/usr/share/wayland-sessions"
  cat > "$R/usr/share/wayland-sessions/golden-gate.desktop" <<'EOF'
[Desktop Entry]
Name=Golden Gate
Comment=Golden Gate desktop
Exec=gg-session
Type=Application
DesktopNames=Hyprland
EOF

  rm -rf "$R/usr/share/icons/GoldenGate"
  cp -a "$REPO/icons/GoldenGate" "$R/usr/share/icons/GoldenGate"
  for svg in "$REPO"/prototype/assets/wallpapers/*.svg; do
    local name
    name="$(basename "$svg" .svg)"
    cp "$svg" "$R/usr/share/backgrounds/golden-gate/$name.svg"
    if command -v rsvg-convert >/dev/null; then
      rsvg-convert -w 3840 -h 2400 -o "$R/usr/share/backgrounds/golden-gate/$name.png" "$svg"
    fi
  done

  local SKEL="$R/etc/skel"
  if [[ ! -d "$SKEL/.config/quickshell/golden-gate" ]]; then
    say "new-account Golden Gate desktop → $SKEL"
    mkdir -p "$SKEL/.config/hypr/golden-gate" "$SKEL/.config/quickshell" \
             "$SKEL/.config/ghostty/themes" "$SKEL/.config/gtk-4.0" "$SKEL/.config/gtk-3.0" \
             "$SKEL/.config/fontconfig/conf.d"
    sed -e 's#__GG_WALLPAPER__#/usr/share/backgrounds/golden-gate/tide.png#' \
        -e 's#__GG_APPS__#/usr/share/golden-gate/apps#' \
        "$REPO/compositor/hyprland/hyprland.conf" > "$SKEL/.config/hypr/hyprland.conf"
    cp "$REPO/design/dist/hyprland-motion.conf" "$SKEL/.config/hypr/golden-gate/motion.conf"
    cp "$REPO/compositor/hyprland/hypridle.conf" "$SKEL/.config/hypr/hypridle.conf"
    cp "$REPO/compositor/hyprland/report-config-errors.sh" "$SKEL/.config/hypr/golden-gate/report-config-errors.sh"
    cp "$REPO/compositor/hyprland/machine-conf.sh" "$SKEL/.config/hypr/golden-gate/machine-conf.sh"
    chmod 755 "$SKEL/.config/hypr/golden-gate/report-config-errors.sh" "$SKEL/.config/hypr/golden-gate/machine-conf.sh"
    printf '# Written by Setup Assistant (keyboard layout).\n' > "$SKEL/.config/hypr/golden-gate/input.conf"
    printf '# Written by Settings.\n' > "$SKEL/.config/hypr/golden-gate/accessibility.conf"
    printf '# Written by Settings.\n' > "$SKEL/.config/hypr/golden-gate/displays.conf"
    printf '# Filled in by machine-conf.sh when the session starts.\n' > "$SKEL/.config/hypr/golden-gate/machine.conf"
    cp -a "$REPO/shell" "$SKEL/.config/quickshell/golden-gate"
    # The shell consumes the same canonical primitives as apps. Keep only
    # shell-specific controls local; shared Glass/Symbol/springs/Theme resolve
    # to /usr/share/golden-gate/ui for every account created from /etc/skel.
    local SHELL_SKEL="$SKEL/.config/quickshell/golden-gate"
    for shared in Glass.qml Spring.qml SpringValue.qml Symbol.qml TextField.qml; do
      rm -f "$SHELL_SKEL/components/$shared"
      ln -s "/usr/share/golden-gate/ui/$shared" "$SHELL_SKEL/components/$shared"
    done
    rm -rf "$SHELL_SKEL/components/theme" "$SHELL_SKEL/components/assets"
    ln -s "/usr/share/golden-gate/ui/theme" "$SHELL_SKEL/components/theme"
    ln -s "/usr/share/golden-gate/ui/assets" "$SHELL_SKEL/components/assets"
    rm -f "$SHELL_SKEL/theme/Theme.qml"
    ln -s "/usr/share/golden-gate/ui/theme/Theme.qml" "$SHELL_SKEL/theme/Theme.qml"
    cp "$REPO/themes/ghostty/config" "$SKEL/.config/ghostty/config"
    cp "$REPO"/themes/ghostty/themes/* "$SKEL/.config/ghostty/themes/"
    cp "$REPO/design/dist/gtk.css" "$SKEL/.config/gtk-4.0/gtk.css"
    cp "$REPO/design/dist/gtk3.css" "$SKEL/.config/gtk-3.0/gtk.css"
    cp "$REPO/themes/fontconfig/60-golden-gate.conf" "$SKEL/.config/fontconfig/conf.d/60-golden-gate.conf"
    printf '[Default Applications]\nx-scheme-handler/http=org.goldengate.Web.desktop\nx-scheme-handler/https=org.goldengate.Web.desktop\ntext/html=org.goldengate.Web.desktop\ninode/directory=org.goldengate.Files.desktop\ntext/plain=org.goldengate.TextEdit.desktop\ntext/markdown=org.goldengate.TextEdit.desktop\napplication/json=org.goldengate.TextEdit.desktop\nimage/jpeg=org.goldengate.Photos.desktop\nimage/png=org.goldengate.Photos.desktop\nimage/webp=org.goldengate.Photos.desktop\nimage/gif=org.goldengate.Photos.desktop\nimage/tiff=org.goldengate.Photos.desktop\nvideo/mp4=org.goldengate.Photos.desktop\nvideo/quicktime=org.goldengate.Photos.desktop\nvideo/webm=org.goldengate.Photos.desktop\naudio/mpeg=org.goldengate.Music.desktop\naudio/mp4=org.goldengate.Music.desktop\naudio/flac=org.goldengate.Music.desktop\naudio/ogg=org.goldengate.Music.desktop\naudio/opus=org.goldengate.Music.desktop\naudio/x-wav=org.goldengate.Music.desktop\n' > "$SKEL/.config/mimeapps.list"
  fi
  say "GNOME defaults (fonts and icons) → $R/usr/share/glib-2.0/schemas"
  local schema_dir="$R/usr/share/glib-2.0/schemas"
  mkdir -p "$schema_dir"
  cp "$REPO/themes/gsettings/90_golden-gate.gschema.override" "$schema_dir/"
  # During an ArchISO build airootfs is copied before packages are installed.
  # At this point the staged root contains our override but not the package-owned
  # *.gschema.xml files yet. Calling glib-compile-schemas here produces the
  # misleading "No schema files found" message. Pacman's GLib schema hook compiles
  # the directory after gsettings-desktop-schemas is installed. For an existing
  # system (--extras without a staging root), compile immediately instead.
  if command -v glib-compile-schemas >/dev/null 2>&1 \
      && compgen -G "$schema_dir/*.gschema.xml" >/dev/null; then
    glib-compile-schemas "$schema_dir"
  else
    say "GSettings override staged; schema cache will be built when packages are installed"
  fi

  say "keyd ⌘ layer → $R/etc/keyd"
  mkdir -p "$R/etc/keyd"
  cp "$REPO/themes/keyd/default.conf" "$REPO/themes/keyd/app.conf" "$R/etc/keyd/"

  say "SDDM theme → $R/usr/share/sddm/themes/golden-gate"
  local T="$R/usr/share/sddm/themes/golden-gate"
  rm -rf "$T"
  mkdir -p "$T/components" "$T/theme" "$T/assets"
  cp "$REPO"/themes/sddm/golden-gate/* "$T/"

  # The greeter uses the same canonical primitives as the running desktop. Only
  # the lock/login surface and its Qt-only clock helper are shell-specific.
  for shared in Glass.qml TextField.qml Symbol.qml Spring.qml SpringValue.qml; do
    cp "$REPO/apps/lib/$shared" "$T/components/$shared"
  done
  cp "$REPO/shell/components/LockSurface.qml" "$T/components/LockSurface.qml"
  cp "$REPO/shell/components/SystemClockProxy.qml" "$T/components/SystemClockProxy.qml"
  cp "$REPO/apps/lib/theme/Theme.qml" "$T/theme/Theme.qml"
  ln -s ../theme "$T/components/theme"
  ln -s ../assets "$T/components/assets"
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
  install_extras "$ROOT"
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
if [[ $MODE == system ]]; then APPS_RUN=/usr/share/golden-gate/apps; else APPS_RUN="$DATA/golden-gate/apps"; fi
sed -e "s#__GG_WALLPAPER__#$BG_ABS/tide.png#" -e "s#__GG_APPS__#$APPS_RUN#" "$REPO/compositor/hyprland/hyprland.conf" > "$REPO/.hyprland.tmp"
place "$REPO/.hyprland.tmp" "$CONF/hypr/hyprland.conf"
rm -f "$REPO/.hyprland.tmp"
place "$REPO/design/dist/hyprland-motion.conf" "$CONF/hypr/golden-gate/motion.conf"
place "$REPO/compositor/hyprland/hypridle.conf" "$CONF/hypr/hypridle.conf"
place "$REPO/compositor/hyprland/report-config-errors.sh" "$CONF/hypr/golden-gate/report-config-errors.sh"
chmod +x "$CONF/hypr/golden-gate/report-config-errors.sh"
# Keyboard layout, written by Setup Assistant; empty until then.
[[ -e "$CONF/hypr/golden-gate/input.conf" ]] || { mkdir -p "$CONF/hypr/golden-gate"; echo "# Written by Setup Assistant (keyboard layout)." > "$CONF/hypr/golden-gate/input.conf"; }
# Written by Settings (Accessibility, Displays); empty until you change something.
for f in accessibility displays; do
  [[ -e "$CONF/hypr/golden-gate/$f.conf" ]] || echo "# Written by Settings." > "$CONF/hypr/golden-gate/$f.conf"
done
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

# Golden Gate's own apps (Calculator, …): Quickshell configs with desktop entries.
say "apps → $DATA/golden-gate/apps"
rm -rf "$DATA/golden-gate/apps"
mkdir -p "$DATA/golden-gate" "$DATA/applications"
cp -a "$REPO/apps" "$DATA/golden-gate/apps"
rm -rf "$DATA/golden-gate/apps/desktop"
# Canonical component store for installed apps. App-local lib/ is an alias, so
# Button/Switch/Slider/TextField/etc. can never drift between applications.
rm -rf "$DATA/golden-gate/ui" "$DATA/golden-gate/apps/lib"
cp -a "$REPO/apps/lib" "$DATA/golden-gate/ui"
ln -s ../ui "$DATA/golden-gate/apps/lib"

# Collapse shell/app primitives onto the same runtime component store. In a
# staged system image the final target is /usr/share; user installs point at
# their actual XDG data directory.
if [[ $MODE == system ]]; then
  SHARED_UI=/usr/share/golden-gate/ui
else
  SHARED_UI="$DATA/golden-gate/ui"
fi
SHELL_RUNTIME="$CONF/quickshell/golden-gate"
for shared in Glass.qml Spring.qml SpringValue.qml Symbol.qml TextField.qml; do
  rm -f "$SHELL_RUNTIME/components/$shared"
  ln -s "$SHARED_UI/$shared" "$SHELL_RUNTIME/components/$shared"
done
rm -rf "$SHELL_RUNTIME/components/theme" "$SHELL_RUNTIME/components/assets"
ln -s "$SHARED_UI/theme" "$SHELL_RUNTIME/components/theme"
ln -s "$SHARED_UI/assets" "$SHELL_RUNTIME/components/assets"
rm -f "$SHELL_RUNTIME/theme/Theme.qml"
ln -s "$SHARED_UI/theme/Theme.qml" "$SHELL_RUNTIME/theme/Theme.qml"
# gg-diagnostics: a crash and diagnostics report you can read and send.
if [[ $MODE == system ]]; then BIN="$ROOT/usr/local/bin"; else BIN="$HOME/.local/bin"; fi
mkdir -p "$BIN"
printf '#!/bin/sh\nexec bash "%s/setup/diagnostics.sh" "$@"\n' "$APPS_RUN" > "$BIN/gg-diagnostics"
chmod +x "$BIN/gg-diagnostics"
printf '#!/bin/sh\nexec bash "%s/settings/open.sh" "$@"\n' "$APPS_RUN" > "$BIN/gg-settings"
printf '#!/bin/sh\nexec sh "%s/software/open.sh" "$@"\n' "$APPS_RUN" > "$BIN/gg-software"
printf '#!/bin/sh\nexec sh "%s/files/open.sh" "$@"\n' "$APPS_RUN" > "$BIN/gg-files"
RUNTIME="$DATA/golden-gate/runtime"
mkdir -p "$RUNTIME"
cp "$REPO/apps/setup/pref-helper.py" "$RUNTIME/pref-helper.py"
cp "$REPO/compositor/hyprland/hyprglass-sync.sh" "$RUNTIME/hyprglass-sync.sh"
cp "$REPO/compositor/hyprland/apply-preferences.sh" "$RUNTIME/apply-preferences.sh"
chmod 755 "$RUNTIME/pref-helper.py" "$RUNTIME/hyprglass-sync.sh" "$RUNTIME/apply-preferences.sh"
if [[ $MODE == system ]]; then
  printf '#!/bin/sh\nexec python3 /usr/share/golden-gate/runtime/pref-helper.py "$@"\n' > "$BIN/gg-pref"
  printf '#!/bin/sh\nexec /usr/share/golden-gate/runtime/hyprglass-sync.sh "$@"\n' > "$BIN/gg-hyprglass-sync"
  printf '#!/bin/sh\nexec /usr/share/golden-gate/runtime/apply-preferences.sh "$@"\n' > "$BIN/gg-apply-preferences"
else
  printf '#!/bin/sh\nexec python3 "%s/pref-helper.py" "$@"\n' "$RUNTIME" > "$BIN/gg-pref"
  printf '#!/bin/sh\nexec "%s/hyprglass-sync.sh" "$@"\n' "$RUNTIME" > "$BIN/gg-hyprglass-sync"
  printf '#!/bin/sh\nexec "%s/apply-preferences.sh" "$@"\n' "$RUNTIME" > "$BIN/gg-apply-preferences"
fi
chmod +x "$BIN/gg-settings" "$BIN/gg-software" "$BIN/gg-files" "$BIN/gg-pref" "$BIN/gg-hyprglass-sync" "$BIN/gg-apply-preferences"
for f in "$REPO"/apps/desktop/*.desktop; do
  sed "s#@APPS@#$APPS_RUN#g" "$f" > "$DATA/applications/$(basename "$f")"
done
cat > "$DATA/applications/com.mitchellh.ghostty.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Ghostty
Exec=ghostty
NoDisplay=true
EOF
# Terminal: its own title bar and Terminal.app's look
place "$REPO/themes/ghostty/config" "$CONF/ghostty/config"
for f in "$REPO"/themes/ghostty/themes/*; do place "$f" "$CONF/ghostty/themes/$(basename "$f")"; done

# Web owns the browser UI and Chromium engine; do not expose a second browser chrome.
printf '#!/bin/sh\nexec sh "%s/browser/launch.sh" "$@"\n' "$APPS_RUN" > "$BIN/gg-web"
printf '#!/bin/sh\nexec sh "%s/installer/launch.sh" "$@"\n' "$APPS_RUN" > "$BIN/gg-install"
chmod +x "$BIN/gg-web" "$BIN/gg-install"
# System paths inside generated launchers must refer to the booted image, not its build root.
# Respect an existing browser choice; seed MIME defaults only on a fresh install.
if [[ ! -e "$CONF/mimeapps.list" ]]; then
  printf '[Default Applications]\nx-scheme-handler/http=org.goldengate.Web.desktop\nx-scheme-handler/https=org.goldengate.Web.desktop\ntext/html=org.goldengate.Web.desktop\ninode/directory=org.goldengate.Files.desktop\ntext/plain=org.goldengate.TextEdit.desktop\ntext/markdown=org.goldengate.TextEdit.desktop\napplication/json=org.goldengate.TextEdit.desktop\nimage/jpeg=org.goldengate.Photos.desktop\nimage/png=org.goldengate.Photos.desktop\nimage/webp=org.goldengate.Photos.desktop\nimage/gif=org.goldengate.Photos.desktop\nimage/tiff=org.goldengate.Photos.desktop\nvideo/mp4=org.goldengate.Photos.desktop\nvideo/quicktime=org.goldengate.Photos.desktop\nvideo/webm=org.goldengate.Photos.desktop\naudio/mpeg=org.goldengate.Music.desktop\naudio/mp4=org.goldengate.Music.desktop\naudio/flac=org.goldengate.Music.desktop\naudio/ogg=org.goldengate.Music.desktop\naudio/opus=org.goldengate.Music.desktop\naudio/x-wav=org.goldengate.Music.desktop\n' > "$CONF/mimeapps.list"
fi

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

