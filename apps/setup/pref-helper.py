#!/usr/bin/env python3
"""Atomically update one nested CitronOS desktop preference."""
from __future__ import annotations
import fcntl
import json
import os
import pathlib
import sys
import tempfile
import time

if len(sys.argv) != 3:
    raise SystemExit("usage: gg-pref dotted.path JSON_VALUE")

key, raw = sys.argv[1], sys.argv[2]
try:
    value = json.loads(raw)
except json.JSONDecodeError:
    value = raw

config = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config"))
directory = config / "golden-gate"
path = directory / "desktop.json"
directory.mkdir(parents=True, exist_ok=True)
# One writer at a time: read, change and replace under the lock, so two
# changes made together (Settings, Control Center, the shell) both stay.
lock = open(directory / ".desktop.json.lock", "a")
fcntl.flock(lock, fcntl.LOCK_EX)

def damaged(why: str, raw: bytes | None):
    """Refuse, and keep a copy of the damaged file for repair (one per content)."""
    kept = ""
    if raw is not None:
        copies = sorted(directory.glob("desktop.json.damaged-*"))
        same = next((c for c in copies if c.read_bytes() == raw), None)
        if same is None:
            same = directory / f"desktop.json.damaged-{time.strftime('%Y%m%d-%H%M%S')}"
            same.write_bytes(raw)
        kept = f"; a copy is in {same.name}"
    raise SystemExit(f"desktop.json can't be used ({why}); it was left as it is{kept}")


# A damaged file is left as it is and the change refused: starting again
# from {} would throw away every other preference on a guess.
raw = None
try:
    raw = path.read_bytes()
    data = json.loads(raw.decode("utf-8"))
except FileNotFoundError:
    data = {}
except OSError as exc:
    damaged(exc.strerror or str(exc), None)
except ValueError as exc:
    damaged(str(exc), raw)
if not isinstance(data, dict):
    damaged("it isn't a set of preferences", raw)

node = data
parts = [p for p in key.split(".") if p]
if not parts:
    raise SystemExit("empty preference path")
for part in parts[:-1]:
    child = node.get(part)
    if not isinstance(child, dict):
        child = {}
        node[part] = child
    node = child
node[parts[-1]] = value

fd, tmp = tempfile.mkstemp(prefix=".desktop.", suffix=".json", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
finally:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
