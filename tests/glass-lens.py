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
    id: root
    width: 400; height: 200; color: "white"
    Component.onCompleted: Theme.reduceTransparency = %s
    ShaderEffectSource {
        id: texture
        visible: false
        sourceItem: Backdrops.used(texture) ? stripes : null
        live: true
        Component.onCompleted: Backdrops.add(root, stripes, texture)
    }
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
    // Moved once it's drawn, as a layout moves a toolbar's buttons: the glass's
    // own x never changes, so only following its place every frame keeps the
    // lens over what's under it (rather than a miniature of the whole window).
    Item {
        objectName: "holder"
        Glass { objectName: "glass"; x: 100; y: 60; width: 190; height: 80; radius: 24; role: "control"; tint: "transparent" }
    }
}
""" % (root, root, "true" if reduce else "false"))
view.setSource(QUrl.fromLocalFile(str(fixture)))
if view.status() != QQuickView.Ready:
    print("\n".join(e.toString() for e in view.errors()), file=sys.stderr)
    sys.exit(2)
view.resize(400, 200)
view.show()
QTest.qWait(400)
from PySide6.QtCore import QObject
view.rootObject().findChild(QObject, "holder").setProperty("x", 10)
QTest.qWait(400)
glass = view.rootObject().findChild(QObject, "glass")
print("lensing", glass.property("lensing"))
# Still glass over still content draws nothing more: the window rests.
frames = [0]
view.frameSwapped.connect(lambda: frames.__setitem__(0, frames[0] + 1))
QTest.qWait(1000)
print("idle frames", frames[0])
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
        idle = [int(l.split()[-1]) for l in p.stdout.splitlines() if l.startswith("idle frames")]
        if not idle or idle[0] > 6:
            failures.append(f"still glass lets the window rest: {idle[0] if idle else '?'} frames drawn in a second with nothing moving")
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

        # The glass is at x 110..300 once moved. Outside it the stripes are
        # 10 px wide; under its middle, magnified, they're wider.
        outside = edges(30, 110, 300)
        inside = edges(100, 165, 245)
        widths_out = [b - a for a, b in zip(outside, outside[1:])]
        widths_in = [b - a for a, b in zip(inside, inside[1:])]
        mean = lambda xs: sum(xs) / max(1, len(xs))
        if not widths_in or mean(widths_in) < mean(widths_out) * 1.03:
            failures.append(f"the middle magnifies: stripes {mean(widths_out):.1f} px outside, {mean(widths_in):.1f} under the glass")
        # Near the left edge the bevel bends them: the edges there no longer
        # line up with the ones outside.
        near = edges(100, 112, 128)
        straight = [x for x in outside if 112 < x < 128]
        if near == straight:
            failures.append(f"the edge bends what's under it: {near} vs {straight}")
        # The glass doesn't sample itself: no dark halo of its own fill.
        corner = img.pixelColor(110 + 30, 60 + 40)
        if corner.alpha() < 250:
            failures.append(f"the lens is opaque where content is: {corner.name()}")
        # Under its centre (x 205, the middle of a light stripe) is what's
        # behind it there, not what was behind it before it moved (a dark
        # stripe) nor a shrunken copy of the whole window.
        if dark(205, 100) != dark(205, 30):
            failures.append(f"the lens follows the glass: {img.pixelColor(205, 100).name()} under its centre, {img.pixelColor(205, 30).name()} behind it")
    for f in failures:
        print("FAIL", f, file=sys.stderr)
    if not failures:
        print(f"Glass lens: stripes {mean(widths_out):.1f} px outside, {mean(widths_in):.1f} px magnified under the middle; bent at the edge; none with Reduce Transparency")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
