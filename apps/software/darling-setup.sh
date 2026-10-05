#!/bin/bash
# Mac app support: builds and installs Darling (darlinghq.org), the macOS
# translation layer, from the Arch User Repository. The App Store opens this in
# a Terminal window, since it takes a while and asks for your password.
set -euo pipefail
bold=$'\e[1m'; dim=$'\e[2m'; off=$'\e[0m'
# Everything also goes to a log, so a failed build can be read (and sent) later.
log="${XDG_CACHE_HOME:-$HOME/.cache}/golden-gate/darling-setup.log"
mkdir -p "$(dirname "$log")"
exec > >(tee "$log") 2>&1
printf '%s\n\n' "${bold}CitronOS · Mac app support${off}"
if command -v darling >/dev/null 2>&1; then
  echo "Darling is already installed. Mac apps from the App Store open with it."
  read -rp "Press Return to close. " _
  exit 0
fi
cat <<TEXT
This builds Darling, the macOS translation layer, from source:
  • about 30–90 minutes, depending on your computer
  • about 10 GB of free space while it builds (much less afterwards)
  • your password, to install the build tools and Darling itself

${dim}Darling runs Mac command-line programs well. Its support for Mac apps with
windows is still experimental: many of them won't open yet.${off}

TEXT
read -rp "Build and install Darling now? [Y/n] " answer
case "$answer" in n*|N*) exit 0 ;; esac

sudo pacman -S --needed --noconfirm base-devel git
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
# The development package tracks Darling's current source; the stable one is
# the fallback while the former doesn't build.
for pkg in darling-git darling; do
  if git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$pkg" && [ -f "$pkg/PKGBUILD" ]; then
    if (cd "$pkg" && makepkg -si --noconfirm); then
      built=1
      break
    fi
    echo "${bold}$pkg didn't build; trying the next one.${off}"
  fi
done
if [ -z "${built:-}" ]; then
  echo "${bold}Darling couldn't be built.${off} The output above says why; it's also in"
  echo "  $log"
  read -rp "Press Return to close. " _
  exit 1
fi
echo "Setting up the Mac environment (the first start takes a minute)…"
darling shell true || true
printf '\n%s\n' "${bold}Mac app support is ready.${off} Open Mac apps from Launchpad or the App Store."
read -rp "Press Return to close. " _
