#!/usr/bin/env python3
"""Move Theme.fs(n) calls onto the Theme.font roles (T-2.10; CS2-043).

    python3 tools/migrate-fs.py [--check] [FILE…]   # default: every QML file in shell/, apps/, themes/

Each Theme.fs(n) whose n is on the type ramp becomes Theme.font.<role>.pixelSize,
which is fs() of the same size, so it renders exactly as before. The map is
here, for review:
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The macOS ramp (design/tokens.json font.size). 8 and 9 already render at the
# 10 px floor, so they're footnotes too; other sizes (14, 16, 18, 20 …) are off
# the ramp and are left for a person to choose.
MAP = {
    8: "footnote", 9: "footnote", 10: "footnote",
    11: "subheadline", 12: "callout", 13: "body",
    15: "title3", 17: "title2", 22: "title1", 26: "largeTitle",
}
CALL = re.compile(r"\bTheme\.fs\(\s*(\d+)\s*\)")


def migrate(text: str) -> tuple[str, int]:
    count = 0

    def swap(m: re.Match) -> str:
        nonlocal count
        role = MAP.get(int(m.group(1)))
        if not role:
            return m.group(0)
        count += 1
        return f"Theme.font.{role}.pixelSize"

    return CALL.sub(swap, text), count


def main() -> int:
    check = "--check" in sys.argv
    files = [Path(a) for a in sys.argv[1:] if not a.startswith("--")] or \
        [p for d in ("shell", "apps", "themes") for p in sorted((ROOT / d).rglob("*.qml")) if "theme" not in p.parts]
    total = 0
    for path in files:
        text = path.read_text()
        new, n = migrate(text)
        if n:
            total += n
            if not check:
                path.write_text(new)
    print(f"{'would move' if check else 'moved'} {total} Theme.fs() calls onto Theme.font roles")
    return 1 if check and total else 0


if __name__ == "__main__":
    raise SystemExit(main())
