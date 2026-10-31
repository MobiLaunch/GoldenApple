#!/usr/bin/env python3
"""The shell left alone draws about once a second, not continuously (T-3.3).

A new account's desktop has the Clock widget. Its hands sprang to each new
place, the second hand and the minute hand (which creeps each second) alike,
so the whole widget layer, glass and all, was drawn nine times a second at
rest: the session harness measured 16-18 % of a core in software rendering
(perf-baseline.md). Through the preview harness with its clocks running
(--idle-frames), the shell must draw at most about one frame in a typical
second once it has settled (the median second): the second hand's step.

Also checks that only the clock face keeps seconds: the shared feed every
widget reads goes by the minute, so the other faces aren't re-evaluated
every second."""
from __future__ import annotations

from pathlib import Path
import re
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SECONDS = 8
failures: list[str] = []

run = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "-o", "/dev/null",
                      "--wait", "4000", "--idle-frames", str(SECONDS)],
                     capture_output=True, text=True, timeout=300)
m = re.search(r"idle frames: (\d+) in \d+ s \(each second: ([\d ]+)\)", run.stdout)
if not m:
    failures.append(f"the preview didn't count frames (exit {run.returncode}):\n{run.stdout[-1500:]}{run.stderr[-1500:]}")
else:
    each = [int(n) for n in m.group(2).split()]
    print(f"the shell at rest: {m.group(1)} frames in {SECONDS} s (each second: {m.group(2)})")
    # Something animating at rest draws in every second; a late image or a
    # fixture answering draws in one. So the typical second is what counts.
    typical = statistics.median(each)
    if typical > 2:
        failures.append(f"the shell drew {typical:g} frames in a typical second at rest (at most 2: "
                        "something animates continuously, or springs on every clock tick)")

face = (ROOT / "shell/widgets/Face.qml").read_text()
feeds = (ROOT / "shell/widgets/Feeds.qml").read_text()
if "SystemClock.Seconds" in feeds:
    failures.append("Feeds.qml's shared clock has seconds: every widget face re-evaluates each second")
if not re.search(r"springs: false[^\n]*\n[^\n]*springs: false", face):
    failures.append("Face.qml: the minute and second hands should step (springs: false), not spring")

for f in failures:
    print("FAIL:", f)
sys.exit(1 if failures else 0)
