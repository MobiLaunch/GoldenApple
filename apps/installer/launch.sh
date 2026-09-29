#!/bin/sh
# Golden Gate graphical installer launcher. Installation itself remains delegated
# to Arch's maintained archinstall engine; this wrapper gives the live desktop a
# discoverable, branded entry point and refuses to run outside the live image.
if [ ! -d /run/archiso ]; then
  printf '%s\n' "Install Golden Gate is only available from the live USB." >&2
  exit 1
fi
exec ghostty -e sh -lc 'printf "\\033[2J\\033[H"; printf "\\n  Golden Gate Installer\\n  ─────────────────────\\n\\n"; printf "  Choose the destination carefully. The guided installer will confirm destructive disk changes before writing.\\n\\n"; exec sudo archinstall'
