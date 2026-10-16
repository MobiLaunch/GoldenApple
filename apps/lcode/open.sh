#!/bin/sh
# Open LCode, optionally on a project folder or a file. Like Xcode's xed, a
# file opens the Swift package that contains it, with that file selected.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project=""
file=""
if [ -n "${1:-}" ]; then
  target=$(realpath -m -- "$1")
  if [ -f "$target" ]; then
    file="$target"
    project=$(dirname -- "$target")
    dir="$project"
    while [ "$dir" != "/" ]; do
      if [ -f "$dir/Package.swift" ]; then project="$dir"; break; fi
      dir=$(dirname -- "$dir")
    done
  else
    project="$target"
  fi
fi
LCODE_PROJECT="$project" LCODE_FILE="$file" exec qs -n -p "$here/lcode.qml"
