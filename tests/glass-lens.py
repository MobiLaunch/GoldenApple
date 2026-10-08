#!/usr/bin/env python3
"""Glass over an app's own content bends it, as a thick slab of glass does
(apps/lib/Glass.qml with shaders/glasslens.frag): drawn with OpenGL over a
row of stripes, the stripes under the middle of the glass are magnified
(the dome) and near its edge pulled outward (the bevel), while the glass
never samples itself. With Reduce Transparency, or without a GPU, there is
no lens. Runs under xvfb-run with Mesa; skips without them (CI fails
instead)."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

RENDER = r'''
import sys
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest
root, out, reduce = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
sys.path.insert(0, root + "/tools/preview")
import preview
app = QGuiApplication([])
fake = preview.Preview({"HOME": "/tmp"}, root + "/apps", "'default'")
view = QQuickView()
view.engine().addImportPath(root + "/tools/preview/qml")
view.rootContext().setContextProperty("__preview", fake)
fixture = Path(out).with_suffix(".qml")
fixture.write_text("""import QtQuick
import "file:%s/apps/lib"
import "file:%s/apps/lib/theme"
Rectangle {
    width: 400; height: 200; color: "white"
    Component.onCompleted: Theme.reduceTransparency = %s
    property Item glassBackdrop: stripes
    Item {
        id: stripes
        anchors.fill: parent
        Row {
            Repeater {
                model: 40
                Rectangle { width: 10; height: 200; color: index %% 2 ? "#202020" : "#f0f0f0" }
            }
        }
    }
    Glass { objectName: "glass"; x: 100; y: 60; width: 200; height: 80; radius: 24; role: "control"; tint: "transparent" }
}
""" % (root, root, "true" if reduce else "false"))
view.setSource(QUrl.fromLocalFile(str(fixture)))
if view.status() != QQuickView.Ready:
    print("\n".join(e.toString() for e in view.errors()), file=sys.stderr)
    sys.exit(2)
view.resize(400, 200)
view.show()
QTest.qWait(600)
glass = view.rootObject().findChild(__import__("PySide6.QtCore", fromlist=["QObject"]).QObject, "glass")
print("lensing", glass.property("lensing"))
view.grabWindow().save(out)
'''


def render(tmp, reduce):
    out = tmp / ("reduce.png" if reduce else "lens.png")
    script = tmp / "render.py"
    script.write_text(RENDER)
    env = dict(os.environ, QT_QPA_PLATFORM="xcb", QSG_RHI_BACKEND="opengl", LIBGL_ALWAYS_SOFTWARE="1")
    env.pop("QT_QUICK_BACKEND", None)
    p = subprocess.run(["xvfb-run", "-a", "-s", "-screen 0 600x400x24 +extension GLX", sys.executable, str(script),
                        str(ROOT), str(out), "1" if reduce else "0"], env=env, capture_output=True, text=True, timeout=120)
    return p, out


def main():
    if not shutil.which("xvfb-run"):
        if os.environ.get("CI"):
            print("FAIL xvfb-run is needed to draw the lens with OpenGL", file=sys.stderr)
            return 1
        print("skipped: no xvfb-run")
        return 0
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtGui import QGuiApplication, QImage
    app = QGuiApplication([])
    failures = []
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        p, out = render(t, False)
        if "lensing True" not in p.stdout:
            print(p.stdout, p.stderr[-2000:], file=sys.stderr)
            return 1
        img = QImage(str(out))
        pr, outr = render(t, True)
        if "lensing False" not in pr.stdout:
            failures.append(f"Reduce Transparency: no lens ({pr.stdout.strip()})")
        keep = os.environ.get("GG_KEEP_LENS")
        if keep:
            shutil.copy(out, keep)

        def dark(x, y):
            return img.pixelColor(x, y).lightness() < 128

        def edges(y, x0, x1):
            return [x for x in range(x0 + 1, x1) if dark(x, y) != dark(x - 1, y)]

        # Outside the glass the stripes are 10 px wide; under its middle,
        # magnified, they're wider.
        outside = edges(30, 100, 300)
        inside = edges(100, 160, 240)
        widths_out = [b - a for a, b in zip(outside, outside[1:])]
        widths_in = [b - a for a, b in zip(inside, inside[1:])]
        mean = lambda xs: sum(xs) / max(1, len(xs))
        if not widths_in or mean(widths_in) < mean(widths_out) * 1.03:
            failures.append(f"the middle magnifies: stripes {mean(widths_out):.1f} px outside, {mean(widths_in):.1f} under the glass")
        # Near the left edge the bevel bends them: the edges there no longer
        # line up with the ones outside.
        near = edges(100, 102, 118)
        straight = [x for x in outside if 102 < x < 118]
        if near == straight:
            failures.append(f"the edge bends what's under it: {near} vs {straight}")
        # The glass doesn't sample itself: no dark halo of its own fill.
        corner = img.pixelColor(100 + 30, 60 + 40)
        if corner.alpha() < 250:
            failures.append(f"the lens is opaque where content is: {corner.name()}")
    for f in failures:
        print("FAIL", f, file=sys.stderr)
    if not failures:
        print(f"Glass lens: stripes {mean(widths_out):.1f} px outside, {mean(widths_in):.1f} px magnified under the middle; bent at the edge; none with Reduce Transparency")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
