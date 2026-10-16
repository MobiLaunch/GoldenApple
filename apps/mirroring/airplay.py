#!/usr/bin/env python3
"""AirPlay Receiver (Control Center › Screen Mirroring, Settings › General ›
AirPlay Receiver): runs UxPlay and says what it's doing.

An iPhone, iPad or Mac on the same network mirrors its screen to this
computer, under the computer's name. UxPlay only writes a log, so this reads
it and keeps a small state file the shell watches:

    $XDG_RUNTIME_DIR/gg-airplay.json
    {"running": true, "connected": true, "device": "Jordan's iPhone",
     "model": "iPhone16,1", "pinPending": false, "pin": "", "since": 1760000000}

Settings (~/.config/golden-gate/airplay.json):
    requirePin   a device must type the code shown on this computer the first
                 time it connects (it's remembered after that); default on
    fullScreen   the mirrored screen fills the display; default off

The code is shown in a notification when a device asks to connect, and a
notification says who's mirroring. Run by the gg-airplay user service.
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time

CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "golden-gate/airplay.json"
STATE_DIR = pathlib.Path(os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state")) / "golden-gate"
RUNTIME = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir())
STATUS = RUNTIME / "gg-airplay.json"
UXPLAY = os.environ.get("GG_UXPLAY", "uxplay")

REQUEST = re.compile(r"connection request from (.+?) \((.*?)\) with deviceID")
OPEN = re.compile(r"Open connections: (\d+)")
PAIRED = re.compile(r"registered new client|registration found")


def settings() -> dict:
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
        data = data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        data = {}
    pin = str(data.get("pin") or "")
    if not re.fullmatch(r"\d{4}", pin):
        # One code for this computer, kept, so the code a device was told
        # stays right; a device that typed it once isn't asked again.
        pin = f"{secrets.randbelow(10000):04d}"
        data["pin"] = pin
        try:
            CONFIG.parent.mkdir(parents=True, exist_ok=True)
            tmp = CONFIG.with_name("." + CONFIG.name + ".tmp")
            tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
            os.chmod(tmp, 0o600)
            os.replace(tmp, CONFIG)
        except OSError:
            pass
    return {"requirePin": data.get("requirePin", True) is not False, "fullScreen": data.get("fullScreen") is True,
            "pin": pin}


def computer_name() -> str:
    try:
        name = subprocess.run(["hostnamectl", "--pretty"], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return name or socket.gethostname() or "CitronOS"


def command(cfg: dict, name: str) -> list[str]:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [UXPLAY, "-n", name, "-nh", "-vs", "waylandsink", "-nohold", "-d", "1",
           "-reg", str(STATE_DIR / "airplay.register")]
    if cfg["requirePin"]:
        cmd += ["-pin", cfg["pin"]]
    if cfg["fullScreen"]:
        cmd += ["-fs"]
    return cmd


class Receiver:
    def __init__(self, cfg: dict, notify=None, clock=time.time):
        self.cfg = cfg
        self.clock = clock
        self.notify = notify or self._notify
        self.state = {"running": True, "connected": False, "device": "", "model": "", "pinPending": False,
                      "pin": "", "since": 0}
        self.pin_since = 0.0

    @staticmethod
    def _notify(title: str, body: str) -> None:
        if shutil.which("notify-send"):
            subprocess.run(["notify-send", "-a", "AirPlay Receiver", "-i", "airplay", title, body],
                           capture_output=True, timeout=10)

    def write(self) -> None:
        tmp = STATUS.with_name("." + STATUS.name + ".tmp")
        try:
            tmp.write_text(json.dumps(self.state), encoding="utf-8")
            os.replace(tmp, STATUS)
        except OSError:
            pass

    def line(self, text: str) -> bool:
        """One line of UxPlay's log; True when the state changed."""
        before = dict(self.state)
        m = REQUEST.search(text)
        if m:
            self.state["device"], self.state["model"] = m.group(1).strip(), m.group(2).strip()
            if self.cfg["requirePin"]:
                self.state["pinPending"], self.state["pin"] = True, self.cfg["pin"]
                self.pin_since = self.clock()
                self.notify("AirPlay Code: " + self.cfg["pin"],
                            "Enter this code on " + (self.state["device"] or "your device") + " to mirror it here.")
        elif PAIRED.search(text):
            self.state["pinPending"], self.state["pin"] = False, ""
        else:
            m = OPEN.search(text)
            if m:
                count = int(m.group(1))
                if count > 0 and not self.state["connected"]:
                    self.state.update(connected=True, pinPending=False, pin="", since=int(self.clock()))
                    self.notify("Screen Mirroring", (self.state["device"] or "A device") + " is mirroring to this computer.")
                elif count == 0:
                    self.state.update(connected=False, device="", model="", pinPending=False, pin="", since=0)
        # A code nobody typed stops showing after a minute.
        if self.state["pinPending"] and self.clock() - self.pin_since > 60:
            self.state["pinPending"], self.state["pin"] = False, ""
        return self.state != before


def main() -> int:
    cfg = settings()
    receiver = Receiver(cfg)
    receiver.write()
    try:
        proc = subprocess.Popen(command(cfg, computer_name()), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors="replace", bufsize=1)
    except FileNotFoundError:
        receiver.state["running"] = False
        receiver.write()
        print("uxplay isn't installed", file=sys.stderr)
        return 1

    def stop(*_):
        proc.terminate()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        for text in proc.stdout:
            if receiver.line(text):
                receiver.write()
                # Only what matters reaches the journal (UxPlay's debug log is long).
                print(json.dumps(receiver.state), flush=True)
    finally:
        proc.wait()
        receiver.state.update(running=False, connected=False, device="", model="", pinPending=False, pin="")
        receiver.write()
    return proc.returncode or 0


if __name__ == "__main__":
    raise SystemExit(main())
