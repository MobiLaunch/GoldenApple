#!/bin/sh
# Always start Messages as a new Quickshell application, but retain its
# diagnostic output when QML fails. A desktop-file launch otherwise hides
# the error completely and appears to do nothing.
set -u
# Startup diagnostics can contain phone numbers or contact names.
# Keep log files private to this account.
umask 077
apps=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
state="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$state"
log="$state/golden-gate-messages.log"
# Avoid unbounded logs on machines that repeatedly fail on startup.
if [ -f "$log" ] && [ "$(wc -c < "$log")" -gt 2000000 ]; then
    mv -f "$log" "$log.old"
fi
{
    printf '%s\n' "--- Messages launched $(date -Is) ---"
    qs -n -p "$apps/messages.qml" "$@"
} >> "$log" 2>&1
result=$?
if [ "$result" -ne 0 ]; then
    printf 'Messages could not start (exit %s). See %s\n' "$result" "$log" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name='Golden Gate Messages' -u critical             'Messages could not open'             "Startup details were saved to $log" >/dev/null 2>&1 || :
    fi
fi
exit "$result"
