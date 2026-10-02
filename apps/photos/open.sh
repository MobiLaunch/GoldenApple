#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
file=${1:-}

if [ -n "$file" ]; then
  file=$(realpath -m -- "$file")
  dir=$(dirname -- "$file")
  GG_PHOTOS_OPEN="$file" GG_PHOTOS_DIRS="$dir" exec qs -n -p "$here/photos.qml"
fi

exec qs -n -p "$here/photos.qml"
