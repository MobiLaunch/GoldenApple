#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
file=${1:-}
# Running already (its window maybe put away): bring it back, with the file.
if [ -n "$file" ]; then
  case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
  qs -p "$here/textedit.qml" ipc call app open "$file" >/dev/null 2>&1 && exit 0
else
  qs -p "$here/textedit.qml" ipc call app reopen >/dev/null 2>&1 && exit 0
fi
GG_TEXTEDIT_FILE="$file" exec qs -n -p "$here/textedit.qml"
