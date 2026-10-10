#!/bin/sh
# Native Archive Utility. --create creates a ZIP without starting the UI.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${1:-}" = "--create" ]; then
    shift
    [ "$#" -gt 0 ] || { echo "Select files to compress." >&2; exit 2; }
    exec python3 "$here/archive/helper.py" create "$@"
fi
GG_ARCHIVE_PATH="${1:-}" exec qs -n -p "$here/archive.qml"
