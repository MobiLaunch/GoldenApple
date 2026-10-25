#!/bin/sh
# Compatibility CLI: Citron is a shell-integrated overlay, never an app.
# Right-click, writing and voice invocations keep working. Aion Labs' models
# work with text, so Citron no longer creates or edits images.
set -eu
mode=ask
case "${1:-}" in
  --voice) mode=voice ;;
  --writing) mode=writing ;;
  --image|--photo)
    echo "Citron Intelligence works with text: creating and editing images isn't available." >&2
    exit 2
    ;;
  --settings) exec gg-settings intelligence ;;
  "") ;;
  *) printf '%s\n' 'Usage: gg-intelligence [--voice|--writing|--settings]' >&2; exit 2 ;;
esac
exec qs -c golden-gate ipc call citron "$mode"
