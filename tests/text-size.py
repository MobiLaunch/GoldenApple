#!/usr/bin/env python3
"""Text Size reaches CitronOS's own UI: Theme.textScale (desktop.json
textScale, 85% to 150%, set by Settings › Accessibility) scales text
(Theme.fs, and the Theme.font.* roles) and the controls around it
(Theme.fh), so at 150% a button's label still fits inside it. Nothing goes
under 10 px, so 11 and 12 stay apart (CS2-043); titles (25–40 px) scale at
half the rate and display numerals over 40 stay. Every app, shell part and
the setup assistant read the same value. Also the other role tokens
(T-2.7): Theme.radius.* and Theme.motion.*, whose ms follows Reduce Motion."""
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


ROLES = """import QtQuick
import "%s/theme"
QtObject {
    Component.onCompleted: { Theme.textScale = %s; Theme.reduceMotion = %s }
    property var sizes: [Theme.fs(8), Theme.fs(9), Theme.fs(10), Theme.fs(11), Theme.fs(12), Theme.fs(13), Theme.fs(26), Theme.fs(56)]
    property var roles: [Theme.font.caption2.pixelSize, Theme.font.body.pixelSize, Theme.font.headline.weight,
                         Theme.font.largeTitle.pixelSize, Theme.font.largeTitle.family]
    property var radii: [Theme.radius.control, Theme.radius.field, Theme.radius.card, Theme.radius.menu,
                         Theme.radius.panel, Theme.radius.window, Theme.radius.capsule]
    property var motion: [Theme.motion.panel.ms, Theme.motion.panel.duration, Theme.motion.bouncy.ms,
                          Theme.motion.tap.curve.length, Theme.motion.fade]
}
"""


def roles(scale, reduce=False):
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    with tempfile.TemporaryDirectory() as t:
        path = Path(t) / "R.qml"
        path.write_text(ROLES % (LIB, scale, "true" if reduce else "false"))
        engine = QQmlEngine()
        comp = QQmlComponent(engine, QUrl.fromLocalFile(str(path)))
        obj = comp.create()
        assert obj, [e.toString() for e in comp.errors()]
        QTest.qWait(10)
        out = {k: [v for v in obj.property(k).toVariant()] if hasattr(obj.property(k), "toVariant") else list(obj.property(k))
               for k in ("sizes", "roles", "radii", "motion")}
        obj.setProperty("objectName", "done")
        return out


failures = []
small, plain, large, still = roles(0.85), roles(1), roles(1.5), roles(1, reduce=True)
# fs(8) … fs(56) at 85%, 100% and 150%.
if plain["sizes"] != [10, 10, 10, 11, 12, 13, 26, 56]:
    failures.append(f"100%: sizes under 10 come up to 10, the rest stay: {plain['sizes']}")
if small["sizes"] != [10, 10, 10, 10, 10, 11, 24, 56]:
    failures.append(f"85%: smaller, never under 10, display numerals stay: {small['sizes']}")
if large["sizes"] != [12, 14, 15, 17, 18, 20, 33, 56]:
    failures.append(f"150%: 1.5× up to 24, titles at half the rate, display numerals stay: {large['sizes']}")
if plain["roles"][:4] != [10, 13, 600, 26] or large["roles"][1] != 20 or "Display" not in plain["roles"][4]:
    failures.append(f"Theme.font roles: {plain['roles']} (150%: {large['roles']})")
if plain["radii"] != [6, 8, 12, 14, 18, 22, 999]:
    failures.append(f"Theme.radius roles: {plain['radii']}")
panel_ms, panel_dur, bouncy_ms, curve_len, fade = plain["motion"]
if panel_ms != panel_dur or panel_ms < 300 or curve_len < 8 or fade != 155:
    failures.append(f"Theme.motion roles: {plain['motion']}")
if still["motion"][0] != 140 or still["motion"][2] != 0:
    failures.append(f"Reduce Motion: a panel fades in 140 ms and bouncy doesn't move: {still['motion']}")
normal, big = measure(1), measure(1.5)
if (normal["body"], normal["button"]) != (13, 26):
    failures.append(f"100% isn't unchanged: {normal}")
if big["body"] != 20 or big["labelSize"] != 20:
    failures.append(f"150% text isn't 1.5×: {big}")
if big["display"] != 56:   # over 40 px
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
