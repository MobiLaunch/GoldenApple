#!/usr/bin/env python3
"""When Qt WebEngine won't load, Web says why and what fixes it.

PySide only says "libshiboken: could not import module
'PySide6.QtWebEngineCore'" (what Web's log showed on every launch), and the
notification only pointed at the log. apps/browser/diagnose.py loads the
module's library itself and looks at what's installed. Checked against made-up
installs: no PySide6, a pip copy in the home folder, no qt6-webengine, the
Web Engine part missing, a library that's gone, a symbol PySide6 needs that
this Qt doesn't have, and PySide6 and Qt at different versions. Also that
browser.py and launch.sh carry the reason through to the notification."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/browser"))
from diagnose import diagnose  # noqa: E402

failures: list[str] = []
OK = {"pyside6": "6.12.0-1", "shiboken6": "6.12.0-1", "qt6-base": "6.12.0-1", "qt6-webengine": "6.12.0-1"}


def check(cond: bool, what: str) -> None:
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


def build(dirpath: Path, source: str, *link: str) -> None:
    c = dirpath / "m.c"
    c.write_text(source)
    subprocess.run(["gcc", "-shared", "-fPIC", "-o", str(dirpath / "QtWebEngineCore.abi3.so"), str(c), *link],
                   check=True, capture_output=True)


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    s, _ = diagnose(str(tmp / "nowhere"), OK)
    check("PySide6 isn't installed" in s and "pacman -S pyside6" in s, f"no PySide6: {s}")

    home = Path(os.path.expanduser("~"))
    pip = home / ".local/lib/python3.99/site-packages/PySide6"
    made = not pip.exists()
    pip.mkdir(parents=True, exist_ok=True)
    try:
        s, _ = diagnose(str(pip), OK)
        check("pip" in s and "hiding" in s, f"a pip copy in the home folder: {s}")
    finally:
        if made:
            shutil.rmtree(home / ".local/lib/python3.99")

    plain = tmp / "sys/PySide6"
    plain.mkdir(parents=True)
    s, _ = diagnose(str(plain), {k: v for k, v in OK.items() if k != "qt6-webengine"})
    check("pacman -S qt6-webengine" in s, f"no qt6-webengine: {s}")
    s, _ = diagnose(str(plain), OK)
    check("Web Engine part is missing" in s, f"no QtWebEngineCore module: {s}")

    # A library that's gone: built against one, then the one taken away.
    gone = tmp / "gone/PySide6"
    gone.mkdir(parents=True)
    (gone / "dep.c").write_text("int dep(void) { return 1; }\n")
    subprocess.run(["gcc", "-shared", "-fPIC", "-o", str(gone / "libQt6WebEngineCoreFake.so.6"), str(gone / "dep.c")], check=True)
    build(gone, "int dep(void);\nint f(void) { return dep(); }\n", f"-L{gone}", "-l:libQt6WebEngineCoreFake.so.6")
    (gone / "libQt6WebEngineCoreFake.so.6").unlink()
    s, d = diagnose(str(gone), OK)
    check("libQt6WebEngineCoreFake.so.6 is missing" in s and "pacman -Syu" in s, f"a missing library: {s} {d}")

    # A symbol PySide6 needs that this Qt doesn't have.
    skew = tmp / "skew/PySide6"
    skew.mkdir(parents=True)
    build(skew, "int qt_6_13_only(void);\nint f(void) { return qt_6_13_only(); }\n")
    s, d = diagnose(str(skew), OK)
    check("built for a different Qt" in s and "Software Update" in s, f"an undefined symbol: {s} {d}")

    # Loads, but PySide6 and Qt are different versions.
    fine = tmp / "fine/PySide6"
    fine.mkdir(parents=True)
    build(fine, "int f(void) { return 1; }\n")
    s, _ = diagnose(str(fine), dict(OK, pyside6="6.11.2-1"))
    check("PySide6 6.11" in s and "Qt 6.12" in s and "Software Update" in s, f"PySide6 and Qt at different versions: {s}")

browser = (ROOT / "apps/browser/browser.py").read_text()
check("except ImportError as exc:" in browser and "WEB-CANT-START: " in browser and "SystemExit(3)" in browser,
      "browser.py explains a failed Qt import and exits 3")
from diagnose import qml_failure
check("Quickshell-only" not in qml_failure(['module "Quickshell" is not installed'])
      and "shared interface" in qml_failure(['module "Quickshell" is not installed']),
      "QML diagnosis identifies standalone Quickshell import without leaking file paths")
check("Qt WebEngine QML" in qml_failure(['module "QtWebEngine" is not installed']),
      "QML diagnosis identifies a missing QtWebEngine module")
check("Qt Quick UI" in qml_failure(['module "QtQuick.Controls" is not installed']),
      "QML diagnosis identifies missing Qt Quick modules")
browser = (ROOT / "apps/browser/browser.py").read_text()
check('qml_warnings = []' in browser and 'qml_failure(qml_warnings)' in browser,
      "browser.py records QML load errors for user-facing failure diagnosis")
launch = (ROOT / "apps/browser/launch.sh").read_text()
check('if [ "$status" = 2 ] || [ "$status" = 3 ]' in launch
      and "WEB-CANT-START: " in launch and '"${why:-Details: $log}"' in launch,
      "the notification says why, not only where the log is")

print("Web diagnosis: " + ("all checks passed" if not failures else f"{len(failures)} failed"))
sys.exit(1 if failures else 0)
