#!/usr/bin/env bash
# Build the Golden Gate live ISO.
#
# Requirements: an Arch Linux host (or the archlinux container, see
# .github/workflows/iso.yml), root, and: pacman -S archiso librsvg nodejs
#
#   sudo distro/archiso/build.sh            → out/golden-gate-YYYY.MM.DD-x86_64.iso
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
for tool in mkarchiso rsvg-convert; do
  command -v "$tool" >/dev/null || { echo "missing $tool: pacman -S archiso librsvg"; exit 1; }
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
  ["/etc/sudoers.d/10-golden-live"]="0:0:440"
  ["/home/golden"]="1000:1000:750"
)
EOF

# ---------------------------------------------------------------- packages
cat "$HERE/packages.x86_64" >> "$PROFILE/packages.x86_64"
missing=()
while read -r pkg; do
  [[ -z $pkg || $pkg == \#* ]] && continue
  if pacman -Si "$pkg" >/dev/null 2>&1; then echo "$pkg" >> "$PROFILE/packages.x86_64"; else missing+=("$pkg"); fi
done < "$HERE/packages.extra"
if ((${#missing[@]})); then
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

# ---------------------------------------------------------------- desktop
say "installing the Golden Gate desktop into the image"
bash "$REPO/scripts/install.sh" --system "$AIR"
mkdir -p "$AIR/home/golden"
cp -a "$AIR/etc/skel/." "$AIR/home/golden/"
cat > "$AIR/home/golden/.bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && . ~/.bashrc
# Autologin lands on tty1; go straight to the desktop.
if [[ -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then exec gg-session; fi
EOF

# ---------------------------------------------------------------- build
say "mkarchiso"
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE"
say "done: $(ls -1 "$OUT"/*.iso | tail -1)"
