#!/usr/bin/env bash
# Disable only Golden Gate-owned injections, retaining a timestamped backup.
# --system FIREFOX_DIR is used by the installer; --profiles never needs root.
set -euo pipefail
stamp=$(date +%Y%m%d-%H%M%S)-$$
backup_owned() {
  local file=$1 marker=$2
  if [[ -f $file ]] && grep -qF "$marker" "$file"; then
    mv -- "$file" "$file.disabled-$stamp"
    printf 'Disabled Golden Gate styling: %s\n' "$file"
  fi
}
case "${1:---profiles}" in
  --system)
    base=${2:?Firefox installation directory required}
    backup_owned "$base/defaults/pref/autoconfig.js" 'Golden Gate: load golden-gate.cfg'
    ;;
  --profiles)
    base="$HOME/.mozilla/firefox"
    [[ -d $base ]] || exit 0
    for profile in "$base"/*/; do
      [[ -d $profile ]] || continue
      backup_owned "$profile/chrome/userChrome.css" 'Golden Gate'
    done
    ;;
  *) printf 'usage: recover.sh --profiles | --system FIREFOX_DIR\n' >&2; exit 2 ;;
esac
