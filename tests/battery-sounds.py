#!/usr/bin/env python3
"""Finishing touches: the battery reads the firmware's own level (weighted
across batteries; 100% when fully charged) with a smoothed time left and a
menu in the menu bar; CitronOS's own alert sounds (chosen in Settings ›
Sound) play with notifications, and a chime when power is connected."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


# The firmware's level, weighted by each battery's full charge.
js = (ROOT / "shell/components/battery.js").read_text().replace(".pragma library", "")
if shutil.which("node"):
    cases = {"one": "87 50000000\n", "two": "100 20000000\n50 60000000\n", "no full": "64\n", "none": "", "junk": "abc\n150 1\n"}
    script = js + "\nconsole.log(JSON.stringify(Object.fromEntries(Object.entries(%s).map(([k, v]) => [k, level(v)]))))" % json.dumps(cases)
    out = json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)
    check(abs(out["one"] - 0.87) < 1e-9, f"one battery: its capacity ({out['one']})")
    check(abs(out["two"] - 0.625) < 1e-9, f"two batteries: weighted by their full charge ({out['two']})")
    check(abs(out["no full"] - 0.64) < 1e-9, f"no full-charge reading: the capacity as it is ({out['no full']})")
    check(out["none"] == -1 and out["junk"] == -1, f"nothing to go on: -1, so UPower's is used ({out['none']}, {out['junk']})")
elif os.environ.get("CI"):
    failures.append("node is needed to check the battery level")

battery = (ROOT / "shell/components/Battery.qml").read_text()
check("/sys/class/power_supply" in battery and "capacity" in battery, "the level is the firmware's")
check("level: full ? 1" in battery, "fully charged reads 100%")
check("Calculating…" in battery and "smoothed * 0.8" in battery, "the time left is smoothed, and Calculating… at first")
check('Prefs.chargingSound' in battery and 'soundPath("Charging")' in battery, "connecting power plays the chime, if chosen")
for f in ("shell/MenuBar.qml", "shell/LockScreen.qml", "shell/widgets/Feeds.qml"):
    text = (ROOT / f).read_text()
    check("Battery." in text and "UPower.displayDevice.percentage" not in text, f"{f} shows the same level (Battery)")
bar = (ROOT / "shell/MenuBar.qml").read_text()
check('id: batteryMenu' in bar and "Battery.timeText" in bar and "Battery Settings…" in bar, "the menu bar's battery has its menu")

# The sounds: CitronOS's own, made by design/sounds.py, short and clean.
sounds = ROOT / "apps/lib/assets/sounds"
names = ["Crystal", "Ping", "Pebble", "Bubble", "Breeze", "Chord", "Charging"]
for name in names:
    path = sounds / f"{name}.wav"
    if not path.exists():
        failures.append(f"{name}.wav is there")
        continue
    with wave.open(str(path)) as w:
        frames = w.readframes(w.getnframes())
        check(w.getframerate() == 48000 and w.getnchannels() == 1 and w.getsampwidth() == 2, f"{name}: 48 kHz mono 16-bit")
        check(0.15 < w.getnframes() / w.getframerate() < 1.5, f"{name}: short")
        peak = max(abs(int.from_bytes(frames[i:i + 2], "little", signed=True)) for i in range(0, len(frames), 2))
        check(peak < 32767 * 0.6, f"{name}: never clips ({peak})")
        last = abs(int.from_bytes(frames[-2:], "little", signed=True))
        check(last < 200, f"{name}: fades to silence, no click at the end ({last})")
with tempfile.TemporaryDirectory() as t:
    gen = Path(t) / "sounds.py"
    gen.write_text((ROOT / "design/sounds.py").read_text().replace(
        'Path(__file__).resolve().parents[1] / "apps/lib/assets/sounds"', f'Path({t!r})'))
    subprocess.run([sys.executable, str(gen)], check=True, capture_output=True)
    check(all((Path(t) / f"{n}.wav").read_bytes() == (sounds / f"{n}.wav").read_bytes() for n in names),
          "the sounds are what design/sounds.py makes")

notes = (ROOT / "shell/Notifications.qml").read_text()
check("Prefs.soundPath(Prefs.alertSound)" in notes, "notifications play the alert sound chosen")
pane = (ROOT / "apps/settings/panes/SoundPane.qml").read_text()
for name in names[:-1]:
    check(f'"{name}"' in pane, f"Settings › Sound offers {name}")
check('setPref(["sound", "charging"]' in pane, "Settings › Sound turns the charging chime on and off")
r = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "app", "apps/settings.qml",
                    "--env", "GG_SETTINGS_PANE=sound", "--wait", "1000", "--require-object", "alertSounds",
                    "-o", str(Path(tempfile.gettempdir()) / "sound-pane.png")],
                   cwd=ROOT, capture_output=True, text=True, timeout=200,
                   env=dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen")))
check(r.returncode == 0 and "TypeError" not in r.stderr, f"the Sound pane shows the alert sounds: {r.stderr.strip()[-300:]}")

for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print("Battery and sounds: the firmware's level (weighted, 100% when full), a smoothed time left and a menu; CitronOS's own alert sounds and charging chime")
sys.exit(1 if failures else 0)
