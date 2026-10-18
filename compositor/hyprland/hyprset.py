#!/usr/bin/env python3
"""gg-hyprset: change Hyprland settings in the running session, now.

Hyprland's Lua config (0.55+) has no `hyprctl keyword`; this turns the
settings CitronOS changes live into one `hyprctl eval` of hl.config() and
hl.monitor() calls. What is saved for the next login is written separately
(golden-gate/*.lua, by set-prefs.py and the Displays pane).

    gg-hyprset KEY VALUE [KEY VALUE ...]   e.g. input:kb_layout us  input:touchpad:tap-to-click true
    gg-hyprset --monitor RULE [RULE ...]   e.g. eDP-1,2560x1600@60,0x0,1.6  (the hyprland.conf form)
    gg-hyprset --print ...                 print the Lua instead of running it

KEY is a dotted or colon path (input.kb_layout = input:kb_layout); the old
hyprlang spellings with dashes (tap-to-click) are accepted. VALUE true/false
and numbers are written as such, anything else as a string. Exits with
hyprctl's status, and prints its error if it refused."""
from __future__ import annotations

import re
import subprocess
import sys

KEY = re.compile(r"[a-z][a-z0-9_.:-]{0,95}$")


def lua_value(raw: str) -> str:
    if raw in ("true", "false"):
        return raw
    if re.fullmatch(r"-?(\d+\.?\d*|\.\d+)", raw):
        return raw
    return '"' + raw.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_table(tree: dict, indent: str = "") -> str:
    parts = []
    for k, v in tree.items():
        val = lua_table(v, indent) if isinstance(v, dict) else v
        parts.append(f"{k} = {val}")
    return "{ " + ", ".join(parts) + " }"


def config_call(pairs: list[tuple[str, str]]) -> str:
    tree: dict = {}
    for key, raw in pairs:
        if not KEY.match(key):
            raise ValueError(f"not a setting: {key}")
        path = [p.replace("-", "_") for p in re.split(r"[.:]", key) if p]
        node = tree
        for p in path[:-1]:
            node = node.setdefault(p, {})
            if not isinstance(node, dict):
                raise ValueError(f"{key} is inside another setting")
        node[path[-1]] = lua_value(raw)
    return f"hl.config({lua_table(tree)})"


def monitor_call(rule: str) -> str:
    """name,mode,position,scale[,extra key,value ...] → hl.monitor({...})."""
    fields = [f.strip() for f in rule.split(",")]
    if not fields or not fields[0] and len(fields) < 2:
        raise ValueError(f"not a monitor rule: {rule}")
    if len(fields) >= 2 and fields[1] == "disable":
        return f"hl.monitor({{ output = {lua_value(fields[0])}, disabled = true }})"
    spec = {"output": lua_value(fields[0])}
    for name, value in zip(("mode", "position", "scale"), fields[1:4]):
        if value:
            spec[name] = lua_value(value) if name != "scale" or not re.fullmatch(r"[\d.]+", value) else value
    extra = fields[4:]
    for i in range(0, len(extra) - 1, 2):
        k = extra[i].replace("-", "_")
        if re.fullmatch(r"[a-z_]+", k):
            spec[k] = lua_value(extra[i + 1])
    return "hl.monitor(" + lua_table(spec) + ")"


def build(argv: list[str]) -> str:
    if argv and argv[0] == "--monitor":
        if len(argv) < 2:
            raise ValueError("--monitor needs a rule")
        return "\n".join(monitor_call(r) for r in argv[1:])
    if not argv or len(argv) % 2:
        raise ValueError("expected KEY VALUE pairs")
    return config_call(list(zip(argv[::2], argv[1::2])))


def main(argv: list[str]) -> int:
    show = bool(argv) and argv[0] == "--print"
    if show:
        argv = argv[1:]
    try:
        code = build(argv)
    except ValueError as exc:
        print(f"gg-hyprset: {exc}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 2
    if show:
        print(code)
        return 0
    try:
        p = subprocess.run(["hyprctl", "eval", code], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"gg-hyprset: hyprctl: {exc}", file=sys.stderr)
        return 1
    out = (p.stdout + p.stderr).strip()
    if p.returncode != 0 or (out and not out.startswith("ok")):
        print(out or f"hyprctl exited {p.returncode}", file=sys.stderr)
        return p.returncode or 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
