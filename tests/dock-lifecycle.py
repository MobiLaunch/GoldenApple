#!/usr/bin/env python3
"""Isolated, fixture-only Dock close/reopen and launch cancellation regressions."""
import os
from pathlib import Path
import re
import sys
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview as P
from PySide6.QtCore import QObject, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, QQmlEngine, QQmlExpression
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest


class FixtureSystem(P.Preview):
    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = cmd.toVariant() if hasattr(cmd, "toVariant") else cmd
        line = " ".join(str(c) for c in (cmd or []))
        for pattern, out, code in P.FIXTURES:
            if re.search(pattern, line):
                return {"stdout": out.replace("{scheme}", self._scheme), "stderr": "",
                        "code": 0 if code == "hang" else code, "hang": code == "hang"}
        return {"stdout": "", "stderr": "", "code": 0}


def plain(value):
    return value.toVariant() if hasattr(value, "toVariant") else value


def evaluate(obj, code):
    expr = QQmlExpression(QQmlEngine.contextForObject(obj), obj, code)
    result = expr.evaluate()
    assert not expr.hasError(), expr.error().toString()
    return plain(result[0])


def objects(root):
    pending, seen = [root], set()
    while pending:
        obj = pending.pop()
        if obj in seen:
            continue
        seen.add(obj)
        yield obj
        pending.extend(obj.children())
        if isinstance(obj, QQuickItem):
            pending.extend(obj.childItems())


