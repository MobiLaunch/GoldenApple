#!/bin/sh
# CitronOS Web starts accelerated on installed systems, but some live GPUs
# crash the Qt/Chromium renderer before the first window appears. Recover from
# one native crash without changing or deleting the user's browser profile.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
umask 077
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
# A Qt/Wayland-specific crash can survive the Mesa software fallback. Use
# XWayland only when the compositor already provides a DISPLAY endpoint.
if [ -f "$state/web-xcb-mode" ] && [ -n "${DISPLAY:-}" ]; then
    export QT_QPA_PLATFORM=xcb
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
    79|132|133|134|135|136|137|138|139)
        if [ "${GG_WEB_LIVE_SAFE:-0}" != 1 ] && [ "${LIBGL_ALWAYS_SOFTWARE:-0}" != 1 ]; then
            printf 'Renderer failed or requested safe restart; trying Mesa software rendering.\n' >> "$log"
            logger -t gg-web "browser exit $status; retrying with Mesa software rendering" 2>/dev/null || :
            safe_graphics
            if run_web "$@"; then
                touch "$state/web-safe-mode" 2>/dev/null || :
                exit 0
            else
                status=$?
                printf 'Software-rendered retry exited with status %s\n' "$status" >> "$log"
            fi
        fi
        # An explicit safe-mode boot can also fail. Only retry a genuine
        # native crash on XWayland when the desktop provides it, not QML or
        # Python errors, and never more than once per platform.
        case "$status" in
            132|133|134|135|136|137|138|139)
                if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${DISPLAY:-}" ] &&
                   [ "${QT_QPA_PLATFORM:-}" != xcb ]; then
                    printf 'Attempting XWayland-compatible browser startup.\n' >> "$log"
                    safe_graphics
                    export QT_QPA_PLATFORM=xcb
                    if run_web "$@"; then
                        touch "$state/web-safe-mode" "$state/web-xcb-mode" 2>/dev/null || :
                        exit 0
                    else
                        status=$?
                        printf 'XWayland retry exited with status %s\n' "$status" >> "$log"
                    fi
                fi
                ;;
        esac
        ;;
esac
logger -t gg-web "Web failed (exit $status); see $log" 2>/dev/null || :
# Exit 2 is a failed QML interface; exit 3 is a missing/incompatible Qt.
# Both report an actionable private-log-safe diagnosis in browser.py.
why=
if [ "$status" = 2 ] || [ "$status" = 3 ]; then
    why=$(grep 'WEB-CANT-START: ' "$log" 2>/dev/null | tail -n 1 | sed 's/^WEB-CANT-START: //')
fi
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Web couldn't start" "${why:-Details: $log}" 2>/dev/null || :
fi
exit "$status"
