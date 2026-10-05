#!/usr/bin/env python3
"""Atomically update one nested CitronOS desktop preference."""
from __future__ import annotations
import json
import os
import pathlib
import sys
import tempfile

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

try:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

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
