#!/usr/bin/env python3
"""The SDDM login window, staged as scripts/install.sh stages it and run
against a stand-in for SDDM's theme API (sddm, userModel, sessionModel,
config): it loads without QML errors, starts awake with the password field
showing under the user's name, draws the clock and the power buttons, sends
the typed password for the right user and the Golden Gate session on Return,
and clears the field when SDDM says the login failed."""
from __future__ import annotations

from pathlib import Path
import os
import re
import shutil
import sys
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QObject, Property, Signal, Slot, Qt, QUrl, QTimer, QEventLoop, QPoint
from PySide6.QtGui import QGuiApplication, QStandardItemModel, QStandardItem, QKeyEvent
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


class Sddm(QObject):
    loginFailed = Signal()
    loginSucceeded = Signal()

    def __init__(self):
        super().__init__()
        self.logins: list[tuple[str, str, int]] = []

    canSuspend = Property(bool, lambda self: True, constant=True)
    canReboot = Property(bool, lambda self: True, constant=True)
    canPowerOff = Property(bool, lambda self: True, constant=True)

    @Slot(str, str, int)
    def login(self, user, password, session):
        self.logins.append((user, password, session))

    @Slot()
    def suspend(self): pass

    @Slot()
    def reboot(self): pass

    @Slot()
    def powerOff(self): pass


class Model(QStandardItemModel):
    def __init__(self, roles: list[str], rows: list[dict], last_index: int = 0, last_user: str = ""):
        super().__init__()
        self._roles = {Qt.UserRole + 1 + i: r.encode() for i, r in enumerate(roles)}
        for row in rows:
            item = QStandardItem()
            for role, name in self._roles.items():
                item.setData(row.get(name.decode(), ""), role)
            self.appendRow(item)
        self._last_index, self._last_user = last_index, last_user

    def roleNames(self):
        return self._roles

    lastIndex = Property(int, lambda self: self._last_index, constant=True)
    lastUser = Property(str, lambda self: self._last_user, constant=True)
    count = Property(int, lambda self: self.rowCount(), constant=True)


def wait(ms: int) -> None:
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def stage(t: Path) -> Path:
    """What install.sh puts in /usr/share/sddm/themes/golden-gate."""
    install = (ROOT / "scripts/install.sh").read_text()
    T = t / "golden-gate"
    (T / "components").mkdir(parents=True)
    for f in (ROOT / "themes/sddm/golden-gate").iterdir():
        shutil.copy(f, T)
    shutil.copytree(ROOT / "apps/lib", T / "ui")
    shared = re.search(r"for shared in ([^;]+); do", install).group(1).split()
    for name in shared + ["LockSurface.qml", "SystemClockProxy.qml"]:
        shutil.copy(ROOT / "shell/components" / name, T / "components" / name)
    return T


app = QGuiApplication(sys.argv)
with tempfile.TemporaryDirectory() as tmp:
    theme = stage(Path(tmp))
    sddm = Sddm()
    users = Model(["name", "realName", "icon", "homeDir", "needsPassword"],
                  [{"name": "jordan", "realName": "Jordan Avery", "icon": "/nonexistent/jordan.face.icon"}], 0, "jordan")
    sessions = Model(["name", "file", "comment"], [{"name": "Plasma"}, {"name": "Golden Gate"}], 0)
    view = QQuickView()
    errors: list[str] = []
    view.engine().warnings.connect(lambda ws: errors.extend(w.toString() for w in ws))
    ctx = view.rootContext()
    ctx.setContextProperty("sddm", sddm)
    ctx.setContextProperty("userModel", users)
    ctx.setContextProperty("sessionModel", sessions)
    wallpaper = ROOT / "tools/preview/cache/tide.png"
    if not wallpaper.exists():
        wallpaper = Path(tmp) / "tide.png"
        os.system(f"rsvg-convert -w 1440 -h 900 '{ROOT}/prototype/assets/wallpapers/tide.svg' -o '{wallpaper}'")
    ctx.setContextProperty("config", {"background": str(wallpaper)})
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.resize(1440, 900)
    view.setSource(QUrl.fromLocalFile(str(theme / "Main.qml")))
    check(view.status() == QQuickView.Ready, f"the theme loads: {[e.toString() for e in view.errors()]}")
    view.show()
    view.requestActivate()
    wait(1600)
    bad = [e for e in errors if "Cannot open" not in e]
    check(not bad, f"no QML warnings: {bad[:3]}")

    img = view.grabWindow()
    if not img.isNull():
        # The clock: big white numerals in the upper part of the screen.
        white = sum(1 for x in range(400, 1040, 3) for y in range(90, 280, 3) if img.pixelColor(x, y).lightness() > 240)
        check(white > 300, f"the clock is drawn (found {white} white pixels)")
        # Awake from the start: the field's capsule under the name.
        y = 900 - round(900 * 0.085) - 26 - 17
        capsule = img.pixelColor(720 - 80, y)
        check(capsule.blue() < 200 or capsule.lightness() < 150, f"the password field shows at once, got {capsule.name()}")
        # The power buttons' labels, bottom right.
        discs = sum(1 for x in range(1440 - 240, 1440 - 20) for yy in range(900 - 92, 900 - 48)
                    if abs(img.pixelColor(x, yy).lightness() - img.pixelColor(x, 900 - 100).lightness()) > 12)
        labels = discs
        check(labels > 1500, f"Sleep, Restart and Shut Down are drawn (found {labels})")

    root = view.rootObject()
    check(root.property("userDisplay") == "Jordan Avery", f"the user's full name, got {root.property('userDisplay')!r}")
    check(root.property("sessionIndex") == 1, "the Golden Gate session is chosen")
    for ch in "hunter2":
        app.sendEvent(view, QKeyEvent(QKeyEvent.KeyPress, 0, Qt.NoModifier, ch))
        app.sendEvent(view, QKeyEvent(QKeyEvent.KeyRelease, 0, Qt.NoModifier, ch))
    app.sendEvent(view, QKeyEvent(QKeyEvent.KeyPress, Qt.Key_Return, Qt.NoModifier))
    wait(100)
    check(sddm.logins == [("jordan", "hunter2", 1)], f"Return logs in as jordan to Golden Gate, got {sddm.logins}")
    sddm.loginFailed.emit()
    wait(700)
    field_text = [o for o in root.findChildren(QObject) if o.metaObject().className().startswith("QQuickTextInput")]
    check(field_text and all(o.property("text") == "" for o in field_text), "a failed login clears the field")
    check(bool(field_text) and field_text[0].hasActiveFocus(), "the field keeps the keyboard after a failure")
    if os.environ.get("GG_SDDM_SHOT"):
        img.save(os.environ["GG_SDDM_SHOT"])
    view.setSource(QUrl())
    del view

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("SDDM theme: loads, starts awake, logs in with the typed password and clears it on failure")
