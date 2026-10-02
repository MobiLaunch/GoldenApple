#!/bin/sh
# Keep Chromium sandboxing enabled. VM graphics fallback is opt-in or inherited
# from the session, and is confined to this browser process.
if [ "${GG_WEB_SOFTWARE:-0}" = 1 ] || [ "${LIBGL_ALWAYS_SOFTWARE:-0}" = 1 ] || [ "${QT_QUICK_BACKEND:-}" = software ]; then
    export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-} --disable-gpu"
fi
# WebEngine has its own renderer; the shell's Qt Quick backend is not inherited.
unset QT_QUICK_BACKEND
exec python3 "$(dirname "$0")/browser.py" "$@"
