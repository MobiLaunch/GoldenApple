#!/bin/bash
# Mac app support: installs Darling (darlinghq.org), the macOS translation
# layer. The App Store opens this in a Terminal window, since it downloads
# about 120 MB and asks for your password.
#
# It installs darling-bin from the AUR: Darling's own prebuilt release,
# repackaged, which needs only packages from Arch's main repositories. The
# source builds don't install on a normal system: darling-git needs an
# AUR-only build helper (makepkg-git-lfs-proto) and 32-bit compilers from
# [multilib]; the old "darling" package needs libavresample, which Arch
# dropped years ago. Those missing dependencies were why every attempt
# (here, and the commands on Darling's site) ended in "target not found".
#
# Before that it gets pacman into a state where installing works: current
# package signing keys, an up-to-date package database (installing against
# an old one fails with 404s and signature errors), no stale lock.
#
#   GG_DARLING_DRY_RUN=1   print the commands instead of running them (tests)
set -euo pipefail
bold=$'\e[1m'; dim=$'\e[2m'; red=$'\e[31m'; off=$'\e[0m'
# Everything also goes to a log, so a failure can be read (and sent) later.
log="${XDG_CACHE_HOME:-$HOME/.cache}/golden-gate/darling-setup.log"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1

AUR_PKG=darling-bin
AUR_URL="https://aur.archlinux.org/$AUR_PKG.git"
# GitHub's mirror of the AUR, for when aur.archlinux.org is down or blocked.
AUR_MIRROR="https://github.com/archlinux/aur.git"

run() { if [[ ${GG_DARLING_DRY_RUN:-0} == 1 ]]; then echo "+ $*"; else "$@"; fi; }
step() { printf '\n%s\n' "${bold}$*${off}"; }
finish() {
  echo
  read -rp "Press Return to close. " _ || true
  exit "${1:-0}"
}
fail() {
  printf '\n%s\n' "${red}${bold}$1${off}"
  [[ -n ${2:-} ]] && printf '%s\n' "$2"
  printf '%s\n' "${dim}Everything above is also in $log${off}"
  finish 1
}

printf '%s\n\n' "${bold}CitronOS · Mac app support${off}"
if command -v darling >/dev/null 2>&1; then
  echo "Darling is already installed. Mac apps from the App Store open with it."
  finish 0
fi

# The live USB keeps changes in a small RAM disk: Darling won't fit, and it
# would be gone at the next restart anyway.
if [[ -d /run/archiso && ${GG_DARLING_DRY_RUN:-0} != 1 ]]; then
  fail "Mac app support can't be set up on the live USB." \
       "Install CitronOS on this computer first (Install CitronOS in Launchpad), then set it up from the App Store."
fi
free_mb=$(df -Pm / | awk 'NR==2 {print $4}')
if (( free_mb < 2048 )); then
  fail "There isn't enough free space." "Setting up Mac app support needs about 2 GB free on the system disk; there's ${free_mb} MB."
fi

cat <<TEXT
This installs Darling, the macOS translation layer:
  • a download of about 120 MB, and about 1.5 GB of space once installed
  • your password, to install it and the tools that set it up

${dim}Darling runs Mac command-line programs well. Its support for Mac apps with
windows is still experimental: many of them won't open yet.${off}

TEXT
read -rp "Install Darling now? [Y/n] " answer || answer=n
case "$answer" in n*|N*) exit 0 ;; esac

# Ask for the password once, up front.
run sudo -v || fail "Mac app support needs an administrator's password."

step "Getting the package manager ready…"
if [[ -e /var/lib/pacman/db.lck ]]; then
  if pgrep -x pacman >/dev/null; then
    fail "Another app is installing software right now." "Try again when it finishes."
  fi
  # Left by an install that was interrupted.
  run sudo rm -f /var/lib/pacman/db.lck
fi
# The keys that sign today's packages are newer than the ones this computer
# was installed with. Refresh them first, as Arch advises; if pacman still
# can't verify anything, rebuild the keyring from scratch and try again.
if ! run sudo pacman -Sy --needed --noconfirm archlinux-keyring; then
  echo "${dim}Repairing the package signing keys…${off}"
  run sudo pacman-key --init
  run sudo pacman-key --populate archlinux
  run sudo pacman -Sy --needed --noconfirm archlinux-keyring \
    || fail "The package signing keys couldn't be updated." "Check the internet connection and try again."
fi
# Installing new packages against an old package database is what makes
# pacman fail with "404" and signature errors: bring the system up to date.
step "Updating the system (so new packages match it)…"
run sudo pacman -Su --noconfirm \
  || fail "The system couldn't be updated." "The lines above say why. Software Update in Settings can usually fix this; then try again."
run sudo pacman -S --needed --noconfirm base-devel git \
  || fail "The tools that set up Darling couldn't be installed."

step "Downloading Darling…"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
if ! run git clone --depth 1 "$AUR_URL" "$AUR_PKG" 2>/dev/null; then
  echo "${dim}The AUR didn't answer; using its mirror on GitHub.${off}"
  run git clone --depth 1 --single-branch --branch "$AUR_PKG" "$AUR_MIRROR" "$AUR_PKG" \
    || fail "Darling's package couldn't be downloaded." "Check the internet connection and try again."
fi
if [[ ${GG_DARLING_DRY_RUN:-0} != 1 && ! -f $AUR_PKG/PKGBUILD ]]; then
  fail "Darling's package came back empty." "Try again in a few minutes."
fi

step "Installing Darling…"
cd "$AUR_PKG"
# --syncdeps installs its dependencies from Arch's repositories; all of them
# are there (no [multilib], no other AUR packages).
run makepkg --syncdeps --install --needed --noconfirm \
  || fail "Darling couldn't be installed." "The lines above say why."

step "Setting up the Mac environment (the first start takes a minute)…"
run darling shell true || echo "${dim}Darling will finish setting up the first time a Mac app opens.${off}"
printf '\n%s\n' "${bold}Mac app support is ready.${off} Open Mac apps from Launchpad or the App Store."
finish 0
