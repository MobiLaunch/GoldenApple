#!/usr/bin/env bash
# Build the Golden Gate live ISO.
#
# Requirements: an Arch Linux host (or the archlinux container, see
# .github/workflows/iso.yml), root, and: pacman -S archiso librsvg nodejs
#
#   sudo distro/archiso/build.sh            → out/golden-gate-YYYY.MM.DD-x86_64.iso
#   sudo GG_BUILD_AUR=1 distro/archiso/build.sh
#                                           also builds packages.extra entries that
#                                           exist only in the AUR (CI does this)
#
# Starts from archiso's `releng` profile and layers the Golden Gate desktop on top,
# so bootloader and hardware support stay in sync with upstream Arch.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="${WORK:-$REPO/distro/work}"
OUT="${OUT:-$REPO/out}"
PROFILE="$WORK/profile"
say() { printf '\033[1;33m›\033[0m %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "build.sh must run as root (mkarchiso needs it)"; exit 1; }
for tool in mkarchiso rsvg-convert curl sha256sum; do
  command -v "$tool" >/dev/null || { echo "missing $tool: pacman -S archiso librsvg curl coreutils"; exit 1; }
done

say "profile: releng + golden-gate"
rm -rf "$PROFILE"
mkdir -p "$WORK"
cp -r /usr/share/archiso/configs/releng "$PROFILE"
AIR="$PROFILE/airootfs"

# ---------------------------------------------------------------- identity
sed -i \
  -e 's/^iso_name=.*/iso_name="golden-gate"/' \
  -e 's/^iso_label=.*/iso_label="GOLDENGATE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
  -e 's/^iso_publisher=.*/iso_publisher="Golden Gate <https:\/\/github.com\/mobilaunch\/goldenapple>"/' \
  -e 's/^iso_application=.*/iso_application="Golden Gate Live"/' \
  "$PROFILE/profiledef.sh"
cat >> "$PROFILE/profiledef.sh" <<'EOF'
file_permissions+=(
  ["/usr/local/bin/gg-session"]="0:0:755"
  ["/usr/local/bin/gnome-control-center"]="0:0:755"
  ["/usr/local/bin/gnome-calculator"]="0:0:755"
  ["/usr/local/bin/gg-diagnostics"]="0:0:755"
  ["/usr/local/bin/gg-settings"]="0:0:755"
  ["/usr/local/bin/gg-web"]="0:0:755"
  ["/usr/local/bin/gg-install"]="0:0:755"
  ["/usr/local/bin/gg-firefox-recover"]="0:0:755"
  ["/usr/lib/golden-gate/account-helper.py"]="0:0:755"
  ["/usr/lib/golden-gate/hyprglass.so"]="0:0:755"
  ["/etc/sudoers.d/20-golden-wheel"]="0:0:440"
  ["/etc/sudoers.d/10-golden-live"]="0:0:440"
  ["/home/golden"]="1000:1000:750"
)
EOF

# Builds AUR packages into distro/localrepo/ as an unprivileged user (makepkg
# refuses to run as root). AUR-only dependencies of these packages are not resolved.
build_aur() {
  say "building from the AUR: $*"
  pacman -S --needed --noconfirm base-devel git sudo >/dev/null
  id gg-builder &>/dev/null || useradd -m gg-builder
  echo 'gg-builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/gg-builder
  local src pkg f built
  src="$(mktemp -d)"
  chown gg-builder: "$src"
  mkdir -p "$REPO/distro/localrepo"
  for pkg in "$@"; do
    sudo -u gg-builder git clone -q "https://aur.archlinux.org/$pkg.git" "$src/$pkg"
    # The AUR hands out an empty repository for names it doesn't know.
    [[ -f $src/$pkg/PKGBUILD ]] || { echo "$pkg is not in the AUR either"; exit 1; }
    (cd "$src/$pkg" && sudo -u gg-builder makepkg --syncdeps --noconfirm --needed)
    built=0
    for f in "$src/$pkg"/*.pkg.tar.zst; do
      [[ -e $f && $f != *-debug-* ]] || continue
      cp "$f" "$REPO/distro/localrepo/"
      built=1
    done
    ((built)) || { echo "makepkg produced no package for $pkg"; exit 1; }
  done
}

# ---------------------------------------------------------------- packages
cat "$HERE/packages.x86_64" >> "$PROFILE/packages.x86_64"
missing=()
while read -r pkg; do
  [[ -z $pkg || $pkg == \#* ]] && continue
  if pacman -Si "$pkg" >/dev/null 2>&1; then echo "$pkg" >> "$PROFILE/packages.x86_64"; else missing+=("$pkg"); fi
done < "$HERE/packages.extra"
if ((${#missing[@]})); then
  if [[ ${GG_BUILD_AUR:-0} == 1 ]]; then build_aur "${missing[@]}"; fi
  if compgen -G "$REPO/distro/localrepo/*.pkg.tar.zst" >/dev/null; then
    say "local repo for: ${missing[*]}"
    repo-add -q "$REPO/distro/localrepo/golden-gate-local.db.tar.gz" "$REPO"/distro/localrepo/*.pkg.tar.zst
    printf '\n[golden-gate-local]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO/distro/localrepo" >> "$PROFILE/pacman.conf"
    printf '%s\n' "${missing[@]}" >> "$PROFILE/packages.x86_64"
  else
    echo "Not in the sync repos: ${missing[*]}"
    echo "Build them (e.g. from the AUR with makepkg) into distro/localrepo/ and re-run."
    exit 1
  fi
fi

# ---------------------------------------------------------------- HyprGlass
# Pin the prebuilt plugin to the Hyprland ABI shipped by this image. The release
# is explicitly built for Hyprland 0.56.2; fail rather than creating an ISO with
# a silently incompatible compositor plugin after Arch updates Hyprland.
HYPRGLASS_VERSION="v0.8.1"
HYPRGLASS_SHA256="1db3ccb154e7a7f04954602c1a9a643fd680e724491fe6be7ccc88e166162233"
HYPRLAND_VERSION="$(pacman -Si hyprland 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}')"
case "$HYPRLAND_VERSION" in
  0.56.2-*) ;;
  *) echo "HyprGlass $HYPRGLASS_VERSION is pinned for Hyprland 0.56.2, but repositories provide $HYPRLAND_VERSION"; exit 1 ;;
esac
say "HyprGlass $HYPRGLASS_VERSION for Hyprland $HYPRLAND_VERSION"
mkdir -p "$AIR/usr/lib/golden-gate"
curl -fL --retry 3 --retry-delay 2   "https://github.com/hyprnux/hyprglass/releases/download/$HYPRGLASS_VERSION/hyprglass.so"   -o "$AIR/usr/lib/golden-gate/hyprglass.so"
printf '%s  %s\n' "$HYPRGLASS_SHA256" "$AIR/usr/lib/golden-gate/hyprglass.so" | sha256sum -c -
chmod 755 "$AIR/usr/lib/golden-gate/hyprglass.so"

# ---------------------------------------------------------------- live user + session
cp -a "$HERE/overlay/." "$AIR/"
grep -q '^golden:' "$AIR/etc/passwd"  || echo 'golden:x:1000:1000:Golden Gate:/home/golden:/bin/bash' >> "$AIR/etc/passwd"
grep -q '^golden:' "$AIR/etc/shadow"  || echo 'golden::14871::::::' >> "$AIR/etc/shadow"
grep -q '^golden:' "$AIR/etc/group"   || echo 'golden:x:1000:' >> "$AIR/etc/group"
grep -q '^golden:' "$AIR/etc/gshadow" || echo 'golden:!::' >> "$AIR/etc/gshadow"

# NetworkManager (with iwd as its Wi-Fi backend) replaces systemd-networkd, because
# Control Center drives networking through nmcli.
WANTS="$AIR/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"
rm -f "$WANTS/systemd-networkd.service" "$AIR/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$WANTS/NetworkManager.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$WANTS/bluetooth.service"
ln -sf /usr/lib/systemd/system/keyd.service "$WANTS/keyd.service"
# A Secret Service for apps that keep passwords (Fractal, Geary, Web).
mkdir -p "$AIR/etc/systemd/user/sockets.target.wants"
ln -sf /usr/lib/systemd/user/gnome-keyring-daemon.socket "$AIR/etc/systemd/user/sockets.target.wants/gnome-keyring-daemon.socket"
# mkarchiso drops file ownership, so the live user's home is handed over at boot.
ln -sf /etc/systemd/system/gg-live-home.service "$WANTS/gg-live-home.service"

# ---------------------------------------------------------------- desktop
say "installing the Golden Gate desktop into the image"
bash "$REPO/scripts/install.sh" --system "$AIR"
mkdir -p "$AIR/home/golden"
cp -a "$AIR/etc/skel/." "$AIR/home/golden/"
cat > "$AIR/home/golden/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc
# Autologin lands on tty1; go straight to the desktop. gg-session returns to this
# shell if the compositor can't start, instead of looping through autologin.
if [[ -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then gg-session; fi
EOF
# New local accounts inherit the desktop start too (useradd copies /etc/skel).
cp "$AIR/home/golden/.bash_profile" "$AIR/etc/skel/.bash_profile"
# The live user has no password, so there is nothing for an idle lock to protect.
# Drop the listener that locks and the lock-before-sleep line; keep the rest.
awk '
  /^listener *\{/ { block = $0 "\n"; inblock = 1; next }
  inblock { block = block $0 "\n"; if (/^\}/) { if (block !~ /lock-session/) printf "%s", block; inblock = 0 } next }
  /before_sleep_cmd/ { next }
  { print }
' "$AIR/home/golden/.config/hypr/hypridle.conf" > "$WORK/hypridle.conf"
mv "$WORK/hypridle.conf" "$AIR/home/golden/.config/hypr/hypridle.conf"

# ---------------------------------------------------------------- build
say "mkarchiso"
# Validate the releng boot template before mkarchiso expands %INSTALL_DIR% and
# %ARCHISO_UUID%. Current ArchISO generates the systemd-boot UEFI entry during
# the build, so requiring the final expanded arguments here is incorrect.
if ! grep -qs '^install_dir="arch"' "$PROFILE/profiledef.sh"; then
  echo "generated profile has an unexpected ArchISO install_dir"
  exit 1
fi
if ! grep -qs "uefi.systemd-boot" "$PROFILE/profiledef.sh"; then
  echo "generated profile has no systemd-boot UEFI boot mode"
  exit 1
fi
if ! grep -RqsF 'archisobasedir=%INSTALL_DIR%' "$PROFILE/syslinux" "$PROFILE/grub" 2>/dev/null; then
  echo "generated profile has no ArchISO base-directory discovery template"
  exit 1
fi
if ! grep -RqsF 'archisosearchuuid=%ARCHISO_UUID%' "$PROFILE/syslinux" "$PROFILE/grub" 2>/dev/null; then
  echo "generated profile has no ArchISO media-discovery template"
  exit 1
fi
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"
say "done: $(ls -1 "$OUT"/*.iso | tail -1)"

