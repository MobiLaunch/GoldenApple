#!/usr/bin/env python3
"""Turn the hyprland.conf-era parts CitronOS wrote into the Lua ones.

    migrate-fragments.py [DIR]     DIR: ~/.config/hypr/golden-gate (default)

Before Hyprland's Lua config (0.55+), Setup Assistant and Settings wrote
input.conf, accessibility.conf, windows.conf and displays.conf; hyprland.lua
loads input.lua, accessibility.lua, windows.lua and displays.lua instead. For
each old file with no new one beside it, this writes the new one with the same
settings, so an update keeps the keyboard layout, trackpad and display scale.
The old file is left where it is. gg-session runs this before every start of
the desktop; it does nothing once there is nothing to migrate."""
from __future__ import annotations

import os
import pathlib
import re
import sys
import tempfile

PARTS = ("input", "accessibility", "windows", "displays")


def lua_value(raw: str) -> str:
    raw = raw.strip()
    if raw in ("true", "false", "yes", "no", "on", "off"):
        return "true" if raw in ("true", "yes", "on") else "false"
    if re.fullmatch(r"-?(\d+\.?\d*|\.\d+)", raw):
        return raw
    return '"' + raw.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_table(tree: dict) -> str:
    return "{ " + ", ".join(f"{k} = {lua_table(v) if isinstance(v, dict) else v}" for k, v in tree.items()) + " }"


def monitor(rule: str) -> str:
    f = [x.strip() for x in rule.split(",")]
    if len(f) >= 2 and f[1] == "disable":
        return f"hl.monitor({{ output = {lua_value(f[0])}, disabled = true }})"
    spec = {"output": lua_value(f[0])}
    for name, value in zip(("mode", "position", "scale"), f[1:4]):
        if value:
            spec[name] = value if name == "scale" and re.fullmatch(r"[\d.]+", value) else lua_value(value)
    return f"hl.monitor({lua_table(spec)}) -- display {f[0]}"


def convert(text: str) -> str:
    """The settings of a CitronOS-written hyprlang file, as Lua."""
    tree: dict = {}
    stack: list[dict] = [tree]
    monitors: list[str] = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.endswith("{"):
            name = line[:-1].strip().replace("-", "_")
            if not re.fullmatch(r"[a-z_][a-z0-9_]*", name):
                continue
            stack.append(stack[-1].setdefault(name, {}))
            continue
        if line == "}":
            if len(stack) > 1:
                stack.pop()
            continue
        key, sep, value = line.partition("=")
        if not sep:
            continue
        key = key.strip()
        if key == "monitor" and len(stack) == 1:
            monitors.append(monitor(value))
            continue
        path = [p.replace("-", "_") for p in key.split(":") if p]
        if not path or not all(re.fullmatch(r"[a-z_][a-z0-9_.]*", p) for p in path):
            continue
        node = stack[-1]
        for p in path[:-1]:
            node = node.setdefault(p, {})
        node[path[-1]] = lua_value(value)
    lines = ["-- Converted from the hyprland.conf-era file by migrate-fragments.py."]
    if tree:
        lines.append(f"hl.config({lua_table(tree)})")
    lines += monitors
    return "\n".join(lines) + "\n"


def migrate(directory: pathlib.Path) -> list[str]:
    done = []
    for name in PARTS:
        old, new = directory / f"{name}.conf", directory / f"{name}.lua"
        if new.exists() or not old.is_file():
            continue
        try:
            text = old.read_text(encoding="utf-8")
        except OSError:
            continue
        fd, tmp = tempfile.mkstemp(prefix=f".{name}.", suffix=".lua", dir=directory)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(convert(text))
        os.replace(tmp, new)
        done.append(name)
    return done


def main(argv: list[str]) -> int:
    base = pathlib.Path(os.environ.get("XDG_CONFIG_HOME") or pathlib.Path.home() / ".config")
    directory = pathlib.Path(argv[1]) if len(argv) > 1 else base / "hypr/golden-gate"
    if not directory.is_dir():
        return 0
    for name in migrate(directory):
        print(f"migrated {name}.conf to {name}.lua")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
