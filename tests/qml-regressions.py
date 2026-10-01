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

# Applications.qml is a PanelWindow/QWindow. Do not shadow inherited
# show()/hide() methods: doing so can leave the layer surface visible while the
# launcher's own open state remains false (transparent and non-interactive).
applications = (root / "shell" / "Applications.qml").read_text(encoding="utf-8")
for forbidden in ("function show()", "function hide()"):
    if forbidden in applications:
        errors.append(f"shell/Applications.qml: shadows inherited QWindow method {forbidden}")

# Dock hover geometry must remain stable. Moving/resizing the HoverHandler item
# on entry changes its local pointer coordinates and produces a one-frame jump.
dock = (root / "shell" / "Dock.qml").read_text(encoding="utf-8")
for forbidden in ("x: hover.hovered ?", "width: hover.hovered", "y: hover.hovered ?"):
    if forbidden in dock:
        errors.append(f"shell/Dock.qml: hover-dependent hitbox geometry reintroduced: {forbidden}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print("QML regressions: no obsolete DesktopEntries imports or known parser traps")
