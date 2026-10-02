#!/usr/bin/env python3
"""Safety regression for the Golden Gate graphical installer backend."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
helper = root / "apps" / "installer" / "helper.py"
source = helper.read_text(encoding="utf-8")

for needle in [
    'Path("/run/archiso")',
    "os.geteuid()",
    '"ERASE:" + device',
    "live_device()",
    'sys.argv[1] == "disks"',
    'sys.argv[1] == "install"',
    "release_device(device)",
    "wait_for_partitions(boot, root)",
    '"--info=progress2"',
    "boot_disk = live_device()",
]:
    if needle not in source:
        raise SystemExit(f"installer safety gate missing: {needle}")

with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    fakebin = td / "bin"
    fakebin.mkdir()
    lsblk = fakebin / "lsblk"
    lsblk.write_text(
        """#!/bin/sh
cat <<'JSON'
{"blockdevices":[
 {"path":"/dev/sda","model":"Internal","size":128000000000,"type":"disk","tran":"sata","rm":false},
 {"path":"/dev/sdb","model":"USB","size":64000000000,"type":"disk","tran":"usb","rm":true},
 {"path":"/dev/loop0","model":"Loop","size":64000000000,"type":"loop","tran":"","rm":false},
 {"path":"/dev/sdc","model":"Tiny","size":8000000000,"type":"disk","tran":"sata","rm":false}
]}
JSON
""",
        encoding="utf-8",
    )
    lsblk.chmod(0o755)
    env = os.environ.copy()
    env["PATH"] = str(fakebin) + os.pathsep + env.get("PATH", "")

    out = subprocess.check_output([sys.executable, str(helper), "disks"], text=True, env=env)
    rows = json.loads(out)
    if [r["path"] for r in rows] != ["/dev/sda"]:
        raise SystemExit(f"disk discovery safety filter failed: {rows!r}")

# Target preparation must actively release stale mounts/swap instead of
# relying on the destination already being idle.
if 'run(["swapoff", path], check=False)' not in source:
    raise SystemExit("installer no longer deactivates target swap")
if 'run(["umount", "-R", mountpoint], check=False)' not in source:
    raise SystemExit("installer no longer unmounts target filesystems")

# CI is not an ArchISO session. An install request must therefore fail before
# device validation or any destructive utility can run.
proc = subprocess.run(
    [sys.executable, str(helper), "install"],
    input=json.dumps({
        "device": "/dev/sda",
        "username": "tester",
        "password": "correct-horse",
        "confirm": "ERASE:/dev/sda",
    }),
    text=True,
    capture_output=True,
)
if proc.returncode == 0 or "live environment" not in proc.stdout:
    raise SystemExit("installer did not reject destructive operation outside live media")

print("Installer safety: discovery is read-only and install is gated by live/root/exact erase confirmation")
