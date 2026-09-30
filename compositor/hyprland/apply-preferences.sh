#!/usr/bin/env bash
# Applies persistent Golden Gate preferences that are not owned by a daemon.
set -u

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/golden-gate/desktop.json"

command -v gg-hyprglass-sync >/dev/null 2>&1 && gg-hyprglass-sync >/dev/null 2>&1 || true

[ -r "$CONFIG" ] || exit 0
read -r NIGHT WARMTH BRIGHTNESS <<EOF
$(python3 - "$CONFIG" <<'PY'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    d = {}
display = d.get("display") or {}
night = "1" if display.get("nightShift", False) else "0"
warmth = int(display.get("warmth", 4500))
brightness = display.get("brightness", "")
print(night, warmth, brightness)
PY
)
EOF

if [ -n "$BRIGHTNESS" ] && command -v brightnessctl >/dev/null 2>&1; then
  python3 - "$BRIGHTNESS" <<'PY' | xargs -r brightnessctl -q set >/dev/null 2>&1 || true
import sys
try:
    v=max(.02,min(1.0,float(sys.argv[1])))
    print(f"{round(v*100)}%")
except Exception:
    pass
PY
fi

if [ "$NIGHT" = 1 ] && command -v hyprsunset >/dev/null 2>&1; then
  pgrep -x hyprsunset >/dev/null 2>&1 || setsid -f hyprsunset -t "$WARMTH" >/dev/null 2>&1
fi
