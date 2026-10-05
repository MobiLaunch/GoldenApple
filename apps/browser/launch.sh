#!/bin/sh
# CitronOS Web starts accelerated on installed systems, but some live GPUs
# crash the Qt/Chromium renderer before the first window appears. Recover from
# one native crash without changing or deleting the user's browser profile.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
state="${XDG_STATE_HOME:-$HOME/.local/state}/golden-gate"
mkdir -p "$state" 2>/dev/null || state="${TMPDIR:-/tmp}"
log="$state/web.log"
# Diagnostics may contain visited addresses or site output: private to user.
umask 077
if [ -f "$log" ] && [ "$(wc -c < "$log")" -gt 1048576 ]; then
    mv -f "$log" "$log.old" 2>/dev/null || :
fi
touch "$log" 2>/dev/null || log=/dev/null
chmod 600 "$log" 2>/dev/null || :
printf '\n--- CitronOS Web launch %s ---\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$log"
child=
forward_exit() {
    trap - TERM INT HUP
    if [ -n "$child" ]; then
        kill -TERM "$child" 2>/dev/null || :
        wait "$child" 2>/dev/null || :
    fi
    exit 143
}
trap forward_exit TERM INT HUP

safe_graphics() {
    # Preserve the Qt Quick RHI and the Chromium sandbox. Force Mesa software
    # GL and tell Chromium not to attempt Vulkan/GPU compositing.
    export LIBGL_ALWAYS_SOFTWARE=1
    export QSG_RHI_BACKEND=opengl
    export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-} --disable-gpu --disable-gpu-compositing --disable-features=Vulkan,VaapiVideoDecoder,VaapiVideoEncoder"
}

# Qt Quick's forced software scenegraph causes issues when mixed with an
# accelerated WebEngine; Mesa GL fallback is more widely compatible.
unset QT_QUICK_BACKEND
if [ -d /run/archiso ]; then
    export GG_WEB_LIVE_SAFE=1
    safe_graphics
    logger -t gg-web "live ISO: Chromium acceleration disabled" 2>/dev/null || :
elif [ "${GG_WEB_SOFTWARE:-0}" = 1 ] || [ "${LIBGL_ALWAYS_SOFTWARE:-0}" = 1 ] ||
     [ -f "$state/web-safe-mode" ]; then
    safe_graphics
fi

run_web() {
    python3 "$here/browser.py" "$@" >> "$log" 2>&1 &
    child=$!
    wait "$child"
    result=$?
    child=
    return "$result"
}

if run_web "$@"; then
    exit 0
else
    status=$?
fi
printf 'Web exited with status %s\n' "$status" >> "$log"

# Do not mask missing Python modules, QML errors (exit 2), or an existing
# profile lock (exit 1). Native aborts/segfaults are frequently GPU failures.
case "$status" in
    132|133|134|135|136|137|138|139)
        if [ "${GG_WEB_LIVE_SAFE:-0}" != 1 ] && [ "${LIBGL_ALWAYS_SOFTWARE:-0}" != 1 ]; then
            printf 'Native crash detected; retrying once with safe graphics.\n' >> "$log"
            logger -t gg-web "browser native crash $status; retrying with Mesa software rendering" 2>/dev/null || :
            safe_graphics
            if run_web "$@"; then
                # A successful session keeps the safe setting for next time.
                touch "$state/web-safe-mode" 2>/dev/null || :
                exit 0
            else
                status=$?
                printf 'Software-rendered retry exited with status %s\n' "$status" >> "$log"
            fi
        fi
        ;;
esac
logger -t gg-web "Web failed (exit $status); see $log" 2>/dev/null || :
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Web couldn't start" "Details: $log" 2>/dev/null || :
fi
exit "$status"
