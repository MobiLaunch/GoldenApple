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
  --voice)
    # Voice lives in the desktop's own overlay, without opening another window.
    exec qs -c golden-gate ipc call citron toggle
    ;;
  "") ;;
  *) printf '%s\n' 'Usage: gg-intelligence [--voice|--writing|--image|--settings|--photo FILE]' >&2; exit 2 ;;
esac
GG_INTELLIGENCE_MODE="$mode" GG_INTELLIGENCE_PHOTO="$photo" exec qs -n -p "$here/intelligence.qml"
