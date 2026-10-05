#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=ask
photo=
case "${1:-}" in
  --photo) mode=edit; photo=$(realpath -e -- "${2:?Choose a photo}") ;;
  --writing) mode=writing ;;
  --image) mode=image ;;
  --settings) mode=settings ;;
  "") ;;
  *) printf '%s\n' 'Usage: gg-intelligence [--writing|--image|--settings|--photo FILE]' >&2; exit 2 ;;
esac
GG_INTELLIGENCE_MODE="$mode" GG_INTELLIGENCE_PHOTO="$photo" exec qs -n -p "$here/intelligence.qml"
