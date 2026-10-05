#!/bin/sh
# CitronOS Web normally uses Chromium's hardware renderer. The live ISO has
# to boot across unknown GPUs/firmware combinations; Qt WebEngine's renderer can
# terminate on some real machines even while the QML shell itself remains fine.
# Keep the installed system accelerated, but make live media deterministic.
if [ -d /run/archiso ]; then
    export GG_WEB_LIVE_SAFE=1
    export LIBGL_ALWAYS_SOFTWARE=1
    export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-} --disable-gpu --disable-gpu-compositing --disable-features=Vulkan,VaapiVideoDecoder,VaapiVideoEncoder"
    logger -t gg-web "live ISO: Chromium hardware acceleration disabled for renderer stability"
elif [ "${GG_WEB_SOFTWARE:-0}" = 1 ] || [ "${LIBGL_ALWAYS_SOFTWARE:-0}" = 1 ] || [ "${QT_QUICK_BACKEND:-}" = software ]; then
    export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:-} --disable-gpu"
fi

# WebEngine has its own renderer. Do not inherit a forced Qt Quick backend from
# the desktop shell; LIBGL_ALWAYS_SOFTWARE above is sufficient on the live ISO.
unset QT_QUICK_BACKEND
exec python3 "$(dirname "$0")/browser.py" "$@"
