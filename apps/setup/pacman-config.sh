#!/bin/sh
# Keeps CitronOS's /etc/pacman.conf ready for installing software. Run by the
# citronos-pacman pacman hook whenever pacman.conf is installed or upgraded,
# and by system installs and updates (scripts/install.sh).
#   - [multilib] on: Arch's 32-bit libraries, which Darling's own build
#     instructions, Wine and Steam need ("target not found: lib32-…"
#     otherwise). Most Arch-based desktops ship with it on.
#   - no [golden-gate-local]: the image build's own package folder. It only
#     exists on the computer that built the ISO; left in, every
#     "pacman -Sy" fails to synchronize it, and so every install fails.
#   pacman-config.sh [ROOT]
set -eu
conf="${1:-}/etc/pacman.conf"
[ -f "$conf" ] || exit 0
tmp="$conf.citronos.$$"
awk '
  # Drop the build-only repository: its header and the lines under it.
  /^\[golden-gate-local\]/ { skip = 1; next }
  /^\[/ { skip = 0 }
  skip { next }
  # Uncomment the [multilib] section Arch ships commented out.
  /^#\[multilib\][[:space:]]*$/ { print "[multilib]"; multilib = 1; next }
  multilib && /^#Include = \/etc\/pacman\.d\/mirrorlist/ { print substr($0, 2); multilib = 0; next }
  { multilib = 0; print }
' "$conf" > "$tmp"
if cmp -s "$conf" "$tmp"; then
  rm -f "$tmp"
else
  chmod 644 "$tmp"
  mv "$tmp" "$conf"
fi
