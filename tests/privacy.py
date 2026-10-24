#!/usr/bin/env python3
"""Privacy indicators (apps/lib/privacy/monitor.py, shell/components/Privacy.qml):

- from PipeWire's graph as `pw-dump --monitor` reports it: a running capture
  stream from a microphone counts, a meter, a passive helper or a recording
  of what's playing doesn't; a video stream from a v4l2 camera is the camera,
  from the Hyprland portal the screen; a node that goes away stops counting,
  and an update that repeats part of an object keeps the rest;
- location from the location helper's files (a file left by a helper that is
  gone is removed);
- the menu bar draws a dot in each colour (location an arrow) only while
  something is in use.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("monitor", ROOT / "apps/lib/privacy/monitor.py")
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def node(i, cls, state="running", **props):
    return {"id": i, "type": "PipeWire:Interface:Node", "info": {"state": state, "props": {"media.class": cls, **props}}}


def link(i, out, inp):
    return {"id": i, "type": "PipeWire:Interface:Link", "info": {"output-node-id": out, "input-node-id": inp}}


g = monitor.Graph()
g.apply([
    node(30, "Audio/Source", "running", **{"node.name": "alsa_input.pci"}),
    node(31, "Audio/Sink", "running", **{"node.name": "alsa_output.pci"}),
    node(40, "Stream/Input/Audio", **{"application.name": "Citron"}), link(41, 30, 40),
    node(42, "Stream/Input/Audio", **{"application.name": "Meter", "stream.monitor": True}), link(43, 30, 42),
    node(44, "Stream/Input/Audio", **{"application.name": "Recorder"}), link(45, 31, 44),
    node(46, "Stream/Input/Audio", "idle", **{"application.name": "Idle"}),
    node(47, "Stream/Input/Audio", **{"application.name": "Helper", "node.passive": "true"}),
    node(50, "Video/Source", **{"device.api": "v4l2", "node.name": "v4l2_input.usb"}),
    node(51, "Stream/Input/Video", **{"application.name": "Web"}), link(52, 50, 51),
    node(60, "Video/Source", **{"node.name": "xdph-streaming-0"}),
    node(61, "Stream/Input/Video", **{"application.name": "Chromium"}), link(62, 60, 61),
])
use = g.usage()
check(use["mic"] == {"Citron"}, f"only a real microphone recording counts: {use['mic']}")
check(use["camera"] == {"Web"}, f"a v4l2 video stream is the camera: {use['camera']}")
check(use["screen"] == {"Chromium"}, f"the portal's stream is the screen: {use['screen']}")
# The stream stops (pw-dump repeats the node with its new state only), then goes.
g.apply([{"id": 40, "type": "PipeWire:Interface:Node", "info": {"state": "idle"}}])
check(not g.usage()["mic"], "an idle stream stops counting")
check(g.objects[40]["info"]["props"].get("application.name") == "Citron", "an update keeps what it left out")
g.apply([{"id": 51, "info": None}])
check(not g.usage()["camera"], "a node that goes away stops counting")

with tempfile.TemporaryDirectory() as t:
    run = Path(t) / "citron-location"
    run.mkdir()
    (run / "live.json").write_text(json.dumps({"pid": os.getpid(), "app": "Weather"}))
    (run / "gone.json").write_text(json.dumps({"pid": 2 ** 22 + 7, "app": "Maps"}))
    os.environ["XDG_RUNTIME_DIR"] = t
    check(monitor.location_usage(False) == {"Weather"}, "location: the live helper counts")
    check(not (run / "gone.json").exists(), "location: a gone helper's file is removed")

# A camera opened without PipeWire is looked for only when the kernel says a
# /dev/video device was opened or closed (inotify), not on a timer.
with tempfile.TemporaryDirectory() as t:
    dev = Path(t)
    (dev / "video0").write_text("")
    w = monitor.CameraWatch(str(dev))
    check(w.fd >= 0 and len(w.devices) == 1, "the camera watch follows /dev/video0 with inotify")
    check(w.due(0) and not w.due(0), "cameras: looked at once at the start, then not again without cause")
    open(dev / "video0").close()
    w.drain()
    check(w.due(0), "cameras: opening or closing one is noticed")
    (dev / "video1").write_text("")
    w.drain()
    check(len(w.devices) == 2 and w.due(0), "cameras: one plugged in is watched too")
    (dev / "unrelated").write_text("")
    w.drain()
    check(not w.due(0), "cameras: other files in /dev don't count")
# The graph is worked out again only after it changes.
g2 = monitor.Graph()
g2.apply([node(1, "Audio/Source"), node(2, "Stream/Input/Audio", **{"application.name": "Rec"}), link(3, 1, 2)])
first = g2.usage()
check(g2.usage() is first and first["mic"] == {"Rec"}, "the graph's answer is kept while it doesn't change")
g2.apply([{"id": 2, "info": None}])
check(not g2.usage()["mic"], "a change is seen at once")

# The menu bar's dots, in their colours, only while in use.
def shot(name, state):
    out = Path(tempfile.gettempdir()) / f"privacy-{name}.png"
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "-v",
                           "--env", "GG_PRIVACY_PREVIEW=" + json.dumps(state), "-o", str(out)],
                          capture_output=True, text=True, timeout=180, cwd=ROOT)
    bad = [l for l in proc.stderr.splitlines() if re.search(r"(Privacy|MenuBar)\.qml", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed {proc.stderr[-300:]}")
    check(not bad, f"{name}: QML errors {bad[:3]}")
    from PySide6.QtGui import QImage
    return QImage(str(out))


def count(img, colour):
    want = [int(colour[i:i + 2], 16) for i in (1, 3, 5)]
    return sum(1 for x in range(1000, 1300) for y in range(4, 26)
               if all(abs(a - b) < 40 for a, b in zip(img.pixelColor(x, y).getRgb()[:3], want)))


on = shot("on", {"mic": ["Citron"], "camera": ["Web"], "screen": ["Kooha"], "location": ["Weather"]})
off = shot("off", {})
qml = (ROOT / "shell/components/Privacy.qml").read_text()
colours = dict(re.findall(r'(\w+): "(#[0-9a-f]{6})"', re.search(r"colors: \(\{(.*?)\}\)", qml).group(1)))
for kind in ("mic", "camera", "screen", "location"):
    check(count(on, colours[kind]) >= 6, f"{kind}: its indicator shows ({count(on, colours[kind])} px)")
    check(count(off, colours[kind]) < 3, f"{kind}: nothing while unused ({count(off, colours[kind])} px)")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Privacy: microphone, camera, screen and location in use, from PipeWire and the location helper; the menu bar shows each")
