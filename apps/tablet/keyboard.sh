#!/bin/sh
# Touch-friendly on-screen keyboard for tablet/convertible Golden Gate systems.
# Squeekboard speaks Wayland virtual-keyboard and input-method protocols.
# Invoked on demand; never starts a competing keyboard in normal desktop mode.
set -eu
mode="${1:-show}"
case "$mode" in show|hide) ;; *) echo "Usage: gg-tablet-keyboard show|hide" >&2; exit 2 ;; esac
command -v busctl >/dev/null 2>&1 || { echo "D-Bus unavailable" >&2; exit 1; }
if [ "$mode" = show ]; then
    command -v squeekboard >/dev/null 2>&1 || {
        echo "Install the Arch package squeekboard for the touch keyboard." >&2; exit 1;
    }
    if ! busctl --user --no-pager --quiet status sm.puri.OSK0 >/dev/null 2>&1; then
        # Start one user-scoped keyboard daemon, not one per tap.
        ( squeekboard >/dev/null 2>&1 & )
        i=0
        while [ "$i" -lt 15 ]; do
            if busctl --user --no-pager --quiet status sm.puri.OSK0 >/dev/null 2>&1; then break; fi
            sleep 0.2
            i=$((i + 1))
        done
    fi
fi
if ! busctl --user --no-pager --quiet status sm.puri.OSK0 >/dev/null 2>&1; then
    [ "$mode" = hide ] && exit 0
    echo "The Wayland touch keyboard did not start. Check the input-method protocol and session log." >&2
    exit 1
fi
busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b \
    "$([ "$mode" = show ] && echo true || echo false)"
