#!/usr/bin/env python3
"""AirPlay Receiver (apps/mirroring/airplay.py) turns UxPlay's log into what
Control Center shows: ready, the code a device asking has to type, who's
mirroring, and back to ready when it stops.

Checked: UxPlay's command line (the code when one is required, full screen,
the register of devices that typed it, a new device replacing the old), the
code is made once and kept private, UxPlay's own log lines move the state
along with a notification for the code and one for mirroring, and a run
against a stand-in uxplay leaves the state file saying it stopped. Also that
Control Center and Settings use it."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def load(env: dict[str, str]):
    os.environ.update(env)
    spec = importlib.util.spec_from_file_location("airplay", ROOT / "apps/mirroring/airplay.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    env = {"XDG_CONFIG_HOME": str(tmp / "config"), "XDG_STATE_HOME": str(tmp / "state"), "XDG_RUNTIME_DIR": str(tmp / "run")}
    (tmp / "run").mkdir()
    ap = load(env)

    cfg = ap.settings()
    saved = json.loads((tmp / "config/golden-gate/airplay.json").read_text())
    mode = stat.S_IMODE((tmp / "config/golden-gate/airplay.json").stat().st_mode)
    check(len(cfg["pin"]) == 4 and cfg["pin"].isdigit() and saved["pin"] == cfg["pin"] and mode == 0o600,
          "a four-digit code is made once and kept, readable only by you")
    check(ap.settings()["pin"] == cfg["pin"], "the same code next time")
    check(cfg["requirePin"] and not cfg["fullScreen"], "a code is required by default; a window, not full screen")

    cmd = ap.command(cfg, "Jordan's Laptop")
    check(cmd[:3] == [ap.UXPLAY, "-n", "Jordan's Laptop"] and "-nh" in cmd and "-nohold" in cmd
          and cmd[cmd.index("-pin") + 1] == cfg["pin"] and "-reg" in cmd and "-fs" not in cmd
          and cmd[cmd.index("-vs") + 1] == "waylandsink",
          f"UxPlay's command line: {cmd}")
    open_cmd = ap.command(dict(cfg, requirePin=False, fullScreen=True), "x")
    check("-pin" not in open_cmd and "-fs" in open_cmd, "no code when it's off; full screen when chosen")

    told = []
    clock = [1000.0]
    rx = ap.Receiver(cfg, notify=lambda title, body: told.append((title, body)), clock=lambda: clock[0])
    check(rx.line("connection request from Jordan’s iPhone (iPhone16,1) with deviceID = AA:BB:CC:DD:EE:FF\n"),
          "a connection request changes the state")
    check(rx.state["pinPending"] and rx.state["pin"] == cfg["pin"] and rx.state["device"] == "Jordan’s iPhone"
          and rx.state["model"] == "iPhone16,1", f"the device asking and the code it needs: {rx.state}")
    check(told and cfg["pin"] in told[-1][0] and "Jordan’s iPhone" in told[-1][1], f"a notification shows the code: {told[-1:]}")
    rx.line("registered new client: Jordan’s iPhone DeviceID = AA:BB PK = \n")
    check(not rx.state["pinPending"] and rx.state["pin"] == "", "the code goes once the device has typed it")
    rx.line("Open connections: 1\n")
    check(rx.state["connected"] and rx.state["since"] == 1000 and "is mirroring" in told[-1][1],
          f"mirroring, with a notification: {rx.state} {told[-1:]}")
    rx.line("Open connections: 0\n")
    check(not rx.state["connected"] and rx.state["device"] == "", "back to ready when it stops")
    rx.line("connection request from iPad (iPad13,4) with deviceID = 11\n")
    clock[0] += 120
    rx.line("some other line\n")
    check(not rx.state["pinPending"], "a code nobody typed stops showing after a minute")
    quiet = ap.Receiver(dict(cfg, requirePin=False), notify=lambda *a: told.append(a), clock=lambda: 0)
    quiet.line("connection request from Mac (Mac15,3) with deviceID = 22\n")
    check(not quiet.state["pinPending"], "no code asked for when none is required")

    # A run against a stand-in uxplay: its log, then it exits.
    fake = tmp / "uxplay"
    fake.write_text("#!/bin/sh\necho \"connection request from Phone (iPhone) with deviceID = 1\"\necho \"Open connections: 1\"\n"
                    "echo \"Open connections: 0\"\nexit 0\n")
    fake.chmod(0o755)
    run_env = dict(os.environ, **env, GG_UXPLAY=str(fake), PATH="/usr/bin:/bin")
    p = subprocess.run([sys.executable, str(ROOT / "apps/mirroring/airplay.py")], capture_output=True, text=True,
                       env=run_env, timeout=30)
    status = json.loads((tmp / "run/gg-airplay.json").read_text())
    events = [json.loads(line) for line in p.stdout.splitlines() if line.startswith("{")]
    check(p.returncode == 0 and any(e["connected"] for e in events) and status["running"] is False and not status["connected"],
          f"a run: mirroring seen, then the state file says it stopped ({status}, {events[-1:]})")

service = (ROOT / "distro/archiso/overlay/etc/systemd/user/gg-airplay.service").read_text()
check("apps/mirroring/airplay.py" in service, "the user service runs the receiver")
cc = (ROOT / "shell/ControlCenter.qml").read_text()
check("gg-airplay.json" in cc and "stopMirroring()" in cc and "_googlecast._tcp" in cc and "airplay.pinPending" in cc,
      "Control Center shows who's mirroring, the code, Stop, and Google Cast displays")
settings = (ROOT / "apps/settings.qml").read_text()
check('airplay: { title: "AirPlay Receiver", file: "AirPlayPane"' in settings
      and (ROOT / "apps/settings/panes/AirPlayPane.qml").exists(), "Settings › General › AirPlay Receiver")

print("AirPlay Receiver: " + ("all checks passed" if not failures else f"{len(failures)} failed"))
sys.exit(1 if failures else 0)
