#!/usr/bin/env python3
"""gg-hyprctl: hyprctl's dispatch and keyword, for whichever Hyprland
CitronOS runs on (T-2.3).

Hyprland 0.56 reading hyprland.conf takes them as they are. In Lua mode
(0.57 and later read only Lua), hyprctl dispatch takes a Lua dispatcher and
keyword is gone: there the line goes through CitronOS's reader
(compositor/hyprland/hyprlang.lua, loaded as `citronos` by hyprland.lua),
with hyprctl eval, and does what it did.

    gg-hyprctl dispatch workspace 2
    gg-hyprctl keyword input:kb_layout de
    gg-hyprctl --batch "keyword monitor DP-1, preferred, auto, 1 ; dispatch fullscreen 1"
    gg-hyprctl mode                 # lua, or hyprlang

Anything else goes to hyprctl as it is. The mode is asked of Hyprland once
per session and kept in $XDG_RUNTIME_DIR."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def lua_string(s: str) -> str:
    """s as a Lua long string, whatever it holds: its brackets are the ones
    s doesn't close ("[==[…]==]")."""
    eq = ""
    while f"]{eq}]" in s or s.endswith("]" + eq):
        eq += "="
    return f"[{eq}[{s}]{eq}]"


def hyprctl(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5)


def _cache() -> Path | None:
    runtime, instance = os.environ.get("XDG_RUNTIME_DIR"), os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not (runtime and instance) or "/" in instance:
        return None
    return Path(runtime) / f"gg-hyprctl-mode-{instance}"


def mode() -> str:
    """"lua" when Hyprland runs a Lua configuration, else "hyprlang"."""
    cache = _cache()
    try:
        if cache and cache.read_text().strip() in ("lua", "hyprlang"):
            return cache.read_text().strip()
    except OSError:
        pass
    try:
        proc = hyprctl("eval", "return 1")
    except (OSError, subprocess.SubprocessError):
        return "hyprlang"
    out = proc.stdout.strip()
    if proc.returncode != 0 or not out:
        return "hyprlang"                        # no Hyprland to ask: not kept
    found = "lua" if out.startswith("ok") else "hyprlang"
    if cache:
        try:
            cache.write_text(found + "\n")
        except OSError:
            pass
    return found


def to_lua(command: str) -> str | None:
    """"dispatch workspace 2" / "keyword input:kb_layout de" as Lua for the
    reader; None for anything else."""
    verb, _, rest = command.strip().partition(" ")
    rest = rest.strip()
    if verb == "dispatch":
        return f"citronos.dispatch({lua_string(rest)})"
    if verb == "keyword":
        key, _, value = rest.partition(" ")
        return f"citronos.keyword({lua_string(key)}, {lua_string(value.strip())})"
    return None


def main(argv: list[str]) -> int:
    if argv[:1] == ["mode"]:
        print(mode())
        return 0
    if argv[:1] in (["dispatch"], ["keyword"]):
        commands = [" ".join(argv)]
    elif argv[:1] == ["--batch"] and len(argv) == 2:
        commands = [c for c in argv[1].split(";") if c.strip()]
    else:
        os.execvp("hyprctl", ["hyprctl", *argv])
    if mode() != "lua":
        os.execvp("hyprctl", ["hyprctl", *argv])
    code, lua = 0, []
    for command in commands:
        statement = to_lua(command)
        if statement is not None:
            lua.append(statement)
            continue
        # Not dispatch or keyword (reload, …): hyprctl takes it as it is.
        proc = hyprctl(*command.split())
        sys.stdout.write(proc.stdout)
        code = code or proc.returncode
    if lua:
        proc = hyprctl("eval", "; ".join(lua))
        out = proc.stdout.strip() or proc.stderr.strip()
        print(out)
        if proc.returncode != 0 or not out.startswith("ok"):
            code = 1
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
