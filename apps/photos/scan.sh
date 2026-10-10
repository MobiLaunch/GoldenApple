#!/usr/bin/env bash
# CitronOS Photos: lists the photos and videos in the given folders.
#   scan.sh CACHE_DIR DIR...
# Prints one line per item, oldest first:
#   path <tab> mtime <tab> kind (image|video) <tab> seconds <tab> thumbnail
# Videos get a poster frame (and their length) from ffmpeg, cached in
# CACHE_DIR/thumbs; images are thumbnailed by the app as it draws them.
set -u
cache=${1:?usage: scan.sh CACHE_DIR DIR...}; shift
mkdir -p "$cache/thumbs"
for dir in "$@"; do
  [[ -d $dir ]] || continue
  find -L "$dir" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \
       -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' -o -iname '*.heic' \
       -o -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' -o -iname '*.webm' -o -iname '*.mkv' \) \
       -not -path '*/.*' -printf '%T@\t%p\n' 2>/dev/null
done | sort -n | awk -F'\t' '!seen[$2]++' | while IFS=$'\t' read -r mtime path; do
  mtime=${mtime%.*}
  case "${path,,}" in
    *.mp4|*.mov|*.m4v|*.webm|*.mkv)
      key=$(printf '%s|%s' "$path" "$mtime" | md5sum | cut -c1-20)
      thumb="$cache/thumbs/$key.jpg"; meta="$cache/thumbs/$key.len"
      if [[ ! -s $thumb ]]; then
        ffmpeg -nostdin -v error -ss 0.5 -i "$path" -frames:v 1 -vf 'scale=480:-2' -q:v 4 "$thumb" -y 2>/dev/null \
          || ffmpeg -nostdin -v error -i "$path" -frames:v 1 -vf 'scale=480:-2' -q:v 4 "$thumb" -y 2>/dev/null || thumb=""
        d=$(ffmpeg -nostdin -hide_banner -i "$path" 2>&1 | grep -m1 -o 'Duration: [0-9:.]*' | cut -d' ' -f2)
        IFS=: read -r hh mm ss <<< "${d:-0:0:0}"
        echo $((10#${hh:-0} * 3600 + 10#${mm:-0} * 60 + 10#${ss%.*})) > "$meta"
      fi
      printf '%s\t%s\tvideo\t%s\t%s\n' "$path" "$mtime" "$(cat "$meta" 2>/dev/null || echo 0)" "$thumb" ;;
    *)
      printf '%s\t%s\timage\t0\t\n' "$path" "$mtime" ;;
  esac
done
