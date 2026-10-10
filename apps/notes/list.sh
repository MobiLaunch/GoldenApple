#!/usr/bin/env bash
# CitronOS Notes: lists the notes under ROOT for the app.
#   list.sh ROOT
# Folders (one level of subfolders of ROOT) print as
#   F <tab> name <tab> path
# and notes (*.md) as
#   N <tab> folder <tab> path <tab> mtime <tab> title <tab> preview
# where title is the first non-empty line without Markdown marks, and preview
# the start of the rest.
set -u
root=${1:?usage: list.sh ROOT}
mkdir -p "$root/Notes"
shopt -s nullglob
for d in "$root"/*/; do
  d=${d%/}
  name=${d##*/}
  printf 'F\t%s\t%s\n' "$name" "$d"
  for f in "$d"/*.md; do
    mtime=$(stat -c %Y "$f")
    awk -v folder="$name" -v path="$f" -v mtime="$mtime" '
      function clean(s) {
        gsub(/\t/, " ", s); gsub(/^[#>*+ -]+/, "", s); gsub(/^\[[ xX]\] /, "", s)
        gsub(/\*\*|__|~~|`/, "", s); gsub(/\]\([^)]*\)/, "", s); gsub(/\[/, "", s); gsub(/\\/, "", s)
        return s
      }
      NF && title == "" { title = clean($0); next }
      NF && title != "" && length(preview) < 140 { preview = preview (preview == "" ? "" : " ") clean($0) }
      END { printf "N\t%s\t%s\t%s\t%s\t%s\n", folder, path, mtime, title, substr(preview, 1, 140) }
    ' "$f"
  done
done
