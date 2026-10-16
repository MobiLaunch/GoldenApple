#!/usr/bin/env python3
"""Closing and quitting are told apart (apps/lib/AppWindow.qml): ⌘W and the
red button run the window's closeAction, ⌘Q its quitAction; an app that
only guards closing (unsaved changes) is guarded on quit too. A document
app (Notes, TextEdit) keeps running with its window put away, and opening
it again brings the window back; a utility ends with its window. TextEdit,
Notes and LCode's windows wire theirs to save or ask first."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import re
import sys
import tempfile

from PySide6.QtCore import QMetaObject, QObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])
failures = []


def window(extra):
    view = QQuickView()
    fake = preview.Preview({"HOME": tempfile.mkdtemp()}, str(ROOT / "apps"), "'default'")
    view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
    view.engine().rootContext().setContextProperty("__preview", fake)
    c = QQmlComponent(view.engine())
    c.setData(("import QtQuick\nimport \"../apps/lib\"\nAppWindow { objectName: \"w\"; property var log: []\n" + extra + "\n}").encode(),
              QUrl.fromLocalFile(str(ROOT / "tests" / "CloseFixture.qml")))
    if c.status() != QQmlComponent.Ready:
        raise SystemExit("\n".join(e.toString() for e in c.errors()))
    w = c.create()
    QTest.qWait(50)
    return view, c, w


def log(w):
    v = w.property("log")
    return v.toVariant() if hasattr(v, "toVariant") else v


view, c, w = window('closeAction: () => log = log.concat(["close"]); quitAction: () => log = log.concat(["quit"])')
QMetaObject.invokeMethod(w, "closeWindow")
QMetaObject.invokeMethod(w, "quitApp")
if log(w) != ["close", "quit"]:
    failures.append(f"⌘W closes and ⌘Q quits, each its own: {log(w)}")

view2, c2, w2 = window('closeAction: () => log = log.concat(["asked"])')
QMetaObject.invokeMethod(w2, "quitApp")
if log(w2) != ["asked"]:
    failures.append(f"a close guard also guards quitting: {log(w2)}")

view3, c3, w3 = window('documentApp: true; visible: true; onReopened: log = log.concat(["reopened"]); onOpenRequested: (p) => log = log.concat([p])')
QMetaObject.invokeMethod(w3, "closeWindow")
if w3.property("visible") is not False:
    failures.append("a document app's window is put away on close, the app still running")
QMetaObject.invokeMethod(w3, "reopen")
if w3.property("visible") is not True or log(w3) != ["reopened"]:
    failures.append(f"opening it again brings the window back: {w3.property('visible')} {log(w3)}")
ipc = next((h for h in w3.findChildren(QObject) if h.property("target") == "app"), None)
if ipc is None or ipc.property("enabled") is not True:
    failures.append("a document app answers `ipc call app reopen`")

src = (ROOT / "apps/lib/AppWindow.qml").read_text()
if 'sequence: "Ctrl+Q"; onActivated: win.quitApp()' not in src or 'sequence: "Ctrl+W"; onActivated: win.closeWindow()' not in src:
    failures.append("⌘Q and ⌘W reach quitApp and closeWindow")
for f, needle in (("apps/textedit.qml", "editor.requestAction"), ("apps/notes.qml", "editor.flush()"),
                  ("apps/notes.qml", "documentApp: true"), ("apps/textedit.qml", "documentApp: true"),
                  ("apps/desktop/org.goldengate.Notes.desktop", "ipc call app reopen"), ("apps/textedit/open.sh", "ipc call app open"),
                  ("apps/lcode/SettingsWindow.qml", "quitHandler"), ("apps/lcode/Workspace.qml", "app.quitHandler = win.requestClose")):
    if needle not in (ROOT / f).read_text():
        failures.append(f"{f} guards closing ({needle})")
for f in failures:
    print("FAIL:", f)
if not failures:
    print("Windows: ⌘W closes, ⌘Q quits, document apps keep running without a window, and unsaved work is asked about either way")
sys.exit(1 if failures else 0)
