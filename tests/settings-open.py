#!/usr/bin/env python3
"""gg-settings PANE (apps/settings/open.sh) opens that pane: every pane and
sub-page in settings.qml as itself, GNOME Settings' panel names on the pane
that does the same job, and anything unknown on General. Panes added after
the script was written (Notifications, Lock Screen, Control Center, Menu
Bar, Spotlight, Touch ID) used to open General, or Focus."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
src = (ROOT / "apps/settings.qml").read_text()
ids = [p for p, _ in re.findall(r'\[\d, "([a-z]+)", "[^"]+", "[^"]+", "#[0-9a-f]{6}", "([A-Za-z]+)"', src)]
ids += re.findall(r'^\s+([a-z]+): \{ title:', src, re.M)

with tempfile.TemporaryDirectory() as t:
    bin_ = Path(t)
    # qs: no Settings running; then report the pane it would open with.
    (bin_ / "qs").write_text('#!/bin/sh\nfor a; do :; done\nif [ "$1" = "-n" ]; then echo "PANE=$GG_SETTINGS_PANE"; exit 0; fi\nexit 1\n')
    (bin_ / "hyprctl").write_text("#!/bin/sh\nexit 0\n")
    for f in bin_.iterdir():
        f.chmod(0o755)

    def opened(arg):
        r = subprocess.run(["bash", str(ROOT / "apps/settings/open.sh"), arg], capture_output=True, text=True,
                           env=dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}"), timeout=20)
        m = re.search(r"PANE=(\S*)", r.stdout)
        return m.group(1) if m else None

    failures = []
    for pane in ids:
        got = opened(pane)
        if got != pane:
            failures.append(f"gg-settings {pane} opens {got!r}")
    for legacy, want in {"display": "displays", "background": "wallpaper", "power": "battery", "notifications": "notifications",
                         "fingerprint": "touchid", "mouse": "trackpad", "region": "language", "nonsense": "general"}.items():
        got = opened(legacy)
        if got != want:
            failures.append(f"gg-settings {legacy} opens {got!r}, not {want}")
        if got not in ids:
            failures.append(f"gg-settings {legacy} opens {got!r}, which isn't a pane")

for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"gg-settings: all {len(ids)} panes and sub-pages open as themselves; GNOME names and unknowns land on real panes")
sys.exit(1 if failures else 0)
