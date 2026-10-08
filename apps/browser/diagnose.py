"""Why Qt WebEngine won't load, in words, for when `import PySide6.QtWebEngine…`
fails. PySide only says "libshiboken: could not import module
'PySide6.QtWebEngineCore'", which hides the reason. This loads the module's
library directly (no Qt import, so it works exactly when Qt is broken) and
looks at what's installed, then says what's wrong and what fixes it.

    summary, details = diagnose()
"""
from __future__ import annotations

import ctypes
import glob
import importlib.util
import os
import re
import site
import subprocess


def _versions() -> dict[str, str]:
    try:
        out = subprocess.run(["pacman", "-Q", "pyside6", "shiboken6", "qt6-base", "qt6-webengine"],
                             capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    found = {}
    for line in out.splitlines():
        name, _, version = line.partition(" ")
        if version:
            found[name] = version
    return found


def _minor(version: str) -> str:
    m = re.match(r"(?:\d+:)?(\d+\.\d+)", version)
    return m.group(1) if m else ""


def diagnose(pyside_dir: str | None = None, versions: dict[str, str] | None = None) -> tuple[str, list[str]]:
    details: list[str] = []
    if pyside_dir is None:
        spec = importlib.util.find_spec("PySide6")
        pyside_dir = os.path.dirname(spec.origin) if spec and spec.origin else ""
    if not pyside_dir or not os.path.isdir(pyside_dir):
        return ("PySide6 isn't installed, so Web can't start. Install it with: sudo pacman -S pyside6 qt6-webengine",
                ["PySide6 not found"])
    details.append("PySide6: " + pyside_dir)
    if versions is None:
        versions = _versions()
    if versions:
        details.append("packages: " + ", ".join(f"{k} {v}" for k, v in versions.items()))

    # A PySide6 installed with pip for this user shadows the system's (it's
    # first on the path) and brings its own Qt that no longer matches.
    user_site = site.getusersitepackages() if hasattr(site, "getusersitepackages") else ""
    home = os.path.expanduser("~")
    if (user_site and pyside_dir.startswith(user_site)) or (pyside_dir.startswith(home + os.sep) and "site-packages" in pyside_dir):
        return ("A copy of PySide6 installed with pip in your home folder is hiding CitronOS's own, and its Qt doesn't "
                "match the system. Remove it: pip uninstall --break-system-packages PySide6 PySide6-Essentials "
                "PySide6-Addons shiboken6 (or delete " + os.path.dirname(pyside_dir) + "/PySide6*)", details)

    if "qt6-webengine" not in versions and versions:
        return ("Qt WebEngine isn't installed, so Web can't start. Install it with: sudo pacman -S qt6-webengine", details)

    libs = sorted(glob.glob(os.path.join(pyside_dir, "QtWebEngineCore*.so")))
    if not libs:
        return ("PySide6's Web Engine part is missing, so Web can't start. Install it with: sudo pacman -S qt6-webengine pyside6",
                details)
    error = ""
    try:
        ctypes.CDLL(libs[0], mode=os.RTLD_NOW | os.RTLD_GLOBAL)
    except OSError as exc:
        error = str(exc)
        details.append("loading " + os.path.basename(libs[0]) + ": " + error)

    py, qt = _minor(versions.get("pyside6", "")), _minor(versions.get("qt6-base", ""))
    web = _minor(versions.get("qt6-webengine", ""))
    mismatch = [f"{n} {v}" for n, v in (("PySide6", py), ("Qt WebEngine", web)) if v and qt and v != qt]
    missing = re.search(r"(lib[\w.+-]+\.so[\w.]*): cannot open shared object file", error)
    if missing:
        return (f"Web can't start: the library {missing.group(1)} is missing. Run Software Update (or sudo pacman -Syu); "
                f"if it's still missing, sudo pacman -S qt6-webengine pyside6.", details)
    if "undefined symbol" in error or "version `" in error or mismatch:
        what = ("PySide6 and Qt are different versions (" + ", ".join(mismatch) + f", Qt {qt})") if mismatch \
            else "PySide6 was built for a different Qt than the one installed"
        return (f"Web can't start: {what}. This happens when Qt is updated before PySide6 is rebuilt for it. "
                "Run Software Update (or sudo pacman -Syu) to bring them together.", details)
    if error:
        return ("Web can't start: Qt WebEngine couldn't be loaded (" + error + "). Run Software Update "
                "(or sudo pacman -Syu); if that doesn't help, sudo pacman -S qt6-webengine pyside6.", details)
    return ("Web can't start: Qt WebEngine couldn't be loaded. Run Software Update (or sudo pacman -Syu); if that "
            "doesn't help, sudo pacman -S qt6-webengine pyside6.", details)


if __name__ == "__main__":
    summary, details = diagnose()
    print(summary)
    for line in details:
        print("  " + line)
