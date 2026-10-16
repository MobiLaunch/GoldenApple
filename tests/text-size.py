#!/usr/bin/env python3
"""Text Size reaches CitronOS's own UI: Theme.textScale (desktop.json
textScale, set by Settings › Accessibility) scales body and label text
(Theme.fs; display numerals over 24 px stay) and the controls around it
(Theme.fh), so at 150% a button's label still fits inside it. Every app,
shell part and the setup assistant read the same value."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import re
import sys
import tempfile

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication([])
LIB = QUrl.fromLocalFile(str(ROOT / "apps/lib")).toString()
QML = """import QtQuick
import "%s" as L
import "%s/theme"
Rectangle {
    width: 400; height: 200; color: "white"
    Component.onCompleted: Theme.textScale = %s
    L.Button { objectName: "button"; text: "Erase Disk and Install" }
    Text { objectName: "body"; y: 60; text: "Body"; font.pixelSize: Theme.fs(13) }
    Text { objectName: "display"; y: 100; text: "12:30"; font.pixelSize: Theme.fs(56) }
}
"""


def measure(scale):
    with tempfile.TemporaryDirectory() as t:
        path = Path(t) / "T.qml"
        path.write_text(QML % (LIB, LIB, scale))
        view = QQuickView()
        view.setSource(QUrl.fromLocalFile(str(path)))
        assert view.status() == QQuickView.Ready, [e.toString() for e in view.errors()]
        view.show()
        QTest.qWait(80)
        root = view.rootObject()
        def find(name):
            stack = [root]
            while stack:
                it = stack.pop()
                if it.objectName() == name:
                    return it
                stack.extend(it.childItems())
        button = find("button")
        label = next(c for c in _walk(button) if c.metaObject().className().startswith("QQuickText"))
        out = {"button": button.height(), "label": label.height(), "labelSize": label.property("font").pixelSize(),
               "body": find("body").property("font").pixelSize(), "display": find("display").property("font").pixelSize()}
        view.close()
        return out


def _walk(item):
    yield item
    for c in item.childItems():
        yield from _walk(c)


failures = []
normal, big = measure(1), measure(1.5)
if (normal["body"], normal["button"]) != (13, 26):
    failures.append(f"100% isn't unchanged: {normal}")
if big["body"] != 20 or big["labelSize"] != 20:
    failures.append(f"150% text isn't 1.5×: {big}")
if big["display"] != 56:
    failures.append(f"display numerals should stay: {big}")
if big["button"] < big["label"] + 6:
    failures.append(f"the button didn't grow around its label: {big}")
# Everything reads the one value.
for f, needle in (("apps/lib/AppWindow.qml", "Theme.textScale = d.textScale"), ("apps/setup.qml", "Theme.textScale = prefs.textScale"),
                  ("shell/shell.qml", 'property: "textScale"'), ("apps/settings/panes/AccessibilityPane.qml", 'setPref(["textScale"]')):
    if needle not in (ROOT / f).read_text():
        failures.append(f"{f} doesn't read or write textScale")
left = [m for p in list((ROOT / "apps").rglob("*.qml")) + list((ROOT / "shell").rglob("*.qml"))
        if not str(p).startswith(str(ROOT / "apps/lib/kit")) and "shell/ui" not in str(p) and "lcode/design/" not in str(p)
        for m in re.findall(r"pixelSize:\s*(1\d|2[0-4]|[89])\s*$", p.read_text(), re.M)]
if left:
    failures.append(f"{len(left)} body text sizes don't follow Text Size (use Theme.fs)")
for f in failures:
    print("FAIL:", f)
if not failures:
    print(f"Text Size: 150% scales text {normal['body']}→{big['body']} px and buttons {normal['button']:.0f}→{big['button']:.0f} px")
sys.exit(1 if failures else 0)
