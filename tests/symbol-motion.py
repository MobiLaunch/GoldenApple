#!/usr/bin/env python3
"""A symbol that changes (play → pause, the Wi-Fi bars, mute) replaces its
glyph as SF Symbols do: the old one shrinks and fades as the new one grows
in. Its first glyph just appears, and Reduce Motion swaps at once."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from pathlib import Path
import sys
import tempfile

from PySide6.QtCore import Q_ARG, QMetaObject, QObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication([])

QML = """import QtQuick
import "%s/apps/lib" as L
import "%s/apps/lib/theme"
Rectangle {
    width: 200; height: 100; color: "white"
    function calm(on) { Theme.reduceMotion = on }
    L.Symbol { objectName: "sym"; x: 80; y: 30; size: 40; name: "play"; tone: "dark" }
}
""" % (QUrl.fromLocalFile(str(ROOT)).toString(), QUrl.fromLocalFile(str(ROOT)).toString())


def main() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as t:
        path = Path(t) / "Symbols.qml"
        path.write_text(QML)
        view = QQuickView()
        view.setSource(QUrl.fromLocalFile(str(path)))
        if view.status() != QQuickView.Ready:
            print([e.toString() for e in view.errors()], file=sys.stderr)
            return 1
        view.show()
        QTest.qWait(150)
        sym = view.rootObject().findChild(QObject, "sym")
        old = sym.findChild(QObject, "symbolOutgoing")
        if old.property("opacity") != 0:
            failures.append("the first glyph appears without a swap")
        sym.setProperty("name", "pause")
        QTest.qWait(40)
        mid = (old.property("opacity"), old.property("scale"))
        if not (0 < mid[0] < 1 and mid[1] < 1):
            failures.append(f"the old glyph shrinks and fades as the new one comes in: {mid}")
        if "play" not in old.property("source").toString():
            failures.append(f"the glyph going away is the old one: {old.property('source')}")
        QTest.qWait(400)
        if old.property("opacity") != 0:
            failures.append("the old glyph is gone once the swap ends")
        QMetaObject.invokeMethod(view.rootObject(), "calm", Q_ARG("QVariant", True))
        sym.setProperty("name", "play")
        QTest.qWait(40)
        if old.property("opacity") != 0:
            failures.append("with Reduce Motion the glyph changes at once")
    if failures:
        print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
        return 1
    print("Symbols: a changed glyph replaces the old one as SF Symbols do; Reduce Motion swaps at once")
    return 0


if __name__ == "__main__":
    sys.exit(main())
