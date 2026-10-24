#!/bin/sh
if [ ! -d /run/archiso ]; then
  printf '%s\n' "Install CitronOS is only available from the live USB." >&2
  exit 1
fi
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec qs -n -p "$here/installer.qml"
