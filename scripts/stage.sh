#!/usr/bin/env bash
# Lay CitronOS out as its packages install it (T-2.1), under DESTDIR:
#
#   scripts/stage.sh PART DESTDIR      (or: make install-PART DESTDIR=…)
#
#   runtime          the apps and shared UI (/usr/share/golden-gate), helpers
#                    (/usr/lib/golden-gate), the gg-* commands (/usr/bin), the
#                    session's units and D-Bus services, desktop entries,
#                    the login session, PAM, polkit, the system's name
#   shell            the shell, /etc/xdg/quickshell/golden-gate: `qs -c
#                    golden-gate` finds it there once an account has no copy
#                    of its own in ~/.config/quickshell
#   hyprland-config  /usr/share/golden-gate/hypr, and a new account's
#                    ~/.config/hypr/hyprland.conf: one line that sources it,
#                    so updating the package never rewrites anyone's file
#   theme            icons, wallpapers, GTK, fonts, keyd, SDDM, Plymouth,
#                    GNOME defaults, default apps
#
# Nothing here writes outside DESTDIR, runs systemctl or touches a home folder:
# what an installed system does on upgrade belongs to pacman's hooks.
# PKGBUILDs (packaging/citronos) call one part per package.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PART="${1:?usage: stage.sh runtime|shell|hyprland-config|theme DESTDIR}"
D="$(realpath -m "${2:?usage: stage.sh PART DESTDIR}")"

SHARE=/usr/share/golden-gate          # where things are on the installed system
LIB=/usr/lib/golden-gate
APPS=$SHARE/apps
HYPR=$SHARE/hypr
WALLPAPER=/usr/share/backgrounds/golden-gate/club-soda.jpg

# The gg-* commands: name, how it runs, what it runs.
WRAPPERS="
gg-diagnostics          bash        $APPS/setup/diagnostics.sh
gg-settings             bash        $APPS/settings/open.sh
gg-web                  sh          $APPS/browser/launch.sh
gg-install              sh          $APPS/installer/launch.sh
gg-software             sh          $APPS/software/open.sh
gg-mac-open             sh          $APPS/software/mac-open.sh
gg-files                sh          $APPS/files/open.sh
gg-archive              sh          $APPS/archive/open.sh
gg-lcode                sh          $APPS/lcode/open.sh
gg-airdrop              sh          $APPS/airdrop/share.sh
gg-intelligence         sh          $APPS/intelligence/open.sh
gg-install-citronpods   bash        $APPS/citronpods/install-engine.sh
gg-citronpods           sh          $APPS/citronpods/ctl.sh
gg-citronpods-bootstrap bash        $APPS/citronpods/bootstrap.sh
gg-tablet-keyboard      sh          $APPS/tablet/keyboard.sh
gg-disk-utility         qs:-n:-p    $APPS/diskutility.qml
gg-pref                 python3     $LIB/pref-helper.py
gg-settingsd            python3     $LIB/settingsd.py
gg-notifyd              python3     $LIB/notifyd.py
gg-hyprglass-sync       -           $LIB/hyprglass-sync.sh
gg-apply-preferences    -           $LIB/apply-preferences.sh
gg-tile                 python3     $LIB/tile.py
gg-icon-resolver        python3     $LIB/icon-resolver.py
gg-idle                 python3     $LIB/idle.py
"

# A builder's own system symbols (local-assets/symbols, never committed: they
# are theirs to use, not CitronOS's to give out), over the shipped ones.
local_symbols() { # local_symbols DEST-DIR
  local svg
  for svg in "$REPO"/local-assets/symbols/*.svg; do
    [[ -e $svg ]] && install -Dm644 "$svg" "$1/${svg##*/}"
  done
  return 0
}

