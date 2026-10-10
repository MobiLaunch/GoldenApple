#!/usr/bin/env bash
# Package this checkout as a CitronOS update bundle, for systems that update
# from a USB stick instead of GitHub:
#
#   scripts/make-update-bundle.sh [OUT.tar.gz] [VERSION.json]
#
# On the installed system (the bundle is one file, so any USB stick will do):
#   tar xzf golden-gate-update.tar.gz
#   sudo python3 golden-gate/apps/settings/golden_update.py install-local
#
# The bundle is the committed tree (git archive; uncommitted changes are left
# out) plus golden-gate-version.json: which repository, branch and commit it
# is, so Software Update knows where to look for the next update. The ISO
# build uses this for /usr/share/golden-gate/source.tar.gz (gg-update-disk).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(realpath -m "${1:-golden-gate-update.tar.gz}")"
VERSION_OUT="${2:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/golden-gate"

if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$REPO" archive --format=tar HEAD | tar -x -C "$work/golden-gate"
  origin="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
  repo="$(printf '%s' "$origin" | sed -nE 's#^(https://|git@)github\.com[:/]([^/]+/[^/]+)/?$#\2#p' | sed 's/\.git$//')"
  branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
  commit="$(git -C "$REPO" rev-parse HEAD)"
  date="$(git -C "$REPO" log -1 --format=%cI)"
  subject="$(git -C "$REPO" log -1 --format=%s)"
else
  tar -C "$REPO" --exclude=.git --exclude=node_modules --exclude=out --exclude=distro/work \
      --exclude=distro/localrepo -cf - . | tar -x -C "$work/golden-gate"
  repo="" branch="" commit="" date="" subject=""
fi
# A clone of a local copy (a Windows checkout, say) has no GitHub origin.
[[ -n $repo ]] || repo="MobiLaunch/GoldenApple"
[[ -n $branch && $branch != HEAD ]] || branch="claude/linux-macos-golden-gate-ui-pckc7s"

python3 - "$work/golden-gate/golden-gate-version.json" "$repo" "$branch" "$commit" "$date" "$subject" <<'PY'
import json, sys
out, repo, branch, commit, date, subject = sys.argv[1:7]
json.dump({"repo": repo, "branch": branch, "commit": commit, "date": date, "subject": subject},
          open(out, "w"), indent=2)
PY
mkdir -p "$(dirname "$OUT")"
[[ -z $VERSION_OUT ]] || { mkdir -p "$(dirname "$VERSION_OUT")"; cp "$work/golden-gate/golden-gate-version.json" "$VERSION_OUT"; }
tar -C "$work" -czf "$OUT" golden-gate
echo "› $OUT: CitronOS ${commit:0:7} ($repo, $branch)"
