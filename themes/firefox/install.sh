#!/bin/bash
# Installs the Safari look for Firefox into a Firefox directory:
#   themes/firefox/install.sh /usr/lib/firefox
# (autoconfig, the stylesheet and policies; every profile picks them up).
# Without write access there, `--profiles` instead puts the stylesheet in each
# of your Firefox profiles as userChrome.css, with the prefs in user.js.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ${1:-} == --profiles ]]; then
  base="$HOME/.mozilla/firefox"
  [[ -d $base ]] || { echo "no Firefox profiles yet; run Firefox once, then this again"; exit 0; }
  for p in "$base"/*/; do
    [[ -f $p/prefs.js ]] || continue
    mkdir -p "$p/chrome"
    # userChrome.css applies to the browser window only: drop the document wrapper.
    sed -e '/^@-moz-document/d' -e '$ d' "$HERE/golden-gate.css" > "$p/chrome/userChrome.css"
    grep '^defaultPref' "$HERE/golden-gate.cfg" | sed 's/^defaultPref/user_pref/' > "$p/user.js"
  done
  exit 0
fi
FF="${1:?usage: install.sh FIREFOX_DIR | --profiles}"
install -Dm644 "$HERE/autoconfig.js" "$FF/defaults/pref/autoconfig.js"
install -Dm644 "$HERE/golden-gate.cfg" "$FF/golden-gate.cfg"
install -Dm644 "$HERE/golden-gate.css" "$FF/golden-gate/golden-gate.css"
install -Dm644 "$HERE/policies.json" "$FF/distribution/policies.json"
