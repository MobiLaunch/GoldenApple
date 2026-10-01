#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
file=${1:-}
GG_TEXTEDIT_FILE="$file" exec qs -n -p "$here/textedit.qml"
