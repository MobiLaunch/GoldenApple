#!/usr/bin/env python3
"""A prominent destructive button (Erase Disk and Install, Erase, Empty
Trash) is red with white text, not the accent blue of a safe default; a
plain destructive button has red text; a prominent one is the accent."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile

from PySide6.QtCore import QUrl
from PySide6.QtGui import QColor, QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication([])

QML = """import QtQuick
import "%s/apps/lib" as L
Rectangle {
    width: 400; height: 120; color: "white"
    Row {
        spacing: 10
        L.Button { objectName: "erase"; text: "Erase"; prominent: true; destructive: true }
        L.Button { objectName: "ok"; text: "OK"; prominent: true }
        L.Button { objectName: "discard"; text: "Discard"; destructive: true }
    }
}
""" % QUrl.fromLocalFile(str(ROOT)).toString()


def walk(item):
    yield item
    for child in item.childItems():
        yield from walk(child)


def main() -> int:
    with tempfile.TemporaryDirectory() as t:
        path = Path(t) / "Buttons.qml"
        path.write_text(QML)
        view = QQuickView()
        view.setSource(QUrl.fromLocalFile(str(path)))
        if view.status() != QQuickView.Ready:
            print([e.toString() for e in view.errors()], file=sys.stderr)
            return 1
        view.show()
        QTest.qWait(100)
        root = view.rootObject()
        found = {}
        for item in walk(root):
            name = item.objectName()
            if name in ("erase", "ok", "discard"):
                glass = next(c for c in item.childItems() if c.property("tint") is not None)
                text = next(c for c in walk(item) if c.metaObject().className().startswith("QQuickText") and c.property("text"))
                found[name] = (QColor(glass.property("tint")), QColor(text.property("color")))
        failures = []
        tint, text = found["erase"]
        if not (tint.red() > 200 and tint.green() < 90 and tint.blue() < 90):
            failures.append(f"Erase isn't red: {tint.name()}")
        if text.name() != "#ffffff":
            failures.append(f"Erase's text isn't white: {text.name()}")
        tint, _ = found["ok"]
        if tint.blue() < 150 or tint.red() > 120:
            failures.append(f"OK isn't the accent: {tint.name()}")
        _, text = found["discard"]
        if not (text.red() > 200 and text.green() < 90):
            failures.append(f"Discard's text isn't red: {text.name()}")
        for f in failures:
            print("FAIL:", f)
        if not failures:
            print("destructive buttons are red; the default is the accent")
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
