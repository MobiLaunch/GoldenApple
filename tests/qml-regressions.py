#!/usr/bin/env python3
"""Cheap QML regressions that do not require Qt to be installed."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
errors = []

for folder in ("apps", "shell", "themes", "design/dist"):
    for path in (root / folder).rglob("*.qml"):
        text = path.read_text(encoding="utf-8")
        if "Quickshell.Services.DesktopEntries" in text:
            errors.append(f"{path.relative_to(root)}: DesktopEntries belongs to core Quickshell")
        for lineno, line in enumerate(text.splitlines(), 1):
            if re.search(r"\b(?:anchors|font|border)\s*\{[^}]*\}\s*;", line):
                errors.append(
                    f"{path.relative_to(root)}:{lineno}: grouped QML property must not be followed by ';'"
                )
            if re.search(r"\?\s*[A-Z]\w*\s*\{", line):
                errors.append(
                    f"{path.relative_to(root)}:{lineno}: do not instantiate a QML object inside a JS ternary"
                )

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print("QML regressions: no obsolete DesktopEntries imports or known parser traps")
