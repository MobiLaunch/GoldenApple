#!/usr/bin/env python3
"""Nearby devices for the shell's pairing cards.

Runs short Bluetooth scans through bluetoothctl with an RSSI floor, so BlueZ
only reports devices that are close, and prints one JSON line per device
worth a card:

  {"mac": "...", "name": "AirPods Pro", "kind": "headphones", "paired": false,
   "connected": false, "rssi": -48, "model": "AirPods Pro"}
  {"kind": "phone", "name": "iPhone", ...}

Headphones are recognised by their Bluetooth class (bluetoothctl's Icon) or,
for AirPods, by Apple's proximity-pairing advertisement (manufacturer 0x004C,
type 0x07) whose model field names them. An iPhone shows up through Apple's
Nearby Info advertisement (type 0x10); its address changes every few minutes,
so the shell treats every iPhone as one.

Scanning is duty-cycled (8 s of every 20) to spare the radio, and pauses while
the shell says so (stdin: "pause" / "resume"), e.g. while audio plays over
Bluetooth. GG_NEARBY_FAKE replays a file of bluetoothctl output (tests).
"""
from __future__ import annotations

import json
import os
import re
import select
import subprocess
import sys
import time

RSSI_FLOOR = int(os.environ.get("GG_NEARBY_RSSI", "-60"))
SCAN_ON, SCAN_OFF = 8.0, 12.0
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x01|\x02")
MAC = r"([0-9A-F]{2}(?::[0-9A-F]{2}){5})"

# Apple proximity-pairing model numbers (bytes 3-4 of a type 0x07 message).
AIRPODS = {
    "0220": "AirPods", "0f20": "AirPods", "1320": "AirPods", "1920": "AirPods", "1b20": "AirPods",
    "0e20": "AirPods Pro", "1420": "AirPods Pro", "2420": "AirPods Pro",
    "0a20": "AirPods Max", "1f20": "AirPods Max",
    "0320": "Powerbeats", "0b20": "Powerbeats Pro", "0c20": "Beats Solo Pro", "1120": "Beats Studio Buds",
    "1020": "Beats Flex", "0520": "BeatsX", "0620": "Beats Solo³", "0920": "Beats Studio³",
    "1720": "Beats Studio Pro", "1220": "Beats Fit Pro", "1620": "Beats Studio Buds +",
}
HEADPHONE_ICONS = ("audio-headset", "audio-headphones", "audio-card")


def classify(info: dict) -> dict | None:
    """What a device is, from `bluetoothctl info`; None when it isn't one we show."""
    mfr = info.get("mfr", {})
    apple = mfr.get("004c", "")
    if apple.startswith("07") and len(apple) >= 10:
        model = AIRPODS.get(apple[6:10])
        return {"kind": "headphones", "model": model or "Headphones", "apple": True}
    icon = info.get("Icon", "")
    if icon.startswith(HEADPHONE_ICONS):
        return {"kind": "headphones", "model": "", "apple": False}
    if apple.startswith("10") or icon == "phone":
        return {"kind": "phone", "model": "iPhone" if apple else "", "apple": bool(apple)}
    return None


def parse_info(text: str) -> dict:
    info, mfr, key, collecting = {}, {}, None, False
    for raw in text.splitlines():
        line = ANSI.sub("", raw).strip()
        if not line:
            continue
        m = re.match(r"ManufacturerData\.?Key:\s*0x([0-9a-fA-F]{1,4})", line)
        if m:
            key, collecting = m.group(1).lower().zfill(4), False
            mfr.setdefault(key, "")
            continue
        if line.startswith("ManufacturerData.Value") or line.startswith("ManufacturerData Value"):
            collecting = key is not None
            continue
        if collecting and re.match(r"^([0-9a-fA-F]{2}\s)+", line + " "):
            mfr[key] += "".join(re.findall(r"\b([0-9a-fA-F]{2})\b", line.split("  ")[0])).lower()
            continue
        collecting = False
        k, sep, v = line.partition(": ")
        if sep:
            info[k.strip()] = v.strip()
    info["mfr"] = mfr
    m = re.search(r"\(?(-\d+)\)?$", info.get("RSSI", ""))
    info["rssi"] = int(m.group(1)) if m else None
    return info


def device_info(mac: str) -> dict:
    try:
        out = subprocess.run(["bluetoothctl", "info", mac], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    return parse_info(out)


def emit(mac: str, info: dict, what: dict):
    print(json.dumps({
        "mac": mac, "name": info.get("Name") or info.get("Alias") or what["model"] or "Device",
        "kind": what["kind"], "model": what["model"], "apple": what["apple"],
        "paired": info.get("Paired") == "yes", "connected": info.get("Connected") == "yes",
        "rssi": info.get("rssi"),
    }), flush=True)


def main() -> int:
    fake = os.environ.get("GG_NEARBY_FAKE")
    if fake:
        # A recorded scan, then `bluetoothctl info` dumps keyed by address.
        data = json.load(open(fake))
        for mac, text in data.items():
            info = parse_info(text)
            what = classify(info)
            if what and (info["rssi"] is None or info["rssi"] >= RSSI_FLOOR):
                emit(mac, info, what)
        time.sleep(float(os.environ.get("GG_NEARBY_LINGER", "0")))
        return 0

    try:
        ctl = subprocess.Popen(["bluetoothctl"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True, bufsize=1)
    except OSError:
        return 1

    def say(cmd):
        try:
            ctl.stdin.write(cmd + "\n")
            ctl.stdin.flush()
        except (OSError, ValueError):
            pass

    # Only devices this close are reported at all.
    for cmd in ("menu scan", "clear", f"rssi {RSSI_FLOOR}", "duplicate-data on", "back"):
        say(cmd)
    paused, scanning = False, False
    next_switch = time.time()
    last_seen: dict[str, float] = {}
    while ctl.poll() is None:
        now = time.time()
        if not paused and now >= next_switch:
            scanning = not scanning
            say("scan on" if scanning else "scan off")
            next_switch = now + (SCAN_ON if scanning else SCAN_OFF)
        # Asleep until bluetoothctl or the shell says something, or the next
        # switch of scanning on or off; paused, until then only.
        wait = None if paused else max(0.05, next_switch - time.time())
        ready, _, _ = select.select([ctl.stdout, sys.stdin], [], [], wait)
        if sys.stdin in ready:
            cmd = sys.stdin.readline().strip()
            if not cmd:
                break
            if cmd == "pause" and not paused:
                paused = True
                if scanning:
                    say("scan off")
                    scanning = False
            elif cmd == "resume" and paused:
                paused, next_switch = False, time.time()
        if ctl.stdout in ready:
            line = ANSI.sub("", ctl.stdout.readline())
            m = re.search(r"\[(NEW|CHG)\] Device " + MAC + r"(?: (RSSI|ManufacturerData)|\s|$)", line)
            if not m:
                continue
            mac = m.group(2)
            # One look per device per minute is plenty.
            if now - last_seen.get(mac, 0) < 60:
                continue
            last_seen[mac] = now
            info = device_info(mac)
            what = classify(info)
            if what and (info.get("rssi") is None or info["rssi"] >= RSSI_FLOOR):
                emit(mac, info, what)
    say("scan off")
    return 0


if __name__ == "__main__":
    sys.exit(main())