def wait_for(predicate, timeout=2000):
    for _ in range(timeout // 10):
        if predicate():
            return
        QTest.qWait(10)
    assert predicate(), "condition did not settle"


app = QGuiApplication([])
with tempfile.TemporaryDirectory(prefix="gg-dock-lifecycle-") as folder:
    system = FixtureSystem({"HOME": folder, "XDG_CONFIG_HOME": folder + "/config",
                            "XDG_STATE_HOME": folder + "/state", "GG_WALLPAPER": str(ROOT / "prototype/assets/wallpapers/tide.svg"),
                            "GG_PREVIEW_WINDOWS": "empty"}, str(ROOT / "shell"), "'default'")
    system._icons.setdefault("application-x-executable", ROOT / "icons/custom/apps/terminal.png")
    engine = QQmlApplicationEngine()
    interceptor = P.SingletonDirs()
    engine.addUrlInterceptor(interceptor)
    engine.addImportPath(str(ROOT / "tools/preview/qml"))
    engine.rootContext().setContextProperty("__preview", system)
    engine.setInitialProperties({"targetUrl": QUrl.fromLocalFile(str(ROOT / "tests/fixtures/dock-lifecycle.qml"))})
    engine.load(QUrl.fromLocalFile(str(ROOT / "tools/preview/Desktop.qml")))
    assert engine.rootObjects(), "preview failed to load"
    root = engine.rootObjects()[0]
    QTest.qWait(100)
    found = {o.objectName(): o for o in objects(root) if o.objectName()}
    fixture, dock, launcher = (found[n] for n in ("dockLifecycleFixture", "testDock", "testLauncher"))
    row = found["dockRow"]
    expiry = found["dockRecentExpiry"]
    assert expiry.property("repeat") is False, "the Dock must not poll recent-app state"
    assert not expiry.property("running"), "no cleanup timer while all apps are active"
    evaluate(fixture, "pin([])")
    evaluate(fixture, "windows(['test.alpha', 'test.beta'])")
    wait_for(lambda: len(plain(dock.property("runningIds"))) == 2)
    QTest.qWait(280)

    def slot(name):
        return next((o for o in objects(root) if o.objectName() == "dockSlot:" + name), None)

    alpha, beta = slot("test.alpha"), slot("test.beta")
    full_width, icon_size = row.property("width"), dock.property("baseSize")
    evaluate(fixture, "windows(['test.alpha', 'test.alpha', 'test.beta'])")
    QTest.qWait(30)
    assert slot("test.alpha") == alpha and len(plain(dock.property("runningIds"))) == 2
    evaluate(fixture, "windows(['test.alpha', 'test.beta'])")
    assert plain(dock.property("runningRecords"))["test.alpha"]["phase"] == "active"
    if os.environ.get("GG_DOCK_LIFECYCLE_SHOT"):
        root.grabWindow().save(os.environ["GG_DOCK_LIFECYCLE_SHOT"])
    evaluate(fixture, "windows(['test.beta'])")
    wait_for(lambda: expiry.property("running"), timeout=500)  # Qt.callLater schedules after the current event
    QTest.qWait(300)
    assert slot("test.alpha") == alpha and slot("test.beta") == beta
    assert abs(row.property("width") - full_width) < 0.1, "recent hold must not resize the shelf"
    wait_for(lambda: plain(dock.property("runningRecords"))["test.alpha"]["phase"] == "leaving")
    wait_for(lambda: expiry.property("running"), timeout=500)  # second phase is armed asynchronously
    widths = []
    for _ in range(6):
        widths.append(row.property("width"))
        QTest.qWait(20)
    assert any(b < a - 0.1 for a, b in zip(widths, widths[1:])), widths
    assert all(b <= a + 0.1 for a, b in zip(widths, widths[1:])), widths
    evaluate(fixture, "windows(['test.alpha', 'test.beta'])")
    QTest.qWait(280)
    assert slot("test.alpha") == alpha and slot("test.beta") == beta, "reopen must reuse delegates"
    assert abs(row.property("width") - full_width) < 0.1
    evaluate(fixture, "windows(['test.beta'])")
    wait_for(lambda: "test.alpha" not in plain(dock.property("runningIds")))
    assert slot("test.beta") == beta and dock.property("baseSize") == icon_size
    wait_for(lambda: not expiry.property("running"), timeout=500)  # idle again after final removal
    assert abs(full_width - row.property("width") - (icon_size + 6)) < 0.1

    # The final app's divider must collapse with its slot, with no trailing snap.
    evaluate(fixture, "windows([])")
    wait_for(lambda: plain(dock.property("runningRecords"))["test.beta"]["phase"] == "leaving")
    QTest.qWait(235)
    before = row.property("width")
    wait_for(lambda: not plain(dock.property("runningIds")))
    assert abs(before - row.property("width")) < 0.1, "divider gap jumped at destruction"

    # Pinned apps never depart; last-window close is not app-identity removal.
    evaluate(fixture, "pin(['org.goldengate.Files'])")
    evaluate(fixture, "windows(['org.goldengate.Files'])")
    QTest.qWait(250)
    assert not plain(dock.property("runningIds"))
    pinned_tiles = plain(dock.property("tiles"))
    evaluate(fixture, "windows([])")
    QTest.qWait(1200)
    assert plain(dock.property("tiles")) == pinned_tiles

    evaluate(fixture, "windows(['test.gamma'])")
    QTest.qWait(250)

    # Reduce Motion toggled during departure stops, rather than just disabling
    # the next Behavior. No partially collapsed interactive slot is left behind.
    evaluate(fixture, "windows([])")
    wait_for(lambda: plain(dock.property("runningRecords"))["test.gamma"]["phase"] == "leaving")
    QTest.qWait(40)
    evaluate(fixture, "motion(true)")
    assert slot("test.gamma").property("presence") == 0
    assert not slot("test.gamma").property("enabled")
    QTest.qWait(60)
    assert slot("test.gamma").property("presence") == 0
    wait_for(lambda: not plain(dock.property("runningIds")))
    evaluate(fixture, "motion(false)")

    # Backdrop delegate identity is tested with mock captures, not GPU/network.
    backdrop = next(o for o in objects(root) if o.property("namespace") == "gg-dock" and o.property("windowIds") is not None)
    evaluate(backdrop, "windowIds = ['capture-a', 'capture-b']")
    QTest.qWait(20)
    def capture(ident):
        return next(o for o in objects(root) if o.property("modelData") == ident and o.property("live") is not None)
    retained_capture = capture("capture-b")
    evaluate(backdrop, "windowIds = ['capture-b']")
    QTest.qWait(20)
    assert capture("capture-b") == retained_capture
    evaluate(backdrop, "windowIds = []")

    # A relaunch from the recent slot keeps it while startup is pending.
    evaluate(fixture, "windows(['test.gamma'])")
    QTest.qWait(250)
    evaluate(fixture, "windows([])")
    evaluate(dock, "retainForLaunch(runningRecords['test.gamma'].entry)")
    QTest.qWait(1200)
    assert "test.gamma" in plain(dock.property("runningIds"))
    evaluate(fixture, "windows(['test.gamma'])")

    # Default close creates no fake window, even with a known frame/target.
    evaluate(launcher, "frames = ({ '0x123': { app: 'org.goldengate.Files', workspace: 1, rect: Qt.rect(100,100,700,500) } })")
    assert evaluate(launcher, "windowClosed('0x123')") is False
    assert launcher.property("state_") == "idle"
    evaluate(fixture, "fold()")
    QTest.qWait(50)
    evaluate(fixture, "launch()")
    QTest.qWait(1500)
    assert launcher.property("state_") == "opening", "old close timer cancelled a new launch"
    evaluate(launcher, "reset()")
    evaluate(fixture, "launch()")
    evaluate(fixture, "closeDuringLaunch()")
    assert launcher.property("state_") == "idle", "closed first window left an opening overlay"
    evaluate(fixture, "fold()")
    card = next(o for o in objects(root) if o.objectName() == "launchCard")
    wait_for(lambda: launcher.property("state_") == "closing" and card.property("opacity") < 0.99)
    evaluate(fixture, "launch()")
    QTest.qWait(350)
    assert launcher.property("state_") == "opening", "old close fade cancelled a new launch"
    evaluate(launcher, "reset()")
    evaluate(fixture, "fold()")
    wait_for(lambda: launcher.property("state_") == "idle")
    evaluate(fixture, "launch()")
    evaluate(fixture, "motion(true)")
    assert launcher.property("state_") == "idle"
    evaluate(fixture, "launch()")
    assert fixture.property("launches") == 5 and launcher.property("state_") == "idle"
    evaluate(fixture, "windows([])")
    wait_for(lambda: not plain(dock.property("runningIds")))
    evaluate(fixture, "motion(false)")
    # Crowded icon density may tighten on insertion, but exit never resizes the
    # layer surface/reserved work area, nor grows all surviving icons afterward.
    reserved, surface_height = dock.property("exclusiveZone"), dock.property("implicitHeight")
    evaluate(fixture, "windows(Array.from({length:30}, (_,i) => 'dense.' + i))")
    QTest.qWait(300)
    crowded_size = dock.property("baseSize")
    assert crowded_size < icon_size
    survivor = slot("dense.29")
    evaluate(fixture, "windows(['dense.29'])")
    wait_for(lambda: len(plain(dock.property("runningIds"))) == 1)
    assert slot("dense.29") == survivor and dock.property("baseSize") == crowded_size
    assert dock.property("exclusiveZone") == reserved and dock.property("implicitHeight") == surface_height
    # Pinning an active transient must not leave a second recent/ghost icon.
    evaluate(fixture, "windows(['org.goldengate.Clock'])")
    evaluate(fixture, "pin(['org.goldengate.Clock'])")
    QTest.qWait(30)
    assert "org.goldengate.Clock" not in plain(dock.property("runningIds"))
    engine.deleteLater()
    QTest.qWait(50)

assert "model: ScriptModel { values: bd.windowIds }" in (ROOT / "shell/components/DesktopBackdrop.qml").read_text()
print("PASS: recent hold, smooth slot/divider collapse, stable delegates, reopen reversal, pinned retention, launch timer cancellation, reduced motion, keyed captures")
