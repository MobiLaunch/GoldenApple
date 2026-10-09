#!/usr/bin/env bash
# Optional local SFWindows font installation. Never downloads or bundles Apple fonts.
# Usage: bash scripts/install-local-sfwindows.sh ~/Downloads/SFWindows
# Only run when your use of the locally obtained fonts is permitted by Apple's terms.
set -euo pipefail
if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "Usage: $0 PATH_TO_LOCALLY_OBTAINED_SFWINDOWS_DIRECTORY" >&2
  exit 2
fi
source_dir=$(realpath "$1")
target="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/golden-gate-sf"
mkdir -p "$target"
count=0
for section in "SF Pro" "SF Mono" "SF Compact" "New York"; do
  [[ -d "$source_dir/$section" ]] || continue
  while IFS= read -r -d '' face; do
    cp -f -- "$face" "$target/$(basename "$face")"
    count=$((count + 1))
  done < <(find "$source_dir/$section" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)
done
if (( count == 0 )); then
  echo "No SF Pro/SF Mono/SF Compact/OpenType or TrueType faces found." >&2
  exit 1
fi
if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$target" >/dev/null; fi
echo "Installed $count locally supplied faces into your user font directory."
echo "Log out and sign in for GTK/Qt to refresh their font cache."
echo "These proprietary fonts are not part of the Golden Gate distribution."
