#!/usr/bin/env python3
"""Where this computer is, for Maps and Weather ("My Location").

- Only with Location Services on (Settings → Privacy & Security).
- Nearby Wi-Fi networks (nmcli) are looked up in BeaconDB, the open
  successor to Mozilla Location Service, for a position to tens of metres;
  without Wi-Fi it falls back to the network's address (about the city).
- The place's name comes from Photon, the geocoder Maps searches with.
- A result is kept for ten minutes, so opening Weather and Maps together
  asks once.
- A file under $XDG_RUNTIME_DIR/citron-location says an app was given a
  location (until a few seconds after), and the menu bar shows its arrow.

Prints one JSON object:
  {"ok": true, "lat": 37.77, "lon": -122.42, "accuracy": 40, "name": "San Francisco",
   "admin1": "California", "country": "United States", "source": "wifi"}
  {"ok": false, "error": "Location Services are off.", "code": "disabled"}

  locate.py [--app Weather] [--fresh]
GG_LOCATION_FIXTURE="lat,lon,Name" answers without the network (tests).
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request

BEACONDB = "https://api.beacondb.net/v1/geolocate"
PHOTON = "https://photon.komoot.io/reverse"
AGENT = "CitronOS/3.5 (location; https://github.com/MobiLaunch/GoldenApple)"
KEEP = 600


def config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "golden-gate"


def cache_file() -> Path:
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "golden-gate" / "location.json"


def enabled() -> bool:
    try:
        return json.loads((config_dir() / "privacy.json").read_text()).get("location", True) is not False
    except (OSError, ValueError):
        return True


def wifi_networks() -> list[dict]:
    """Access points in range, as BeaconDB wants them (2 or more, or none)."""
    try:
        out = subprocess.run(["nmcli", "-t", "-f", "BSSID,SIGNAL", "device", "wifi", "list", "--rescan", "no"],
                             capture_output=True, text=True, timeout=6).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    aps = []
    for line in out.splitlines():
        # BSSIDs have escaped colons: AA\:BB\:CC\:DD\:EE\:FF:72
        bssid, _, signal = line.replace("\\:", "-").rpartition(":")
        mac = bssid.replace("-", ":").lower()
        if len(mac) == 17 and signal.isdigit():
            aps.append({"macAddress": mac, "signalStrength": int(signal) // 2 - 100})
    return aps if len(aps) >= 2 else []


def post_json(url: str, body: dict, timeout: float = 8) -> dict:
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def get_json(url: str, timeout: float = 8) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def name_of(lat: float, lon: float) -> dict:
    try:
        f = get_json(PHOTON + "?" + urllib.parse.urlencode({"lat": lat, "lon": lon, "lang": "en"}))["features"][0]["properties"]
    except (OSError, ValueError, KeyError, IndexError):
        return {}
    return {"name": f.get("city") or f.get("town") or f.get("village") or f.get("county") or f.get("name") or "",
            "admin1": f.get("state") or "", "country": f.get("country") or ""}


def locate() -> dict:
    fixture = os.environ.get("GG_LOCATION_FIXTURE")
    if fixture:
        lat, lon, name = (fixture.split(",", 2) + ["", "", ""])[:3]
        return {"ok": True, "lat": float(lat), "lon": float(lon), "accuracy": 50, "name": name,
                "admin1": "", "country": "", "source": "fixture"}
    aps = wifi_networks()
    try:
        found = post_json(BEACONDB, {"considerIp": True, "wifiAccessPoints": aps})
        lat, lon = float(found["location"]["lat"]), float(found["location"]["lng"])
    except (OSError, ValueError, KeyError, TypeError):
        return {"ok": False, "error": "Your location couldn't be found. Check the internet connection.", "code": "offline"}
    place = {"ok": True, "lat": round(lat, 5), "lon": round(lon, 5),
             "accuracy": round(float(found.get("accuracy") or 0)), "source": "wifi" if aps else "network"}
    place.update(name_of(lat, lon))
    return place


def main() -> int:
    args = sys.argv[1:]
    app = args[args.index("--app") + 1] if "--app" in args and args.index("--app") + 1 < len(args) else "An app"
    if not enabled():
        print(json.dumps({"ok": False, "error": "Location Services are off. Turn them on in Settings → Privacy & Security.",
                          "code": "disabled"}))
        return 0
    cache = cache_file()
    if "--fresh" not in args and not os.environ.get("GG_LOCATION_FIXTURE"):
        try:
            kept = json.loads(cache.read_text())
            if time.time() - kept.get("at", 0) < KEEP and kept.get("ok"):
                print(json.dumps(kept))
                return 0
        except (OSError, ValueError):
            pass
    # Mark the lookup, for the menu bar's location indicator.
    run = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "citron-location"
    mark = run / f"{os.getpid()}.json"
    try:
        run.mkdir(parents=True, exist_ok=True)
        mark.write_text(json.dumps({"pid": os.getpid(), "app": app, "until": time.time() + 8}))
    except OSError:
        mark = None
    # The mark stays until its time runs out: a lookup takes a second, and
    # the indicator should be seen. The privacy monitor removes it after.
    result = locate()
    if result.get("ok") and not os.environ.get("GG_LOCATION_FIXTURE"):
        try:
            cache.parent.mkdir(parents=True, exist_ok=True)
            cache.write_text(json.dumps(dict(result, at=time.time())))
        except OSError:
            pass
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
