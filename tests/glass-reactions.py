#!/usr/bin/env python3
"""Liquid Glass reacts as a piece of glass does (apps/lib/Glass.qml): a soft
light follows the pointer across it and its rim brightens; under the
pointer a control lifts a pixel, and pressed it gives a few and lifts no
more. The light stays off with Reduce Transparency, the lift with Reduce
Motion. The rim stays bright all the way round (its darkest stretch is at
least a third of its brightest), and glass big enough to have a thickness
shows its inner face."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import re
import sys
import tempfile
import unittest

from PySide6.QtCore import QObject, QPoint, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Reactions(unittest.TestCase):
    def setUp(self):
        self.view = QQuickView()
        self.fake = preview.Preview({"HOME": tempfile.mkdtemp()}, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        self.view.setSource(QUrl.fromLocalFile(str(self.fixture())))
        self.assertEqual(self.view.status(), QQuickView.Ready, [e.toString() for e in self.view.errors()])
        self.view.resize(400, 300)
        self.view.show()
        QTest.qWait(100)
        self.glass = self.view.rootObject().findChild(QObject, "glass")

    def set_theme(self, key, value):
        root = self.view.rootObject()
        QQmlExpression(self.view.engine().rootContext(), root, f"setTheme({key!r}, {str(value).lower()})").evaluate()

    def fixture(self):
        f = ROOT / "tests" / "GlassFixture.qml"
        f.write_text('import QtQuick\nimport "../apps/lib"\nimport "../apps/lib/theme"\n'
                     'Rectangle { width: 400; height: 300; color: "#3366cc"\n'
                     '  function setTheme(k, v) { Theme[k] = v }\n'
                     '  Glass { objectName: "glass"; x: 50; y: 50; width: 300; height: 200; role: "regular" } }\n')
        self.addCleanup(f.unlink)
        return f

    def eval(self, expr):
        v = QQmlExpression(self.view.engine().rootContext(), self.glass, expr).evaluate()[0]
        return v.toVariant() if hasattr(v, "toVariant") else v

    def light(self, what="opacity"):
        # The pointer light: the Shape whose radial gradient follows the pointer.
        return self.eval("(function(){ for (const c of children) if (c.toString().startsWith('QQuickShape') && c.data.length"
                         " && c.data[0].fillGradient && c.data[0].fillGradient.centerRadius !== undefined)"
                         " return " + ("c.opacity" if what == "opacity" else "c.data[0].fillGradient.centerX") + "; return -1 })()")

    def hover(self, x, y):
        QTest.mouseMove(self.view, QPoint(x, y))
        QTest.qWait(400)

    def test_light_follows_the_pointer(self):
        self.assertEqual(self.light(), 0, "no light until the pointer is over the glass")
        self.hover(120, 100)
        self.assertEqual(self.light(), 1)
        self.assertAlmostEqual(self.light("x"), 70, delta=1, msg="centred where the pointer is")
        self.assertGreater(self.eval("rimGain"), 1.1, "the rim brightens under the pointer")
        self.hover(5, 5)
        self.assertEqual(self.light(), 0, "gone once the pointer leaves")

    def test_no_light_with_reduce_transparency(self):
        self.set_theme("reduceTransparency", True)
        self.hover(120, 100)
        self.assertEqual(self.light(), 0)

    def test_lifts_then_gives(self):
        self.glass.setProperty("hovered", True)
        QTest.qWait(500)
        self.assertAlmostEqual(self.glass.property("lift"), -1, delta=0.05, msg="lifts under the pointer")
        self.glass.setProperty("pressed", True)
        QTest.qWait(500)
        self.assertLess(self.glass.property("pressScale"), 1, "gives when pressed")
        self.assertAlmostEqual(self.glass.property("lift"), 0, delta=0.05, msg="pressed, it doesn't lift")

    def test_no_lift_with_reduce_motion(self):
        self.set_theme("reduceMotion", True)
        self.glass.setProperty("hovered", True)
        QTest.qWait(400)
        self.assertEqual(self.glass.property("lift"), 0)


class Rim(unittest.TestCase):
    def test_bright_all_the_way_round(self):
        theme = (ROOT / "apps/lib/theme/Theme.qml").read_text()
        for role in ("glassClear", "glassRegular", "menu", "glassControl", "glassDock"):
            block = re.search(role + r"\s*:\s*QtObject \{(.*?)\n    \}", theme, re.S)
            self.assertIsNotNone(block, role)
            alphas = {}
            for name in ("rim", "rimLow"):
                m = re.search(r"property color %s: dark \? \"#([0-9a-f]{2})[0-9a-f]{6}\" : \"#([0-9a-f]{2})[0-9a-f]{6}\"" % name, block.group(1))
                self.assertIsNotNone(m, f"{role}.{name}")
                alphas[name] = (int(m.group(1), 16), int(m.group(2), 16))
            for mode in (0, 1):
                self.assertGreaterEqual(alphas["rimLow"][mode] * 3, alphas["rim"][mode],
                                        f"{role}: the rim doesn't fade away along the edges ({alphas})")

    def test_inner_face(self):
        glass = (ROOT / "apps/lib/Glass.qml").read_text()
        self.assertIn("The inner face", glass)
        self.assertIn("Math.min(root.width, root.height) < 28", glass, "only on glass with room for a thickness")


if __name__ == "__main__":
    unittest.main(verbosity=2)
