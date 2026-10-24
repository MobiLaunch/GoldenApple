#!/usr/bin/env python3
"""Liquid Glass drawn the way a real desktop draws it, with OpenGL (the
preview's software renderer skips shader effects, and once hid a solid white
panel under every pane of glass). Each role is drawn over a dark backdrop:
the glass must stay see-through, and its shadow must fall only outside it,
under the compositor's glass threshold.

Runs under xvfb-run with Mesa; skips without them (CI fails instead)."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ROLES = ["clear", "regular", "menu", "control", "sidebar", "dock"]

QML = """import QtQuick
import "file://%s/apps/lib" as L
import "file://%s/apps/lib/theme"
Rectangle {
    width: 120 * %d + 40; height: 200; color: "%s"
    Component.onCompleted: Theme.dark = %s
    Row { x: 30; y: 50; spacing: 30
        Repeater { model: %s
            L.Glass { width: 90; height: 90; radius: 26; role: modelData } } }
}
"""

RENDER = """import sys
from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
app = QGuiApplication(sys.argv)
v = QQuickView(); v.setSource(QUrl.fromLocalFile(sys.argv[1]))
if v.status() != QQuickView.Ready:
    print([e.toString() for e in v.errors()], file=sys.stderr); sys.exit(2)
v.show()
def grab():
    v.grabWindow().save(sys.argv[2]); print(v.rendererInterface().graphicsApi().name); app.quit()
QTimer.singleShot(700, grab)
app.exec()
"""


def render(tmp: Path, background: str, dark: bool) -> tuple[str, Path]:
    qml = tmp / f"glass-{background[1:]}-{dark}.qml"
    qml.write_text(QML % (ROOT, ROOT, len(ROLES), background, "true" if dark else "false", ROLES))
    script = tmp / "render.py"
    script.write_text(RENDER)
    out = tmp / (qml.stem + ".png")
    env = dict(os.environ, QT_QPA_PLATFORM="xcb", QSG_RHI_BACKEND="opengl", LIBGL_ALWAYS_SOFTWARE="1")
    env.pop("QT_QUICK_BACKEND", None)
    proc = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 1000x400x24 +extension GLX",
                           sys.executable, str(script), str(qml), str(out)],
                          capture_output=True, text=True, timeout=120, env=env)
    if proc.returncode != 0:
        raise SystemExit(f"render failed: {proc.stderr[-600:]}")
    return proc.stdout.strip().splitlines()[-1], out


def main() -> int:
    if not shutil.which("xvfb-run"):
        if os.environ.get("CI"):
            print("FAIL xvfb-run is needed to draw glass with OpenGL", file=sys.stderr)
            return 1
        print("skipped: no xvfb-run")
        return 0
    from PySide6.QtGui import QImage
    failures = []
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for dark in (False, True):
            api, path = render(tmp, "#101418", dark)
            if api != "OpenGL":
                if os.environ.get("CI"):
                    print(f"FAIL drawn with {api}, not OpenGL (is Mesa installed?)", file=sys.stderr)
                    return 1
                print(f"skipped: drawn with {api}, not OpenGL")
                return 0
            img = QImage(str(path))
            _, white = render(tmp, "#ffffff", dark)
            on_white = QImage(str(white))
            for i, role in enumerate(ROLES):
                x0, cx = 30 + i * 120, 30 + i * 120 + 45
                centre = img.pixelColor(cx, 95)
                # Over a near-black backdrop, see-through glass stays short of white
                # (the bug drew 248-255; the most solid role, control, is 86% white).
                if centre.lightness() > 238:
                    failures.append(f"{role} ({'dark' if dark else 'light'}): opaque, the centre is {centre.name()}")
                # Below the glass: shadow only, and lighter than the compositor's 25% line.
                for y in (145, 150, 160):
                    a = 1 - on_white.pixelColor(cx, y).redF()
                    if a >= 0.25:
                        failures.append(f"{role}: its shadow is {a:.2f} opaque {y - 140} px below it")
    if failures:
        print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
        return 1
    print("Glass (OpenGL): every role see-through in light and dark, its shadow outside it and under the glass threshold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