wrappers() {
  local name how target
  while read -r name how target; do
    [[ -n $name ]] || continue
    how=${how//:/ }
    if [[ $how == - ]]; then how=""; else how="$how "; fi
    printf '#!/bin/sh\nexec %s%s "$@"\n' "$how" "$target" | install -Dm755 /dev/stdin "$D/usr/bin/$name"
  done <<< "$WRAPPERS"
}

runtime() {
  # The shared UI, and the apps, whose lib/ is it.
  install -d "$D$SHARE"
  cp -a "$REPO/apps/lib" "$D$SHARE/ui"
  cp -a "$REPO/apps" "$D$APPS"
  rm -rf "$D$APPS/lib" "$D$APPS/desktop"
  ln -s ../ui "$D$APPS/lib"
  local_symbols "$D$SHARE/ui/assets/symbols"
  find "$D$SHARE" -name __pycache__ -type d -prune -exec rm -rf {} +

  # Helpers, beside each other and root-owned.
  local f
  for f in apps/setup/account-helper.py apps/setup/pref-helper.py services/settingsd/settingsd.py \
           services/notifyd/notifyd.py compositor/hyprland/hyprglass-sync.sh \
           compositor/hyprland/apply-preferences.sh compositor/hyprland/tile.py icons/icon-resolver.py \
           compositor/hyprland/idle.py apps/setup/pacman-config.sh; do
    install -Dm755 "$REPO/$f" "$D$LIB/${f##*/}"
  done
  install -Dm644 "$REPO/apps/setup/account_rules.py" "$D$LIB/account_rules.py"
  install -Dm644 "$REPO/apps/setup/save-preferences.py" "$D$LIB/save-preferences.py"

  wrappers
  install -Dm755 "$REPO/distro/archiso/overlay/usr/local/bin/gg-session" "$D/usr/bin/gg-session"
  install -Dm755 "$REPO/compositor/hyprland/session-start.sh" "$D/usr/bin/gg-session-start"
  install -Dm755 "$REPO/compositor/hyprland/lock.sh" "$D/usr/bin/gg-lock"

  # The session's services: systemd user units (CitronPods' setup runs at each
  # login, a quick no-op once done) and D-Bus activation.
  for f in "$REPO"/distro/systemd/user/citronos-* "$REPO"/apps/citronpods/citronpods-{daemon,engine-bootstrap}.service \
           "$REPO"/apps/citronpods/citronpods-engine-bootstrap.path; do
    install -Dm644 "$f" "$D/usr/lib/systemd/user/${f##*/}"
  done
  install -d "$D/usr/lib/systemd/user/default.target.wants"
  ln -s ../citronpods-engine-bootstrap.service "$D/usr/lib/systemd/user/default.target.wants/"
  ln -s ../citronpods-engine-bootstrap.path "$D/usr/lib/systemd/user/default.target.wants/"
  for f in "$REPO"/distro/dbus/*.service; do
    sed 's#@BIN@#/usr/bin#' "$f" | install -Dm644 /dev/stdin "$D/usr/share/dbus-1/services/${f##*/}"
  done

  for f in "$REPO"/apps/desktop/*.desktop; do
    sed "s#@APPS@#$APPS#g" "$f" | install -Dm644 /dev/stdin "$D/usr/share/applications/${f##*/}"
  done
  printf '[Desktop Entry]\nName=CitronOS\nComment=CitronOS desktop\nExec=gg-session\nType=Application\nDesktopNames=Hyprland\n' |
    install -Dm644 /dev/stdin "$D/usr/share/wayland-sessions/golden-gate.desktop"

  # Administration with your password, Touch ID's PAM service and its polkit action.
  install -d -m750 "$D/etc/sudoers.d"     # as the filesystem package has it
  printf '%%wheel ALL=(ALL:ALL) ALL\n' | install -m440 /dev/stdin "$D/etc/sudoers.d/20-golden-wheel"
  install -Dm644 "$REPO/distro/pam/gg-touchid" "$D/etc/pam.d/gg-touchid"
  install -Dm644 "$REPO/distro/polkit/org.goldengate.touchid.policy" \
    "$D/usr/share/polkit-1/actions/org.goldengate.touchid.policy"
  install -Dm644 "$REPO/third_party/hyprglass/LICENSE" "$D/usr/share/licenses/citronos-runtime/hyprglass/LICENSE"

  # What the system calls itself, put back whenever pacman installs or
  # upgrades the files it replaces; pacman.conf ready for installing software.
  identity
  # (Each also when its own source changes: a new version's os-release.)
  hook citronos-release "usr/lib/os-release ${SHARE#/}/os-release" "Naming the system CitronOS..." \
    "/usr/bin/install -m644 $SHARE/os-release /usr/lib/os-release"
  hook citronos-pacman "etc/pacman.conf ${LIB#/}/pacman-config.sh" "Setting up the package repositories for CitronOS..." \
    "/bin/sh $LIB/pacman-config.sh"
}

