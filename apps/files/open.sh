#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
home=${HOME:?}
path="$home"
select=""

if [ "${1:-}" = "--select" ] && [ -n "${2:-}" ]; then
  select=$(realpath -m -- "$2")
  path=$(dirname -- "$select")
elif [ -n "${1:-}" ]; then
  candidate=$(realpath -m -- "$1")
  if [ -d "$candidate" ]; then
    path="$candidate"
  else
    select="$candidate"
    path=$(dirname -- "$candidate")
  fi
fi

GG_FILES_PATH="$path" GG_FILES_SELECT="$select" exec qs -n -p "$here/files.qml"
