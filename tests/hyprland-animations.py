#!/usr/bin/env python3
"""Every `animation =` line the system ships names a style Hyprland accepts for
that animation. An unknown one isn't caught until Hyprland loads the config
("unknown style"), which the boot test reports as a config error. Windows take
slide, popin or gnomed; layers slide, popin or fade; workspaces slide,
slidevert, fade, slidefade or slidefadevert; the rest take no style."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    "compositor/hyprland/hyprland.conf",
    "compositor/hyprland/machine-conf.sh",
    "design/dist/hyprland-motion.conf",
    "design/build.mjs",
]
STYLES = {
    "windows": {"slide", "popin", "gnomed"},
    "layers": {"slide", "popin", "fade"},
    "workspaces": {"slide", "slidevert", "fade", "slidefade", "slidefadevert"},
}
LINE = re.compile(r"animation\s*=\s*([A-Za-z]+)\s*,\s*([^,]+),\s*([^,]+),\s*([^,`\"']+)(?:,\s*([^`\"'\n]+))?")


def family(name):
    for f in ("windows", "layers"):
        if name.startswith(f):
            return f
    if name.startswith("workspaces") or name.startswith("specialWorkspace"):
        return "workspaces"
    return None


def main():
    failures, seen = [], 0
    for rel in FILES:
        path = ROOT / rel
        if not path.exists():
            continue
        for n, line in enumerate(path.read_text().splitlines(), 1):
            m = LINE.search(line)
            if not m:
                continue
            seen += 1
            name, style = m.group(1), (m.group(5) or "").strip()
            if not style:
                continue
            word = style.split()[0]
            allowed = STYLES.get(family(name))
            if allowed is None:
                failures.append(f"{rel}:{n}: {name} takes no style, given {style!r}")
            elif word not in allowed:
                failures.append(f"{rel}:{n}: {name} style {word!r} is not one of {sorted(allowed)}")
    for f in failures:
        print("FAIL", f, file=sys.stderr)
    if not failures:
        print(f"Hyprland animations: {seen} lines, every style one Hyprland knows")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
