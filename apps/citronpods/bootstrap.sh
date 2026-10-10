#!/usr/bin/env bash
# Golden Gate first-login CitronPods engine integration.
# Does not launch a duplicate Qt app. Installs the native M10 daemon only if
# its verified source archive is available and the daemon isn't installed.
# Safe to run on every login or when a new source ZIP is placed in Downloads.
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"
state="${XDG_STATE_HOME:-$HOME/.local/state}/golden-gate"
mkdir -p "$state"
exec 9>"$state/citronpods-bootstrap.lock"
flock -n 9 || exit 0

if command -v citronpods-daemon >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || :
        systemctl --user enable --now citronpods-daemon.service >/dev/null 2>&1 || :
    fi
    exit 0
fi
if ! command -v gg-install-citronpods >/dev/null 2>&1; then
    echo 'CitronPods installer is missing; please update Golden Gate.' >&2
    exit 0
fi
# An incomplete download is never handed to the compiler.
source_zip=$(gg-install-citronpods --find 2>/dev/null || true)
if [ -z "$source_zip" ] || [ ! -f "$source_zip" ]; then
    printf 'Engine pending: place LibrePods-CitronPods-M10-Qt6-Fixed.zip in Downloads.\n' > "$state/citronpods-engine-status"
    exit 0
fi
# Validate again in case the source changed between --find and compile.
# Automatic CMake execution must never trust a Downloads ZIP by filename.
trusted="d14d3e74efb716357713d024bcb7c2311ae1226d8fa6bb883f4b9237661b4da4"
actual=$(sha256sum -- "$source_zip" | cut -d' ' -f1)
if [ "$actual" != "$trusted" ]; then
    printf 'Unrecognized CitronPods source. Select it explicitly in Settings if trusted.\n' > "$state/citronpods-engine-status"
    exit 0
fi
printf 'Building native AirPods engine from validated M10 source…\n' > "$state/citronpods-engine-status"
if gg-install-citronpods "$source_zip" > "$state/citronpods-build.log" 2>&1; then
    printf 'Native AirPods engine installed and service started.\n' > "$state/citronpods-engine-status"
else
    status=$?
    printf 'AirPods engine build needs attention (exit %s). See CitronPods log.\n' "$status" > "$state/citronpods-engine-status"
    exit "$status"
fi
