#!/usr/bin/env bash
# Builds hyprbars, the compositor-drawn title bar with traffic lights, for the
# Hyprland installed on this machine, with Golden Gate's changes
# (distro/hyprbars/patch.py: bars only for apps that leave their title bar to
# the compositor, such as Qt and Electron apps from the App Store).
#
#   build-hyprbars.sh OUT.so
#
# Needs git, make, g++ and pkg-config, and Hyprland's headers (the Arch
# hyprland package ships them). The plugin source is the hyprland-plugins
# commit that hyprpm pins for this Hyprland release. Exits non-zero, leaving
# OUT untouched, when anything is missing or doesn't build.
set -euo pipefail

OUT=${1:?usage: build-hyprbars.sh OUT.so}
HERE=$(cd "$(dirname "$0")/.." && pwd)
PATCHER=$HERE/distro/hyprbars/patch.py

for tool in git make g++ pkg-config python3; do
  command -v "$tool" >/dev/null || { echo "build-hyprbars: $tool is not installed" >&2; exit 2; }
done
pkg-config --exists hyprland || { echo "build-hyprbars: Hyprland's headers aren't installed" >&2; exit 2; }

# The release, e.g. 0.56.2 (from the package, or Hyprland itself).
VERSION=$(pacman -Q hyprland 2>/dev/null | awk '{print $2}' | cut -d- -f1)
[ -n "$VERSION" ] || VERSION=$(pkg-config --modversion hyprland)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q "$work/src"
cd "$work/src"
git remote add origin https://github.com/hyprwm/hyprland-plugins.git
git fetch -q --depth 1 origin main
# hyprpm.toml: ["<hyprland commit>", "<plugins commit>"], # <release>
PIN=$(git show FETCH_HEAD:hyprpm.toml | grep -E "#[[:space:]]*${VERSION//./\\.}[[:space:]]*$" | grep -oE '[0-9a-f]{40}' | tail -n 1 || true)
[ -n "$PIN" ] || { echo "build-hyprbars: no hyprland-plugins commit is pinned for Hyprland $VERSION" >&2; exit 3; }
git fetch -q --depth 1 origin "$PIN"
git checkout -q FETCH_HEAD

python3 "$PATCHER" hyprbars/main.cpp
make -C hyprbars -s >/dev/null
install -Dm755 hyprbars/hyprbars.so "$OUT"
printf '%s\n' "$VERSION" > "$OUT.hyprland"
echo "build-hyprbars: built for Hyprland $VERSION (hyprland-plugins $PIN) → $OUT"
