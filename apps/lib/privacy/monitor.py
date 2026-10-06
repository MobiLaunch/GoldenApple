#!/usr/bin/env python3
"""Which apps are using the microphone, camera, screen and location.

Prints one JSON line whenever that changes, for the menu bar's privacy
indicators and Control Center:
  {"mic": ["Citron"], "camera": [], "screen": ["Web"], "location": ["Weather"]}

- Microphone, camera and screen sharing come from PipeWire's graph, followed
  live with `pw-dump --monitor` (no polling of the audio stack): a capture
  stream that is running, and what it is linked to — a microphone, a camera
  (v4l2/libcamera) or a screen cast (the Hyprland portal's xdph nodes).
  Meters (stream.monitor) and passive helpers don't count; a stream
  recording what's playing (a sink's monitor) isn't the microphone.
- A camera opened directly, without PipeWire, and screen recorders
  (wf-recorder and the like) are found in /proc.
- Location: CitronOS's location helper leaves a file under
  $XDG_RUNTIME_DIR/citron-location while it locates and for a few seconds
  after, and GeoClue says whether any other app is being given a location.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import time

RECORDERS = {"wf-recorder": "Screen Recording", "wl-screenrec": "Screen Recording",
             "gpu-screen-reco": "Screen Recording", "obs": "OBS", "kooha": "Kooha"}
SKIP_PROCS = {"pipewire", "wireplumber", "pipewire-pulse"}


def merge(old: dict, new: dict) -> dict:
    """pw-dump --monitor repeats an object when it changes; keep what it left out."""
    out = dict(old)
    for k, v in new.items():
        out[k] = merge(old[k], v) if isinstance(v, dict) and isinstance(old.get(k), dict) else v
    return out


class Graph:
    def __init__(self) -> None:
        self.objects: dict[int, dict] = {}

    def apply(self, items: list) -> None:
        for o in items:
            if not isinstance(o, dict) or "id" not in o:
                continue
            if o.get("info") is None and "type" not in o:
                self.objects.pop(o["id"], None)
            else:
                self.objects[o["id"]] = merge(self.objects.get(o["id"], {}), o)

    @staticmethod
    def props(o: dict) -> dict:
        return (o.get("info") or {}).get("props") or {}

    def nodes(self):
        for o in self.objects.values():
            if o.get("type") == "PipeWire:Interface:Node":
                yield o

    def sources_of(self, node_id: int) -> list[dict]:
        found = []
        for o in self.objects.values():
            if o.get("type") != "PipeWire:Interface:Link":
                continue
            info = o.get("info") or {}
            if info.get("input-node-id") == node_id and info.get("output-node-id") in self.objects:
                found.append(self.objects[info["output-node-id"]])
        return found

    def usage(self) -> dict[str, set[str]]:
        use = {"mic": set(), "camera": set(), "screen": set()}
        for node in self.nodes():
            p = self.props(node)
            cls = p.get("media.class", "")
            running = (node.get("info") or {}).get("state") == "running"
            if not running or truthy(p.get("stream.monitor")) or truthy(p.get("node.passive")):
                continue
            name = app_name(p)
            sources = [self.props(s) for s in self.sources_of(node["id"])]
            if cls == "Stream/Input/Audio":
                # Recording what plays (a sink's monitor) isn't the microphone.
                if sources and all(s.get("media.class", "").startswith("Audio/Sink") for s in sources):
                    continue
                use["mic"].add(name)
            elif cls == "Stream/Input/Video":
                if any(is_screen(s) for s in sources):
                    use["screen"].add(name)
                elif not sources or any(is_camera(s) for s in sources):
                    use["camera"].add(name)
        return use


def truthy(v) -> bool:
    return v is True or str(v).lower() == "true"


def is_screen(p: dict) -> bool:
    name = str(p.get("node.name", "")).lower()
    return name.startswith(("xdph", "xdpw")) or "screencast" in name or "screen" in str(p.get("media.role", "")).lower()


def is_camera(p: dict) -> bool:
    return p.get("device.api") in ("v4l2", "libcamera") or "camera" in str(p.get("media.role", "")).lower() \
        or str(p.get("node.name", "")).startswith(("v4l2_input", "libcamera_input"))


def app_name(p: dict) -> str:
    name = p.get("application.name") or p.get("application.process.binary") or p.get("node.description") \
        or p.get("node.name") or "An app"
    return pretty(str(name))


def pretty(name: str) -> str:
    known = {"pw-record": "An app", "python3": "An app", "firefox": "Firefox", "chromium": "Chromium",
             "QtWebEngineProcess": "Web", "wf-recorder": "Screen Recording"}
    return known.get(name, name[:1].upper() + name[1:])


def proc_usage() -> dict[str, set[str]]:
    """Cameras opened without PipeWire, and screen recorders."""
    use = {"camera": set(), "screen": set()}
    cams = os.path.exists("/dev/video0") or any(Path("/dev").glob("video*"))
    for d in Path("/proc").iterdir():
        if not d.name.isdecimal():
            continue
        try:
            comm = (d / "comm").read_text().strip()
        except OSError:
            continue
        if comm in RECORDERS:
            use["screen"].add(RECORDERS[comm])
        if not cams or comm in SKIP_PROCS:
            continue
        try:
            fds = list((d / "fd").iterdir())
        except OSError:
            continue                  # another user's process
        for fd in fds:
            try:
                if os.readlink(fd).startswith("/dev/video"):
                    use["camera"].add(pretty(comm))
                    break
            except OSError:
                pass
    return use


def location_usage(geoclue: bool) -> set[str]:
    use = set()
    run = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "citron-location"
    for f in run.glob("*.json") if run.is_dir() else []:
        try:
            data = json.loads(f.read_text())
            if time.time() > float(data.get("until") or 0):
                os.kill(int(data["pid"]), 0)          # still locating, or gone (raises)
            use.add(str(data.get("app") or "An app"))
        except (OSError, ValueError, KeyError, TypeError):
            try:
                f.unlink()            # left by a helper that is gone
            except OSError:
                pass
    if geoclue:
        try:
            out = subprocess.run(["busctl", "--system", "get-property", "org.freedesktop.GeoClue2",
                                  "/org/freedesktop/GeoClue2/Manager", "org.freedesktop.GeoClue2.Manager", "InUse"],
                                 capture_output=True, text=True, timeout=2).stdout
            if out.strip() == "b true":
                use.add("An app")
        except (OSError, subprocess.SubprocessError):
            pass
    return use


class Dump:
    """pw-dump --monitor: arrays of objects, one after another, on stdout."""

    def __init__(self) -> None:
        self.proc = None
        self.buf = ""
        self.decoder = json.JSONDecoder()
        self.retry = 0.0

    def start(self, graph: Graph) -> None:
        if self.proc or time.monotonic() < self.retry or not shutil.which("pw-dump"):
            return
        graph.objects.clear()
        self.buf = ""
        self.proc = subprocess.Popen(["pw-dump", "--monitor", "--no-colors"], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL)
        os.set_blocking(self.proc.stdout.fileno(), False)

    def read(self, graph: Graph) -> None:
        try:
            chunk = os.read(self.proc.stdout.fileno(), 1 << 20)
        except BlockingIOError:
            return
        if not chunk:                 # PipeWire restarted: follow it again shortly
            self.proc.wait()
            self.proc = None
            self.retry = time.monotonic() + 3
            graph.objects.clear()
            return
        self.buf += chunk.decode("utf-8", errors="replace")
        while True:
            text = self.buf.lstrip()
            if not text:
                self.buf = ""
                return
            try:
                items, end = self.decoder.raw_decode(text)
            except ValueError:
                self.buf = text
                return                # the rest of this array is still on its way
            self.buf = text[end:]
            if isinstance(items, list):
                graph.apply(items)


def main() -> int:
    graph = Graph()
    dump = Dump()
    geoclue = bool(shutil.which("busctl")) and Path("/usr/share/dbus-1/system-services/org.freedesktop.GeoClue2.service").exists()
    last = None
    next_scan = 0.0
    scanned = {"camera": set(), "screen": set()}
    located: set[str] = set()
    while True:
        dump.start(graph)
        fds = [dump.proc.stdout] if dump.proc else []
        ready, _, _ = select.select(fds, [], [], 1.0)
        if ready:
            dump.read(graph)
        now = time.monotonic()
        if now >= next_scan:
            scanned = proc_usage()
            located = location_usage(geoclue)
            next_scan = now + 2.0
        use = graph.usage()
        state = {"mic": sorted(use["mic"]), "camera": sorted(use["camera"] | scanned["camera"]),
                 "screen": sorted(use["screen"] | scanned["screen"]), "location": sorted(located)}
        if state != last:
            last = state
            try:
                print(json.dumps(state), flush=True)
            except BrokenPipeError:
                return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
