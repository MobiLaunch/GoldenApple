#!/usr/bin/env python3
"""CitronOS's own scroll bars (apps/lib/Scroller.qml): hidden until you
scroll (then they fade), always there when Settings › Appearance › Show
scroll bars is Always (Theme.alwaysShowScrollbars, from desktop.json),
never on content that fits; dragging the knob scrolls and clicking the
track pages. The main scroll areas of the apps and shell use them."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile

from PySide6.QtCore import QMetaObject, QPoint, Q_ARG, Qt, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication([])
LIB = QUrl.fromLocalFile(str(ROOT / "apps/lib")).toString()
QML = """import QtQuick
import "%s"
import "%s/theme"
Rectangle {
    width: 300; height: 300; color: "white"
    function always(on) { Theme.alwaysShowScrollbars = on }
    Flickable { id: f; objectName: "f"; width: 300; height: 300; contentHeight: 3000
        Rectangle { width: 300; height: 3000; color: "#eee" } }
    Scroller { objectName: "s"; flickable: f }
    Flickable { id: short; objectName: "short"; y: 0; width: 100; height: 300; contentHeight: 200 }
    Scroller { objectName: "s2"; flickable: short }
}
""" % (LIB, LIB)

failures = []
with tempfile.TemporaryDirectory() as t:
    path = Path(t) / "S.qml"
    path.write_text(QML)
    view = QQuickView()
    view.setSource(QUrl.fromLocalFile(str(path)))
    if view.status() != QQuickView.Ready:
        sys.exit("\n".join(e.toString() for e in view.errors()))
    view.show()
    QTest.qWait(100)
    root = view.rootObject()
    find = lambda n: next(c for c in root.childItems() if c.objectName() == n)
    f, s, s2 = find("f"), find("s"), find("s2")
    if s.property("opacity") != 0:
        failures.append("hidden until you scroll")
    if s2.property("visible"):
        failures.append("no bar on content that fits")
    f.setProperty("contentY", 400)
    QTest.qWait(200)
    if s.property("opacity") < 0.9:
        failures.append(f"shows while scrolling: {s.property('opacity')}")
    QTest.qWait(1600)
    if s.property("opacity") > 0.1:
        failures.append(f"fades after: {s.property('opacity')}")
    QMetaObject.invokeMethod(root, "always", Q_ARG("QVariant", True))
    QTest.qWait(500)
    if s.property("opacity") < 0.9:
        failures.append("always shown when set to Always")
    # Click the track below the knob: a page down.
    before = f.property("contentY")
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(295, 290))
    QTest.qWait(50)
    if not f.property("contentY") > before + 200:
        failures.append(f"clicking the track pages: {before} → {f.property('contentY')}")
    # Drag the knob to the bottom.
    knob = [c for c in s.childItems() if c.property("ratio") is not None][0]
    ky = int(s.y() + knob.y() + knob.height() / 2)
    QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, QPoint(295, ky))
    for y in range(ky, 300, 10):
        QTest.mouseMove(view, QPoint(295, y))
    QTest.mouseMove(view, QPoint(295, 299))
    QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, QPoint(295, 299))
    if f.property("contentY") < 2600:
        failures.append(f"dragging the knob scrolls: {f.property('contentY')}")

users = [p for p in list((ROOT / "apps").rglob("*.qml")) + list((ROOT / "shell").rglob("*.qml"))
         if "Scroller {" in p.read_text() and "lib/Scroller.qml" not in str(p)]
if len(users) < 25:
    failures.append(f"the main scroll areas use it ({len(users)} files)")
for f in failures:
    print("FAIL:", f)
if not failures:
    print(f"Scroll bars: show while scrolling, always on request, drag and page; in {len(users)} files")
sys.exit(1 if failures else 0)
