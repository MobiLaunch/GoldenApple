#!/usr/bin/env python3
"""Ensure every literal CitronOS symbol reference exists in icons/source.mjs."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
source = (root / "icons/source.mjs").read_text(encoding="utf-8")
symbol_source = source.split("export const apps", 1)[0]
keys = {
    a or b
    for a, b in re.findall(
        r'^\s{2}(?:"([^"]+)"|([A-Za-z][A-Za-z0-9_-]*))\s*:',
        symbol_source,
        flags=re.M,
    )
}

errors: list[str] = []
qml_files = sorted(
    p
    for folder in ("apps", "shell")
    for p in (root / folder).rglob("*.qml")
)

for path in qml_files:
    text = path.read_text(encoding="utf-8")
    refs = set(re.findall(r'\b(?:symbol|headerSymbol)\s*:\s*"([^"]+)"', text))
    refs.update(
        re.findall(
            r'Symbol\s*\{[\s\S]{0,360}?\bname\s*:\s*"([^"]+)"',
            text,
        )
    )
    for ref in sorted(refs - keys):
        errors.append(f"{path.relative_to(root)} references missing symbol {ref!r}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print(f"Symbol integrity: {len(qml_files)} QML files reference generated symbols only")