identity() {
  rel() { sed -n "s/.*property string $1: \"\(.*\)\".*/\1/p" "$REPO/apps/lib/theme/Release.qml"; }
  local name release version
  name=$(rel name); release=$(rel release); version=$(rel version)
  install -Dm644 /dev/stdin "$D$SHARE/os-release" <<EOF
NAME="$name"
PRETTY_NAME="$name $release $version"
ID=citronos
ID_LIKE=arch
VERSION="$version ($release)"
VERSION_ID=$version
VERSION_CODENAME=$(printf %s "${release,,}" | tr -c "a-z0-9\n" -)
BUILD_ID=$(date -u --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)
ANSI_COLOR="38;2;255;204;0"
HOME_URL="https://github.com/mobilaunch/goldenapple"
LOGO=archlinux-logo
EOF
}

hook() { # hook NAME "TARGET…" DESCRIPTION EXEC
  local t targets=""
  for t in $2; do targets+="Target = $t"$'\n'; done
  install -Dm644 /dev/stdin "$D/usr/share/libalpm/hooks/$1.hook" <<EOF
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
${targets}
[Action]
Description = $3
When = PostTransaction
Exec = $4
EOF
}

shell() {
  local S="$D/etc/xdg/quickshell/golden-gate"
  install -d "${S%/*}"
  cp -a "$REPO/shell" "$S"
  find "$S" -name __pycache__ -type d -prune -exec rm -rf {} +
  # One shared UI, so the shell and every control resolve one Theme singleton.
  rm -rf "$S/ui"
  ln -s "$SHARE/ui" "$S/ui"
  local_symbols "$S/assets/symbols"
}

hyprland_config() {
  sed -e "s#__GG_WALLPAPER__#$WALLPAPER#" -e "s#__GG_APPS__#$APPS#g" \
      -e "s#~/.config/hypr/golden-gate/motion.conf#$HYPR/motion.conf#" \
      -e "s#~/.config/hypr/golden-gate/report-config-errors.sh#$HYPR/report-config-errors.sh#" \
      "$REPO/compositor/hyprland/hyprland.conf" | install -Dm644 /dev/stdin "$D$HYPR/hyprland.conf"
  install -Dm644 "$REPO/design/dist/hyprland-motion.conf" "$D$HYPR/motion.conf"
  install -Dm755 "$REPO/compositor/hyprland/report-config-errors.sh" "$D$HYPR/report-config-errors.sh"
  install -Dm755 "$REPO/compositor/hyprland/machine-conf.sh" "$D$HYPR/machine-conf.sh"
  # A new account's own files: the stub that sources the desktop's settings,
  # and hypridle's, which gg-idle rewrites from Settings. The rest of
  # ~/.config/hypr/golden-gate (what Settings writes) gg-session makes.
  install -Dm644 /dev/stdin "$D/etc/skel/.config/hypr/hyprland.conf" <<EOF
# CitronOS's desktop settings come from the citronos-hyprland-config package
# ($HYPR/hyprland.conf); updates never change this file.
# Settings writes to ~/.config/hypr/golden-gate. Your own lines go below.
source = $HYPR/hyprland.conf
EOF
  install -Dm644 "$REPO/compositor/hyprland/hypridle.conf" "$D/etc/skel/.config/hypr/hypridle.conf"
}

