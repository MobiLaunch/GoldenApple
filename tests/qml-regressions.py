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

for forbidden in ("dockMagnification", "dockMagnifiedSize", "pointerTargetX", "sizeAt(", "offsetAt("):
    if forbidden in dock:
        errors.append(f"shell/Dock.qml: removed magnification path reintroduced: {forbidden}")

control_center = (root / "shell" / "ControlCenter.qml").read_text(encoding="utf-8")
for required in ("Big Sur-inspired Control Center", 'id: panel', 'title: "Display"', 'title: "Sound"'):
    if required not in control_center:
        errors.append(f"shell/ControlCenter.qml: Big Sur control surface missing {required!r}")
if 'tint: Theme.dark ? "#7021262e" : "#5f343941"' not in dock:
    errors.append("shell/Dock.qml: smoked real-hardware Dock material was removed")

prefs = (root / "shell" / "components" / "Prefs.qml").read_text(encoding="utf-8")
for forbidden in ("dockMagnification", "dockMagnifiedSize", "magnifiedSize"):
    if forbidden in prefs:
        errors.append(f"shell/components/Prefs.qml: removed Dock magnification preference reintroduced: {forbidden}")

browser = (root / "apps" / "browser" / "Browser.qml").read_text(encoding="utf-8")
browser_ids = re.findall(r"\bid:\s*([A-Za-z_]\w*)", browser)
for qml_id in sorted(set(browser_ids)):
    if browser_ids.count(qml_id) > 1:
        errors.append(f"apps/browser/Browser.qml: duplicate QML id {qml_id!r}")
for function in ("openTabGroup", "saveCurrentTabGroup", "createProfile", "reorderTab"):
    count = len(re.findall(r"\bfunction\s+" + re.escape(function) + r"\s*\(", browser))
    if count != 1:
        errors.append(f"apps/browser/Browser.qml: expected one {function}() implementation, found {count}")
for needle in (
    "BrowserBackend.attachProfile(profile)",
    "QWebEngineUrlRequestInterceptor",
    "DragHandler",
):
    target = browser if needle != "QWebEngineUrlRequestInterceptor" else (root / "apps" / "browser" / "backend.py").read_text(encoding="utf-8")
    if needle not in target:
        errors.append(f"browser architecture guard missing {needle!r}")
if re.search(r"id:\s*tabArea[\\s\\S]{0,160}z:\s*-1", browser):
    errors.append("apps/browser/Browser.qml: tab click surface was moved behind its contents")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print("QML regressions: no obsolete DesktopEntries imports or known parser traps")
