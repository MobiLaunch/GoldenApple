#!/bin/sh
# Compatibility CLI: Citron is a shell-integrated overlay, never an app.
# Existing right-click, image, writing and voice invocations keep working.
set -eu
mode=ask
case "${1:-}" in
  --voice) mode=voice ;;
  --writing) mode=writing ;;
  --image) mode=image ;;
  --photo)
    [ -n "${2:-}" ] || { echo "Choose a photo." >&2; exit 2; }
    photo=$(realpath -e -- "$2")
    exec qs -c golden-gate ipc call citron photo "$photo"
    ;;
  --settings) exec gg-settings intelligence ;;
  "") ;;
  *) printf '%s\n' 'Usage: gg-intelligence [--voice|--writing|--image|--settings|--photo FILE]' >&2; exit 2 ;;
esac
exec qs -c golden-gate ipc call citron "$mode"