theme() {
  install -d "$D/usr/share/icons"
  cp -a "$REPO/icons/GoldenGate" "$D/usr/share/icons/GoldenGate"
  local BG="$D/usr/share/backgrounds/golden-gate" svg photo
  install -d "$BG"
  for svg in "$REPO"/prototype/assets/wallpapers/*.svg; do
    install -m644 "$svg" "$BG/"
    rsvg-convert -w 3840 -h 2400 -o "$BG/$(basename "$svg" .svg).png" "$svg"
  done
  for photo in "$REPO"/themes/wallpapers/*.jpg; do install -m644 "$photo" "$BG/"; done

  # GTK's look and the terminal's are each account's own files: a new
  # account starts with CitronOS's.
  install -Dm644 "$REPO/design/dist/gtk.css" "$D/etc/skel/.config/gtk-4.0/gtk.css"
  install -Dm644 "$REPO/design/dist/gtk3.css" "$D/etc/skel/.config/gtk-3.0/gtk.css"
  install -Dm644 "$REPO/themes/ghostty/config" "$D/etc/skel/.config/ghostty/config"
  local t
  for t in "$REPO"/themes/ghostty/themes/*; do install -Dm644 "$t" "$D/etc/skel/.config/ghostty/themes/${t##*/}"; done
  # System-wide: SF Pro → Inter, GNOME's fonts and icons, the default apps.
  install -Dm644 "$REPO/themes/fontconfig/60-golden-gate.conf" "$D/usr/share/fontconfig/conf.avail/60-golden-gate.conf"
  install -d "$D/etc/fonts/conf.d"
  ln -s /usr/share/fontconfig/conf.avail/60-golden-gate.conf "$D/etc/fonts/conf.d/60-golden-gate.conf"
  install -Dm644 "$REPO/themes/gsettings/90_golden-gate.gschema.override" "$D/usr/share/glib-2.0/schemas/90_golden-gate.gschema.override"
  mimeapps | install -Dm644 /dev/stdin "$D/etc/xdg/mimeapps.list"

  install -Dm644 "$REPO/themes/keyd/default.conf" "$D/etc/keyd/default.conf"
  install -Dm644 "$REPO/themes/keyd/app.conf" "$D/etc/keyd/app.conf"

  # The login screen: laid out like the shell, with its own copy of the shared
  # UI (the greeter may start before anything else is mounted).
  local T="$D/usr/share/sddm/themes/golden-gate" shared
  install -d "$T/components"
  cp -a "$REPO"/themes/sddm/golden-gate/. "$T/"
  cp -a "$REPO/apps/lib" "$T/ui"
  local_symbols "$T/assets/symbols"
  find "$T" -name __pycache__ -type d -prune -exec rm -rf {} +
  for shared in Glass.qml TextField.qml Symbol.qml Spring.qml SpringValue.qml LockSurface.qml SystemClockProxy.qml; do
    install -m644 "$REPO/shell/components/$shared" "$T/components/$shared"
  done
  printf '[Theme]\nCurrent=golden-gate\n\n[General]\nDisplayServer=wayland\n\n[Wayland]\nCompositorCommand=weston --shell=kiosk --idle-time=0\n' |
    install -Dm644 /dev/stdin "$D/etc/sddm.conf.d/golden-gate.conf"

  local P="$D/usr/share/plymouth/themes/golden-gate" k sfx
  install -d "$P"
  cp -a "$REPO"/themes/plymouth/golden-gate/. "$P/"
  for k in 1 2; do
    sfx=""; [[ $k == 2 ]] && sfx="@2x"
    rsvg-convert -w $((92 * k)) -h $((92 * k)) -o "$P/logo$sfx.png" "$REPO/shell/assets/symbols/logo.svg"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="%d" height="%d" rx="%d" fill="#fff" fill-opacity=".22"/></svg>' \
      $((180 * k)) $((5 * k)) $((180 * k)) $((5 * k)) $((3 * k)) | rsvg-convert -o "$P/track$sfx.png"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="%d" height="%d" rx="%d" fill="#fff"/></svg>' \
      $((180 * k)) $((5 * k)) $((180 * k)) $((5 * k)) $((3 * k)) | rsvg-convert -o "$P/fill$sfx.png"
    printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect x=".5" y=".5" width="%d" height="%d" rx="%d" fill="#fff" fill-opacity=".14" stroke="#fff" stroke-opacity=".45"/></svg>' \
      $((220 * k)) $((34 * k)) $((220 * k - 1)) $((34 * k - 1)) $((17 * k)) | rsvg-convert -o "$P/field$sfx.png"
  done
}

mimeapps() {
  local web=org.goldengate.Web.desktop files=org.goldengate.Files.desktop archive=org.goldengate.ArchiveUtility.desktop
  local text=org.goldengate.TextEdit.desktop photos=org.goldengate.Photos.desktop music=org.goldengate.Music.desktop t
  echo "[Default Applications]"
  for t in x-scheme-handler/http x-scheme-handler/https text/html; do echo "$t=$web"; done
  echo "inode/directory=$files"
  for t in application/zip application/x-zip-compressed application/x-tar application/gzip \
           application/x-compressed-tar application/x-xz-compressed-tar; do echo "$t=$archive"; done
  for t in text/plain text/markdown application/json; do echo "$t=$text"; done
  for t in image/jpeg image/png image/webp image/gif image/tiff video/mp4 video/quicktime video/webm; do echo "$t=$photos"; done
  for t in audio/mpeg audio/mp4 audio/flac audio/ogg audio/opus audio/x-wav; do echo "$t=$music"; done
}

case $PART in
  runtime) runtime ;;
  shell) shell ;;
  hyprland-config) hyprland_config ;;
  theme) theme ;;
  *) echo "stage.sh: no part called $PART (runtime, shell, hyprland-config, theme)" >&2; exit 2 ;;
esac
