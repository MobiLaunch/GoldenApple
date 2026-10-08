#!/usr/bin/env python3
"""A shell menu's surface never changes size or place while it's up.

Going from one menu-bar menu to the next reused one popup surface and resized
and moved it while shown. Qt made the surface again and drew before the
compositor had configured it, the compositor dropped the shell for that
("xdg_surface has never been configured"), and Quickshell exited and
restarted. The same happened right-clicking a second Dock icon or another spot
on the desktop. Now a change while a menu is up closes its surface and opens
it again a moment later. Checked through the preview harness: File then Edit
ends with Edit's menu open where Edit opens on its own, and the focus grabs
let go during the reopen instead of closing the menu."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def render(out: Path, *steps: str) -> QImage:
    args = []
    for s in steps:
        args += ["--do", s]
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "-v", *args,
                           "--wait", "500", "-o", str(out)], capture_output=True, text=True, timeout=180, cwd=ROOT)
    bad = [l for l in proc.stderr.splitlines() if "MenuPopup.qml" in l or ("MenuBar.qml" in l and "loop" in l)]
    check(proc.returncode == 0 and out.exists(), f"{out.stem}: preview ran")
    check(not bad, f"{out.stem}: no menu errors {bad[:2]}")
    return QImage(str(out))


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    edit = render(tmp / "edit.png", "menubar.open:Edit")
    switched = render(tmp / "file-then-edit.png", "menubar.open:File", "menubar.open:Edit")
    if not edit.isNull() and not switched.isNull():
        differ = sum(1 for y in range(30, 260, 3) for x in range(0, 700, 3)
                     if abs(edit.pixelColor(x, y).lightness() - switched.pixelColor(x, y).lightness()) > 24)
        check(differ < 60, f"File then Edit leaves Edit's menu open where Edit opens ({differ} pixels differ)")

popup = (ROOT / "shell/components/MenuPopup.qml").read_text()
check("visible: (open || vanish.running) && !reopening" in popup, "the surface goes away while it's put right")
check("onPlaceChanged: if (open && visible) reopen()" in popup, "a move while up reopens it")
check("items: menu.shown" in popup and "shape(items) === shape(shown)" in popup,
      "what's shown is fixed while up; new rows reopen it, refreshed actions don't")
for f in sorted((ROOT / "shell").rglob("*.qml")):
    text = f.read_text()
    for menu in re.findall(r"MenuPopup \{\s*\n\s*id: (\w+)", text):
        grab = re.search(r"windows: \[" + menu + r"\]\s*\n\s*active: (.*)\n\s*onCleared: (.*)", text)
        if grab:
            check(f"!{menu}.reopening" in grab.group(1) and f"!{menu}.reopening" in grab.group(2),
                  f"{f.name} {menu}: its focus grab waits out a reopen")

shell = (ROOT / "shell/shell.qml").read_text()
check("screenshots: screenshotTool" in shell,
      "the menu bar gets the screenshot tool (it bound to itself, so the recording button never showed)")

print("Menu popups: " + ("all checks passed" if not failures else f"{len(failures)} failed"))
sys.exit(1 if failures else 0)
