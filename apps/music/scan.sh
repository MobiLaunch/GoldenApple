#!/usr/bin/env bash
# Golden Gate Music: scans a music folder into a tab-separated library file.
#
#   scan.sh MUSIC_DIR CACHE_DIR
#
# Writes CACHE_DIR/library.tsv, one line per track:
#   path mtime title artist album album-artist track year seconds artwork
# Files whose mtime hasn't changed are copied from the previous scan, so only
# new or edited files are read (with ffmpeg, which reads every tag format).
# Artwork is the folder's cover/folder/front image, or the embedded picture,
# extracted once per album to CACHE_DIR/art/.
set -u
dir=${1:?usage: scan.sh MUSIC_DIR CACHE_DIR}
cache=${2:?usage: scan.sh MUSIC_DIR CACHE_DIR}
mkdir -p "$cache/art"
out="$cache/library.tsv"
tmp="$cache/.library.tsv.$$"
err="$cache/.ffmpeg.$$"
trap 'rm -f "$tmp" "$err"' EXIT

declare -A prev
if [[ -f $out ]]; then
  while IFS= read -r line; do prev["${line%%$'\t'*}"]=$line; done < "$out"
fi
field() { local s=${1//$'\t'/ }; s=${s//$'\r'/}; printf '%s' "${s//\\/}"; }

: > "$tmp"
while IFS= read -r -d '' f; do
  mtime=$(stat -c %Y "$f")
  old=${prev[$f]-}
  if [[ -n $old ]]; then
    IFS=$'\t' read -r _ oldm _ <<< "$old"
    if [[ $oldm == "$mtime" ]]; then printf '%s\n' "$old" >> "$tmp"; continue; fi
  fi

  title="" artist="" album="" aartist="" track="" year=""
  while IFS='=' read -r k v; do
    case "${k,,}" in
      title) title=$v ;; artist) artist=$v ;; album) album=$v ;;
      album_artist|albumartist|"album artist") aartist=$v ;;
      track) track=${v%%/*} ;; date|year) year=${v:0:4} ;;
    esac
  done < <(ffmpeg -nostdin -hide_banner -i "$f" -f ffmetadata - 2>"$err")

  base=${f##*/}; base=${base%.*}
  [[ -n $title ]] || title=$(sed -E 's/^[0-9]+[ ._-]+//' <<< "$base")
  folder=${f%/*}
  [[ -n $album ]] || album=${folder##*/}
  [[ -n $artist ]] || artist="Unknown Artist"
  [[ -n $aartist ]] || aartist=$artist
  secs=0
  if d=$(grep -m1 -o 'Duration: [0-9:.]*' "$err"); then
    d=${d#Duration: }
    IFS=: read -r hh mm ss <<< "$d"
    secs=$((10#$hh * 3600 + 10#$mm * 60 + 10#${ss%.*}))
  fi

  art=$(find "$folder" -maxdepth 1 -type f \( -iname 'cover.jpg' -o -iname 'cover.png' -o -iname 'folder.jpg' \
        -o -iname 'folder.png' -o -iname 'front.jpg' -o -iname 'front.png' -o -iname 'albumart*.jpg' \) -print -quit)
  if [[ -z $art ]] && grep -q 'attached pic' "$err"; then
    key=$(printf '%s|%s' "$aartist" "$album" | md5sum | cut -c1-16)
    art="$cache/art/$key.jpg"
    [[ -s $art ]] || ffmpeg -nostdin -v error -i "$f" -an -map 0:v:0 -vf 'scale=600:-2' -frames:v 1 -q:v 3 "$art" -y || art=""
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$mtime" "$(field "$title")" "$(field "$artist")" \
    "$(field "$album")" "$(field "$aartist")" "${track//[^0-9]/}" "${year//[^0-9]/}" "$secs" "$art" >> "$tmp"
done < <(find -L "$dir" -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' \
          -o -iname '*.wav' -o -iname '*.aac' -o -iname '*.alac' -o -iname '*.aiff' -o -iname '*.wma' \) -print0 2>/dev/null)

mv "$tmp" "$out"
